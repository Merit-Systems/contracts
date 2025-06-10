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
    enum DistributionType {
        Repo,
        Solo
    }

    struct Account {
        mapping(address => uint256) balance;                 // token → balance
        bool                        hasDistributions;        // whether any distributions have occurred
        address                     admin;                   // admin
        mapping(address => bool)    authorizedDistributors;  // distributor → authorized?
    }

    enum Status { 
        Distributed,
        Claimed,
        Reclaimed
    }

    struct Distribution {
        uint256 amount;
        ERC20   token;
        address recipient;
        uint256 claimDeadline;             // unix seconds
        Status  status;                    // Distributed → Claimed / Reclaimed
        bool    exists;                    // whether this distribution exists
        DistributionType distributionType; // Repo or Solo
        address payer;                     // who paid for this distribution (only used for Solo)
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

    mapping(address => uint256)  public recipientNonce; // recipient → nonce
    uint256                      public ownerNonce;    

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
    modifier isRepoAdmin(uint256 repoId, uint256 accountId) {
        require(msg.sender == accounts[repoId][accountId].admin, Errors.NOT_REPO_ADMIN);
        _;
    }

    modifier isAuthorizedDistributor(uint256 repoId, uint256 accountId) {
        require(
            msg.sender == accounts[repoId][accountId].admin || 
            accounts[repoId][accountId].authorizedDistributors[msg.sender], 
            Errors.NOT_AUTHORIZED_DISTRIBUTOR
        );
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
        require(admin != address(0),         Errors.INVALID_ADDRESS);
        require(block.timestamp <= deadline, Errors.SIGNATURE_EXPIRED);

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
    /*                              DISTRIBUTE REPO                               */
    /* -------------------------------------------------------------------------- */
    function distributeRepo(
        uint256                       repoId,
        uint256                       accountId,
        DistributionParams[] calldata params,
        bytes                memory   data
    ) 
        external 
        isAuthorizedDistributor(repoId, accountId) 
        returns (uint256[] memory distributionIds)
    {
        distributionIds             = new uint256[](params.length);
        uint256 distributionBatchId = distributionBatchCount++;
        Account storage account     = accounts[repoId][accountId];

        for (uint256 i; i < params.length; ++i) {
            DistributionParams calldata param = params[i];
            
            require(param.recipient  != address(0),                    Errors.INVALID_ADDRESS);
            require(param.amount      > 0,                             Errors.INVALID_AMOUNT);
            require(param.claimPeriod > 0,                             Errors.INVALID_CLAIM_PERIOD);
            require(_whitelistedTokens.contains(address(param.token)), Errors.INVALID_TOKEN);

            uint256 balance = account.balance[address(param.token)];
            require(balance >= param.amount, Errors.INSUFFICIENT_BALANCE);
            account.balance[address(param.token)] = balance - param.amount;

            uint256 claimDeadline  = block.timestamp + param.claimPeriod;
            uint256 distributionId = distributionCount++;

            distributions[distributionId] = Distribution({
                amount:            param.amount,
                token:             param.token,
                recipient:         param.recipient,
                claimDeadline:     claimDeadline,
                status:            Status.Distributed,
                exists:            true,
                distributionType:  DistributionType.Repo,
                payer:             address(0)
            });

            // Store reverse mapping for repo distributions
            RepoAccount memory repoAccount;
            repoAccount.repoId = repoId;
            repoAccount.accountId = accountId;
            distributionToRepo[distributionId] = repoAccount;
            account.hasDistributions = true;

            distributionIds[i] = distributionId;
            emit DistributedRepo(distributionBatchId, distributionId, param.recipient, address(param.token), param.amount, claimDeadline);
        } 
        emit DistributedRepoBatch(distributionBatchId, repoId, accountId, distributionIds, data);
    }

    /* -------------------------------------------------------------------------- */
    /*                              DISTRIBUTE SOLO                               */
    /* -------------------------------------------------------------------------- */
    function distributeSolo(DistributionParams[] calldata params) 
        external 
        returns (uint256[] memory distributionIds)
    {
        distributionIds = new uint256[](params.length);
        uint256 distributionBatchId = distributionBatchCount++;
        
        for (uint256 i; i < params.length; ++i) {
            DistributionParams calldata param = params[i];
            
            require(param.recipient  != address(0),                    Errors.INVALID_ADDRESS);
            require(param.amount      > 0,                             Errors.INVALID_AMOUNT);
            require(param.claimPeriod > 0,                             Errors.INVALID_CLAIM_PERIOD);
            require(_whitelistedTokens.contains(address(param.token)), Errors.INVALID_TOKEN);

            // Transfer tokens directly from caller
            param.token.safeTransferFrom(msg.sender, address(this), param.amount);

            uint256 claimDeadline  = block.timestamp + param.claimPeriod;
            uint256 distributionId = distributionCount++;

            distributions[distributionId] = Distribution({
                amount:            param.amount,
                token:             param.token,
                recipient:         param.recipient,
                claimDeadline:     claimDeadline,
                status:            Status.Distributed,
                exists:            true,
                distributionType:  DistributionType.Solo,
                payer:             msg.sender
            });

            distributionIds[i] = distributionId;
            emit DistributedSolo(distributionId, msg.sender, param.recipient, address(param.token), param.amount, claimDeadline);
        } 
        emit DistributedSoloBatch(distributionBatchId, distributionIds);
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
                        keccak256(abi.encodePacked(distributionIds)),
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

            require(distribution.exists,                                  Errors.INVALID_DISTRIBUTION_ID);
            require(distribution.status    == Status.Distributed,         Errors.ALREADY_CLAIMED);
            require(distribution.recipient == msg.sender,                 Errors.INVALID_RECIPIENT);
            require(block.timestamp        <= distribution.claimDeadline, Errors.CLAIM_DEADLINE_PASSED);

            distribution.status = Status.Claimed;
             
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
        isRepoAdmin(repoId, accountId) 
    {
        require(_whitelistedTokens.contains(token),            Errors.INVALID_TOKEN);
        require(amount > 0,                                    Errors.INVALID_AMOUNT);
        require(!accounts[repoId][accountId].hasDistributions, Errors.REPO_HAS_DISTRIBUTIONS);
        
        uint256 balance = accounts[repoId][accountId].balance[token];
        require(balance >= amount, Errors.INSUFFICIENT_BALANCE);
        
        accounts[repoId][accountId].balance[token] = balance - amount;
        ERC20(token).safeTransfer(msg.sender, amount);
        
        emit ReclaimedFund(repoId, type(uint256).max, msg.sender, amount);
    }

    /* -------------------------------------------------------------------------- */
    /*                               RECLAIM REPO                                 */
    /* -------------------------------------------------------------------------- */
    function reclaimRepo(uint256[] calldata distributionIds) external {
        for (uint256 i; i < distributionIds.length; ++i) {
            uint256 distributionId = distributionIds[i];
            Distribution storage d = distributions[distributionId];
            
            require(d.exists,                                       Errors.INVALID_DISTRIBUTION_ID);
            require(d.distributionType == DistributionType.Repo,    Errors.NOT_REPO_DISTRIBUTION);
            require(d.status == Status.Distributed,                 Errors.ALREADY_CLAIMED);
            require(block.timestamp > d.claimDeadline,              Errors.STILL_CLAIMABLE);

            d.status = Status.Reclaimed;
            
            // Use reverse mapping to find which account to credit
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
            
            require(d.exists,                                    Errors.INVALID_DISTRIBUTION_ID);
            require(d.distributionType == DistributionType.Solo, Errors.NOT_DIRECT_DISTRIBUTION);
            require(d.status == Status.Distributed,              Errors.ALREADY_CLAIMED);
            require(d.payer == msg.sender,                       Errors.NOT_ORIGINAL_PAYER);
            require(block.timestamp > d.claimDeadline,           Errors.STILL_CLAIMABLE);
            
            d.status = Status.Reclaimed;
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
    /*                               SET REPO ADMIN                              */
    /* -------------------------------------------------------------------------- */
    function setRepoAdmin(uint256 repoId, uint256 accountId, address newAdmin) 
        external 
        isRepoAdmin(repoId, accountId) 
    {
        require(newAdmin != address(0), Errors.INVALID_ADDRESS);

        address oldAdmin = accounts[repoId][accountId].admin;
        accounts[repoId][accountId].admin = newAdmin;
        emit RepoAdminChanged(repoId, oldAdmin, newAdmin);
    }

    /* -------------------------------------------------------------------------- */
    /*                         DISTRIBUTOR AUTHORIZATION                          */
    /* -------------------------------------------------------------------------- */
    function authorizeDistributor(uint256 repoId, uint256 accountId, address[] calldata distributors) 
        external 
        isRepoAdmin(repoId, accountId) 
    {
        for (uint256 i = 0; i < distributors.length; i++) {
            address distributor = distributors[i];
            require(distributor != address(0), Errors.INVALID_ADDRESS);
            if (!accounts[repoId][accountId].authorizedDistributors[distributor]) {
                accounts[repoId][accountId].authorizedDistributors[distributor] = true;
                emit DistributorAuthorized(repoId, accountId, distributor);
            }
        }
    }

    function deauthorizeDistributor(uint256 repoId, uint256 accountId, address[] calldata distributors) 
        external 
        isRepoAdmin(repoId, accountId) 
    {
        for (uint256 i = 0; i < distributors.length; i++) {
            address distributor = distributors[i];
            if (accounts[repoId][accountId].authorizedDistributors[distributor]) {
                accounts[repoId][accountId].authorizedDistributors[distributor] = false;
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
        return accounts[repoId][accountId].authorizedDistributors[distributor];
    }

    function canDistribute(uint256 repoId, uint256 accountId, address caller) 
        external 
        view 
        returns (bool) 
    {
        return caller == accounts[repoId][accountId].admin || accounts[repoId][accountId].authorizedDistributors[caller];
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
