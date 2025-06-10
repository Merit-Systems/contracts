// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Owned}             from "solmate/auth/Owned.sol";
import {ERC20}             from "solmate/tokens/ERC20.sol";
import {SafeTransferLib}   from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {EnumerableSet}     from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ECDSA}             from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {IEscrowRepo}       from "../interface/IEscrowRepo.sol";
import {Errors}            from "../libraries/EscrowRepoErrors.sol";

contract EscrowRepo is Owned, IEscrowRepo {
    using SafeTransferLib   for ERC20;
    using EnumerableSet     for EnumerableSet.AddressSet;
    using FixedPointMathLib for uint256;

    /* -------------------------------------------------------------------------- */
    /*                                   CONSTANTS                                */
    /* -------------------------------------------------------------------------- */
    uint16 public constant MAX_FEE_BPS = 1_000; // 10 %

    bytes32 public constant SET_ADMIN_TYPEHASH =
        keccak256("SetAdmin(uint256 repoId,uint256 accountId,address admin,uint256 nonce,uint256 deadline)");
    bytes32 public constant CLAIM_TYPEHASH =
        keccak256("Claim(uint256[] distributionIds,address recipient,uint256 nonce,uint256 deadline)");

    /* -------------------------------------------------------------------------- */
    /*                                     TYPES                                  */
    /* -------------------------------------------------------------------------- */
    struct Account {
        mapping(address => uint256) balance;          // token → balance
        bool                        hasDistributions; // whether any distributions have occurred
        address                     admin;            // admin
        mapping(address => bool)    distributors;     // distributor → authorized?
    }

    struct Distribution {
        uint256            amount;
        ERC20              token;
        address            recipient;
        uint256            claimDeadline;      // unix seconds
        bool               exists;             // whether this distribution exists
        DistributionStatus distributionStatus; // Distributed → Claimed / Reclaimed
        DistributionType   distributionType;   // Repo or Solo
        address            payer;              // who paid for this distribution (only used for Solo)
    }

    enum DistributionType {
        Repo,
        Solo
    }

    enum DistributionStatus { 
        Distributed,
        Claimed,
        Reclaimed
    }

    struct DistributionParams {
        uint256 amount;
        address recipient;
        uint32  claimPeriod; // seconds
        ERC20   token;
    }

    struct RepoAccount {
        uint256 repoId;
        uint256 accountId;
    }

    /* -------------------------------------------------------------------------- */
    /*                                STATE VARIABLES                             */
    /* -------------------------------------------------------------------------- */
    mapping(uint256 => mapping(uint256 => Account)) public accounts;  // repoId → accountId → Account

    mapping(uint256 => Distribution) public distributions;            // distributionId → Distribution
    mapping(uint256 => RepoAccount)  public distributionToRepo;       // distributionId → RepoAccount (for repo distributions)

    mapping(address => uint256) public recipientNonce;                // recipient → nonce
    uint256                     public ownerNonce;    

    uint16  public protocolFeeBps;
    address public feeRecipient;

    EnumerableSet.AddressSet private _whitelistedTokens;

    address public signer;

    uint256 public distributionBatchCount;
    uint256 public distributionCount;

    /* -------------------------------------------------------------------------- */
    /*                               EIP‑712 DOMAIN                               */
    /* -------------------------------------------------------------------------- */
    uint256 internal immutable INITIAL_CHAIN_ID;
    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;

    /* -------------------------------------------------------------------------- */
    /*                                 MODIFIERS                                  */
    /* -------------------------------------------------------------------------- */
    modifier onlyRepoAdmin(uint256 repoId, uint256 accountId) {
        require(msg.sender == accounts[repoId][accountId].admin, Errors.NOT_REPO_ADMIN);
        _;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 CONSTRUCTOR                                */
    /* -------------------------------------------------------------------------- */
    constructor(
        address          _owner,
        address          _signer,
        address[] memory _initialWhitelist,
        uint16           _initialFeeBps
    ) Owned(_owner) {
        require(_initialFeeBps <= MAX_FEE_BPS, Errors.INVALID_FEE_BPS);

        signer                   = _signer;
        feeRecipient             = _owner;
        protocolFeeBps           = _initialFeeBps;
        INITIAL_CHAIN_ID         = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = _domainSeparator();

        for (uint256 i; i < _initialWhitelist.length; ++i) {
            _whitelistedTokens.add(_initialWhitelist[i]);
            emit TokenWhitelisted(_initialWhitelist[i]);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                              INIT REPO ADMIN                               */
    /* -------------------------------------------------------------------------- */
    function initRepo(
        uint256 repoId,
        uint256 accountId,
        address admin,
        uint256 deadline,
        uint8   v,
        bytes32 r,
        bytes32 s
    ) external {
        require(accounts[repoId][accountId].admin == address(0), Errors.REPO_ALREADY_INITIALIZED);
        require(admin != address(0),                             Errors.INVALID_ADDRESS);
        require(block.timestamp <= deadline,                     Errors.SIGNATURE_EXPIRED);

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    SET_ADMIN_TYPEHASH,
                    repoId,
                    accountId,
                    admin,
                    ownerNonce,
                    deadline
                ))
            )
        );
        require(ECDSA.recover(digest, v, r, s) == owner, Errors.INVALID_SIGNATURE);

        ownerNonce++;
        address oldAdmin = accounts[repoId][accountId].admin;
        accounts[repoId][accountId].admin = admin;
        emit AdminSet(repoId, accountId, oldAdmin, admin);
    }

    /* -------------------------------------------------------------------------- */
    /*                                   FUND REPO                                */
    /* -------------------------------------------------------------------------- */
    function fundRepo(
        uint256 repoId,
        uint256 accountId,
        ERC20   token,
        uint256 amount
    ) external {
        require(_whitelistedTokens.contains(address(token)), Errors.INVALID_TOKEN);
        require(amount > 0,                                  Errors.INVALID_AMOUNT);

        token.safeTransferFrom(msg.sender, address(this), amount);

        accounts[repoId][accountId].balance[address(token)] += amount;

        emit Funded(repoId, address(token), msg.sender, amount, 0);
    }

    /* -------------------------------------------------------------------------- */
    /*                              DISTRIBUTE REPO / SOLO                        */
    /* -------------------------------------------------------------------------- */
    function distributeRepo(
        uint256                       repoId,
        uint256                       accountId,
        DistributionParams[] calldata _distributions,
        bytes                memory   data
    ) 
        external 
        returns (uint256[] memory distributionIds)
    {
        Account storage account = accounts[repoId][accountId];

        bool isAdmin       = msg.sender == account.admin;
        bool isDistributor = account.distributors[msg.sender];
        require(isAdmin || isDistributor, Errors.NOT_AUTHORIZED_DISTRIBUTOR);
        
        distributionIds             = new uint256[](_distributions.length);
        uint256 distributionBatchId = distributionBatchCount++;

        for (uint256 i; i < _distributions.length; ++i) {
            DistributionParams calldata distribution = _distributions[i];
            
            uint256 balance = account.balance[address(distribution.token)];
            require(balance >= distribution.amount, Errors.INSUFFICIENT_BALANCE);
            account.balance[address(distribution.token)] = balance - distribution.amount;

            uint256 distributionId = _createDistribution(distribution, DistributionType.Repo);
            distributionIds[i] = distributionId;

            distributionToRepo[distributionId] = RepoAccount({
                repoId:    repoId,
                accountId: accountId
            });
            account.hasDistributions = true;

            emit DistributedRepo(
                distributionBatchId,
                distributionId,
                distribution.recipient,
                address(distribution.token),
                distribution.amount,
                block.timestamp + distribution.claimPeriod
            );
        } 
        emit DistributedRepoBatch(distributionBatchId, repoId, accountId, distributionIds, data);
    }

    ///
    function distributeSolo(
        DistributionParams[] calldata _distributions
    ) 
        external 
        returns (uint256[] memory distributionIds)
    {
        distributionIds             = new uint256[](_distributions.length);
        uint256 distributionBatchId = distributionBatchCount++;
        
        for (uint256 i; i < _distributions.length; ++i) {
            DistributionParams calldata distribution = _distributions[i];
            distribution.token.safeTransferFrom(msg.sender, address(this), distribution.amount);
            uint256 distributionId = _createDistribution(distribution, DistributionType.Solo);
            distributionIds[i]     = distributionId;

            emit DistributedSolo(
                distributionId,
                msg.sender,
                distribution.recipient,
                address(distribution.token),
                distribution.amount,
                block.timestamp + distribution.claimPeriod
            );
        } 
        emit DistributedSoloBatch(distributionBatchId, distributionIds);
    }

    function _createDistribution(
        DistributionParams calldata distribution,
        DistributionType            distributionType
    ) 
        internal 
        returns (uint256 distributionId) 
    {
        require(distribution.recipient  != address(0),                    Errors.INVALID_ADDRESS);
        require(distribution.amount      > 0,                             Errors.INVALID_AMOUNT);
        require(distribution.claimPeriod > 0,                             Errors.INVALID_CLAIM_PERIOD);
        require(_whitelistedTokens.contains(address(distribution.token)), Errors.INVALID_TOKEN);

        uint256 claimDeadline = block.timestamp + distribution.claimPeriod;
        
        distributionId = distributionCount++;

        distributions[distributionId] = Distribution({
            amount:             distribution.amount,
            token:              distribution.token,
            recipient:          distribution.recipient,
            claimDeadline:      claimDeadline,
            distributionStatus: DistributionStatus.Distributed,
            exists:             true,
            distributionType:   distributionType,
            payer:              distributionType == DistributionType.Solo ? msg.sender : address(0)
        });
    }

    /* -------------------------------------------------------------------------- */
    /*                                   CLAIM                                    */
    /* -------------------------------------------------------------------------- */
    function claim(
        uint256[] memory distributionIds,
        uint256          deadline,
        uint8            v,
        bytes32          r,
        bytes32          s
    ) external {
        require(block.timestamp <= deadline, Errors.SIGNATURE_EXPIRED);
        require(distributionIds.length > 0,  Errors.INVALID_AMOUNT);

        require(ECDSA.recover(
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(
                        CLAIM_TYPEHASH,
                        keccak256(abi.encode(distributionIds)),
                        msg.sender,
                        recipientNonce[msg.sender],
                        deadline
                    ))
                )
            ), v, r, s) == signer, Errors.INVALID_SIGNATURE);

        recipientNonce[msg.sender]++;

        for (uint256 i; i < distributionIds.length; ++i) {
            uint256 distributionId = distributionIds[i];
            Distribution storage distribution = distributions[distributionId];

            require(distribution.exists,                                               Errors.INVALID_DISTRIBUTION_ID);
            require(distribution.distributionStatus == DistributionStatus.Distributed, Errors.ALREADY_CLAIMED);
            require(distribution.recipient          == msg.sender,                     Errors.INVALID_RECIPIENT);
            require(block.timestamp                 <= distribution.claimDeadline,     Errors.CLAIM_DEADLINE_PASSED);

            distribution.distributionStatus = DistributionStatus.Claimed;
             
            uint256 fee       = distribution.amount.mulDivUp(protocolFeeBps, 10_000);
            uint256 netAmount = distribution.amount - fee;
            require(netAmount > 0, Errors.INVALID_AMOUNT);
            
            if (fee > 0) distribution.token.safeTransfer(feeRecipient, fee);
            distribution.token.safeTransfer(msg.sender, netAmount);
            
            emit Claimed(distributionId, msg.sender, netAmount, fee);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                                RECLAIM FUND                                */
    /* -------------------------------------------------------------------------- */
    function reclaimFund(
        uint256 repoId,
        uint256 accountId,
        address token,
        uint256 amount
    ) 
        external 
        onlyRepoAdmin(repoId, accountId) 
    {
        require(_whitelistedTokens.contains(token),            Errors.INVALID_TOKEN);
        require(amount > 0,                                    Errors.INVALID_AMOUNT);
        require(!accounts[repoId][accountId].hasDistributions, Errors.REPO_HAS_DISTRIBUTIONS);
        
        uint256 balance = accounts[repoId][accountId].balance[token];
        require(balance >= amount, Errors.INSUFFICIENT_BALANCE);
        
        accounts[repoId][accountId].balance[token] = balance - amount;
        ERC20(token).safeTransfer(msg.sender, amount);
        
        emit ReclaimedFund(repoId, msg.sender, amount);
    }

    /* -------------------------------------------------------------------------- */
    /*                               RECLAIM REPO                                 */
    /* -------------------------------------------------------------------------- */
    function reclaimRepo(uint256[] calldata distributionIds) external {
        for (uint256 i; i < distributionIds.length; ++i) {
            uint256 distributionId = distributionIds[i];
            Distribution storage d = distributions[distributionId];
            
            require(d.exists,                                               Errors.INVALID_DISTRIBUTION_ID);
            require(d.distributionType   == DistributionType.Repo,          Errors.NOT_REPO_DISTRIBUTION);
            require(d.distributionStatus == DistributionStatus.Distributed, Errors.ALREADY_CLAIMED);
            require(block.timestamp      >  d.claimDeadline,                Errors.STILL_CLAIMABLE);

            d.distributionStatus = DistributionStatus.Reclaimed;
            
            RepoAccount memory repoAccount = distributionToRepo[distributionId];
            accounts[repoAccount.repoId][repoAccount.accountId].balance[address(d.token)] += d.amount;
            
            emit ReclaimedRepo(repoAccount.repoId, distributionId, msg.sender, d.amount);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                               RECLAIM SOLO                                 */
    /* -------------------------------------------------------------------------- */
    function reclaimSolo(uint256[] calldata distributionIds) external {
        for (uint256 i; i < distributionIds.length; ++i) {
            uint256 distributionId = distributionIds[i];
            Distribution storage d = distributions[distributionId];
            
            require(d.exists,                                               Errors.INVALID_DISTRIBUTION_ID);
            require(d.distributionType   == DistributionType.Solo,          Errors.NOT_DIRECT_DISTRIBUTION);
            require(d.distributionStatus == DistributionStatus.Distributed, Errors.ALREADY_CLAIMED);
            require(d.payer              == msg.sender,                     Errors.NOT_ORIGINAL_PAYER);
            require(block.timestamp      >  d.claimDeadline,                Errors.STILL_CLAIMABLE);
            
            d.distributionStatus = DistributionStatus.Reclaimed;
            d.token.safeTransfer(msg.sender, d.amount);
            
            emit ReclaimedSolo(distributionId, msg.sender, d.amount);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                              ONLY OWNER                                    */
    /* -------------------------------------------------------------------------- */
    function addWhitelistedToken(address token) 
        external 
        onlyOwner 
    {
        require(_whitelistedTokens.add(token), Errors.TOKEN_ALREADY_WHITELISTED);
        emit TokenWhitelisted(token);
    }

    function removeWhitelistedToken(address token) 
        external 
        onlyOwner 
    {
        require(_whitelistedTokens.remove(token), Errors.TOKEN_NOT_WHITELISTED);
        emit TokenRemovedFromWhitelist(token);
    }

    function setProtocolFee(uint16 newFeeBps) 
        external 
        onlyOwner 
    {
        require(newFeeBps <= MAX_FEE_BPS, Errors.INVALID_FEE_BPS);
        protocolFeeBps = newFeeBps;
    }

    function setFeeRecipient(address newRec) 
        external 
        onlyOwner 
    {
        feeRecipient = newRec;
    }

    function setSigner(address newSigner) 
        external 
        onlyOwner 
    {
        signer = newSigner;
    }

    /* -------------------------------------------------------------------------- */
    /*                              ONLY REPO ADMIN                              */
    /* -------------------------------------------------------------------------- */
    function setRepoAdmin(uint256 repoId, uint256 accountId, address newAdmin) 
        external 
        onlyRepoAdmin(repoId, accountId) 
    {
        require(newAdmin != address(0), Errors.INVALID_ADDRESS);

        address oldAdmin = accounts[repoId][accountId].admin;
        accounts[repoId][accountId].admin = newAdmin;
        emit RepoAdminChanged(repoId, oldAdmin, newAdmin);
    }

    function authorizeDistributor(uint256 repoId, uint256 accountId, address[] calldata distributors) 
        external 
        onlyRepoAdmin(repoId, accountId) 
    {
        for (uint256 i; i < distributors.length; ++i) {
            address distributor = distributors[i];
            require(distributor != address(0), Errors.INVALID_ADDRESS);
            if (!accounts[repoId][accountId].distributors[distributor]) {
                accounts[repoId][accountId].distributors[distributor] = true;
                emit DistributorAuthorized(repoId, accountId, distributor);
            }
        }
    }

    function deauthorizeDistributor(uint256 repoId, uint256 accountId, address[] calldata distributors) 
        external 
        onlyRepoAdmin(repoId, accountId) 
    {
        for (uint256 i; i < distributors.length; ++i) {
            address distributor = distributors[i];
            if (accounts[repoId][accountId].distributors[distributor]) {
                accounts[repoId][accountId].distributors[distributor] = false;
                emit DistributorDeauthorized(repoId, accountId, distributor);
            }
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                           DOMAIN‑SEPARATOR LOGIC                           */
    /* -------------------------------------------------------------------------- */
    function _domainSeparator() private view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("EscrowRepo")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return block.chainid == INITIAL_CHAIN_ID ? INITIAL_DOMAIN_SEPARATOR : _domainSeparator();
    }

    /* -------------------------------------------------------------------------- */
    /*                                   GETTERS                                  */
    /* -------------------------------------------------------------------------- */
    function getAccountAdmin(uint256 repoId, uint256 accountId) 
        external 
        view 
        returns (address) 
    {
        return accounts[repoId][accountId].admin;
    }

    function getIsAuthorizedDistributor(uint256 repoId, uint256 accountId, address distributor) 
        external 
        view 
        returns (bool) 
    {
        return accounts[repoId][accountId].distributors[distributor];
    }

    function canDistribute(uint256 repoId, uint256 accountId, address caller) 
        external 
        view 
        returns (bool) 
    {
        return caller == accounts[repoId][accountId].admin || accounts[repoId][accountId].distributors[caller];
    }

    function getAccountBalance(uint256 repoId, uint256 accountId, address token) 
        external 
        view 
        returns (uint256) 
    {
        return accounts[repoId][accountId].balance[token];
    }

    function getAccountHasDistributions(uint256 repoId, uint256 accountId) 
        external 
        view 
        returns (bool) 
    {
        return accounts[repoId][accountId].hasDistributions;
    }

    function getDistribution(uint256 distributionId) 
        external 
        view 
        returns (Distribution memory) 
    {
        Distribution memory distribution = distributions[distributionId];
        require(distribution.exists, Errors.INVALID_DISTRIBUTION_ID);
        return distribution;
    }

    function getDistributionRepo(uint256 distributionId) 
        external 
        view 
        returns (RepoAccount memory) 
    {
        require(distributions[distributionId].exists, Errors.INVALID_DISTRIBUTION_ID);
        require(distributions[distributionId].distributionType == DistributionType.Repo, Errors.NOT_REPO_DISTRIBUTION);
        return distributionToRepo[distributionId];
    }

    function isSoloDistribution(uint256 distributionId) 
        external 
        view 
        returns (bool) 
    {
        return distributions[distributionId].exists && 
               distributions[distributionId].distributionType == DistributionType.Solo;
    }

    function getAllWhitelistedTokens() 
        external 
        view 
        returns (address[] memory tokens) 
    {
        uint256 len = _whitelistedTokens.length();
        tokens = new address[](len);
        for (uint256 i; i < len; ++i) tokens[i] = _whitelistedTokens.at(i);
    }

    function isTokenWhitelisted(address token) 
        external 
        view 
        returns (bool) 
    {
        return _whitelistedTokens.contains(token);
    }
}
