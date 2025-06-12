// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Owned}             from "solmate/auth/Owned.sol";
import {ERC20}             from "solmate/tokens/ERC20.sol";
import {SafeTransferLib}   from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {EnumerableSet}     from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ECDSA}             from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {IEscrow} from "../interface/IEscrow.sol";
import {Errors}  from "../libraries/Errors.sol";

contract Escrow is Owned, IEscrow {
    using SafeTransferLib   for ERC20;
    using EnumerableSet     for EnumerableSet.AddressSet;
    using FixedPointMathLib for uint;

    /* -------------------------------------------------------------------------- */
    /*                                   CONSTANTS                                */
    /* -------------------------------------------------------------------------- */
    uint16 public constant MAX_FEE = 1_000; // 10 %

    bytes32 public constant SET_ADMIN_TYPEHASH =
        keccak256("SetAdmin(uint repoId,uint accountId,address[] admins,uint nonce,uint deadline)");
    bytes32 public constant CLAIM_TYPEHASH =
        keccak256("Claim(uint[] distributionIds,address recipient,uint nonce,uint deadline)");

    /* -------------------------------------------------------------------------- */
    /*                                     TYPES                                  */
    /* -------------------------------------------------------------------------- */
    struct Account {
        mapping(address => uint) balance;          // token → balance
        bool                     hasDistributions; // whether any distributions have occurred
        EnumerableSet.AddressSet admins;           // set of authorized admins
        EnumerableSet.AddressSet distributors;     // set of authorized distributors
        bool                     exists;  
    }

    struct Distribution {
        uint               amount;
        ERC20              token;
        address            recipient;
        uint               claimDeadline; // unix seconds
        DistributionStatus status;        // Distributed → Claimed / Reclaimed
        DistributionType   _type;         // Repo or Solo
        address            payer;
        uint               fee;           // fee rate at creation time (basis points)
        bool               exists;
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
        uint repoId;
        uint accountId;
    }

    /* -------------------------------------------------------------------------- */
    /*                                STATE VARIABLES                             */
    /* -------------------------------------------------------------------------- */
    mapping(uint => mapping(uint => Account)) accounts;      // repoId → accountId → Account

    mapping(uint => Distribution) public distributions;      // distributionId → Distribution
    mapping(uint => RepoAccount)  public distributionToRepo; // distributionId → RepoAccount (for repo distributions)

    mapping(address => uint) public recipientNonce;          // recipient → nonce
    uint                     public ownerNonce;    

    uint    public fee;
    address public feeRecipient;
    uint    public batchLimit; 

    EnumerableSet.AddressSet private _whitelistedTokens;

    address public signer;

    uint public distributionBatchCount;
    uint public distributionCount;

    /* -------------------------------------------------------------------------- */
    /*                               EIP‑712 DOMAIN                               */
    /* -------------------------------------------------------------------------- */
    uint    internal immutable INITIAL_CHAIN_ID;
    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;

    /* -------------------------------------------------------------------------- */
    /*                                 MODIFIERS                                  */
    /* -------------------------------------------------------------------------- */
    modifier onlyRepoAdmin(uint repoId, uint accountId) {
        require(accounts[repoId][accountId].admins.contains(msg.sender), Errors.NOT_REPO_ADMIN);
        _;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 CONSTRUCTOR                                */
    /* -------------------------------------------------------------------------- */
    constructor(
        address          _owner,
        address          _signer,
        address[] memory _initialWhitelist,
        uint             _initialFee,
        uint             _batchLimit
    ) Owned(_owner) {
        require(_initialFee <= MAX_FEE, Errors.INVALID_FEE);

        signer                   = _signer;
        feeRecipient             = _owner;
        fee                      = _initialFee;
        batchLimit               = _batchLimit;
        INITIAL_CHAIN_ID         = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = _domainSeparator();

        for (uint i; i < _initialWhitelist.length; ++i) {
            require(_whitelistedTokens.add(_initialWhitelist[i]), Errors.TOKEN_ALREADY_WHITELISTED);
            emit TokenWhitelisted(_initialWhitelist[i]);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                              INIT REPO ADMIN                               */
    /* -------------------------------------------------------------------------- */
    function initRepo(
        uint      repoId,
        uint      accountId,
        address[] calldata admins,
        uint      deadline,
        uint8     v,
        bytes32   r,
        bytes32   s
    ) external {
        Account storage account = accounts[repoId][accountId];

        require(!account.exists,               Errors.REPO_ALREADY_INITIALIZED);
        require(admins.length   >  0,          Errors.INVALID_AMOUNT);
        require(admins.length   <= batchLimit, Errors.BATCH_LIMIT_EXCEEDED);
        require(block.timestamp <= deadline,   Errors.SIGNATURE_EXPIRED);

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    SET_ADMIN_TYPEHASH,
                    repoId,
                    accountId,
                    keccak256(abi.encode(admins)),
                    ownerNonce,
                    deadline
                ))
            )
        );
        require(ECDSA.recover(digest, v, r, s) == owner, Errors.INVALID_SIGNATURE);

        ownerNonce++;
        account.exists = true;
        
        for (uint i; i < admins.length; ++i) {
            require(admins[i] != address(0), Errors.INVALID_ADDRESS);
            account.admins.add(admins[i]);
            emit AdminSet(repoId, accountId, address(0), admins[i]);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                                   FUND REPO                                */
    /* -------------------------------------------------------------------------- */
    function fundRepo(
        uint  repoId,
        uint  accountId,
        ERC20 token,
        uint  amount,
        bytes calldata data
    ) external {
        require(_whitelistedTokens.contains(address(token)), Errors.INVALID_TOKEN);
        require(amount > 0,                                  Errors.INVALID_AMOUNT);

        token.safeTransferFrom(msg.sender, address(this), amount);

        accounts[repoId][accountId].balance[address(token)] += amount;

        emit Funded(repoId, address(token), msg.sender, amount, data);
    }

    /* -------------------------------------------------------------------------- */
    /*                              DISTRIBUTE REPO / SOLO                        */
    /* -------------------------------------------------------------------------- */
    function distributeFromRepo(
        uint                          repoId,
        uint                          accountId,
        DistributionParams[] calldata _distributions,
        bytes                memory   data
    ) 
        external 
        returns (uint[] memory distributionIds)
    {
        require(_distributions.length <= batchLimit, Errors.BATCH_LIMIT_EXCEEDED);
        
        Account storage account = accounts[repoId][accountId];

        bool isAdmin       = account.admins.contains(msg.sender);
        bool isDistributor = account.distributors.contains(msg.sender);
        require(isAdmin || isDistributor, Errors.NOT_AUTHORIZED_DISTRIBUTOR);
        
        distributionIds          = new uint[](_distributions.length);
        uint distributionBatchId = distributionBatchCount++;

        for (uint i; i < _distributions.length; ++i) {
            DistributionParams calldata distribution = _distributions[i];
            
            uint balance = account.balance[address(distribution.token)];
            require(balance >= distribution.amount, Errors.INSUFFICIENT_BALANCE);
            account.balance[address(distribution.token)] = balance - distribution.amount;

            uint distributionId = _createDistribution(distribution, DistributionType.Repo);
            distributionIds[i]  = distributionId;

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
    function distributeFromSender(
        DistributionParams[] calldata _distributions,
        bytes                calldata data
    ) 
        external 
        returns (uint[] memory distributionIds)
    {
        require(_distributions.length <= batchLimit, Errors.BATCH_LIMIT_EXCEEDED);
        
        distributionIds          = new uint[](_distributions.length);
        uint distributionBatchId = distributionBatchCount++;
        
        for (uint i; i < _distributions.length; ++i) {
            DistributionParams calldata distribution = _distributions[i];
            distribution.token.safeTransferFrom(msg.sender, address(this), distribution.amount);
            uint distributionId = _createDistribution(distribution, DistributionType.Solo);
            distributionIds[i]  = distributionId;

            emit DistributedSolo(
                distributionId,
                msg.sender,
                distribution.recipient,
                address(distribution.token),
                distribution.amount,
                block.timestamp + distribution.claimPeriod
            );
        } 
        emit DistributedSoloBatch(distributionBatchId, distributionIds, data);
    }

    ///
    function _createDistribution(
        DistributionParams calldata distribution,
        DistributionType            _type
    ) 
        internal 
        returns (uint distributionId) 
    {
        require(distribution.recipient  != address(0),                    Errors.INVALID_ADDRESS);
        require(distribution.amount      > 0,                             Errors.INVALID_AMOUNT);
        require(distribution.claimPeriod > 0,                             Errors.INVALID_CLAIM_PERIOD);
        require(_whitelistedTokens.contains(address(distribution.token)), Errors.INVALID_TOKEN);

        // Validate that after fees, recipient will receive at least 1 wei
        uint feeAmount = distribution.amount.mulDivUp(fee, 10_000);
        require(distribution.amount > feeAmount, Errors.INVALID_AMOUNT);

        distributionId = distributionCount++;

        distributions[distributionId] = Distribution({
            amount:        distribution.amount,
            token:         distribution.token,
            recipient:     distribution.recipient,
            claimDeadline: block.timestamp + distribution.claimPeriod,
            status:        DistributionStatus.Distributed,
            exists:        true,
            _type:         _type,
            payer:         _type == DistributionType.Solo ? msg.sender : address(0),
            fee:           fee
        });
    }

    /* -------------------------------------------------------------------------- */
    /*                                   CLAIM                                    */
    /* -------------------------------------------------------------------------- */
    function claim(
        uint[] memory distributionIds,
        uint256       deadline,
        uint8         v,
        bytes32       r,
        bytes32       s
    ) external {
        require(block.timestamp <= deadline,          Errors.SIGNATURE_EXPIRED);
        require(distributionIds.length > 0,           Errors.INVALID_AMOUNT);
        require(distributionIds.length <= batchLimit, Errors.BATCH_LIMIT_EXCEEDED);

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

        for (uint i; i < distributionIds.length; ++i) {
            uint distributionId = distributionIds[i];
            Distribution storage distribution = distributions[distributionId];

            require(distribution.exists,                                      Errors.INVALID_DISTRIBUTION_ID);
            require(distribution.status    == DistributionStatus.Distributed, Errors.ALREADY_CLAIMED);
            require(distribution.recipient == msg.sender,                     Errors.INVALID_RECIPIENT);
            require(block.timestamp        <= distribution.claimDeadline,     Errors.CLAIM_DEADLINE_PASSED);

            distribution.status = DistributionStatus.Claimed;
             
            uint feeAmount = distribution.amount.mulDivUp(distribution.fee, 10_000);
            // Cap fee to ensure recipient gets at least 1 wei
            if (feeAmount >= distribution.amount) {
                feeAmount = distribution.amount - 1;
            }
            uint netAmount = distribution.amount - feeAmount;
            
            if (feeAmount > 0) distribution.token.safeTransfer(feeRecipient, feeAmount);
            distribution.token.safeTransfer(msg.sender, netAmount);
            
            emit Claimed(distributionId, msg.sender, netAmount, distribution.fee);
        }
        emit ClaimedBatch(distributionIds, msg.sender, deadline);
    }

    /* -------------------------------------------------------------------------- */
    /*                                RECLAIM FUND                                */
    /* -------------------------------------------------------------------------- */
    function reclaimFund(
        uint    repoId,
        uint    accountId,
        address token,
        uint    amount
    ) 
        external 
        onlyRepoAdmin(repoId, accountId) 
    {
        require(_whitelistedTokens.contains(token),            Errors.INVALID_TOKEN);
        require(amount > 0,                                    Errors.INVALID_AMOUNT);
        require(!accounts[repoId][accountId].hasDistributions, Errors.REPO_HAS_DISTRIBUTIONS);
        
        uint balance = accounts[repoId][accountId].balance[token];
        require(balance >= amount, Errors.INSUFFICIENT_BALANCE);
        
        accounts[repoId][accountId].balance[token] = balance - amount;
        ERC20(token).safeTransfer(msg.sender, amount);
        
        emit ReclaimedFund(repoId, msg.sender, amount);
    }

    /* -------------------------------------------------------------------------- */
    /*                               RECLAIM REPO                                 */
    /* -------------------------------------------------------------------------- */
    function reclaimRepo(uint[] calldata distributionIds) external {
        require(distributionIds.length <= batchLimit, Errors.BATCH_LIMIT_EXCEEDED);
        
        for (uint i; i < distributionIds.length; ++i) {
            uint distributionId = distributionIds[i];
            Distribution storage distribution = distributions[distributionId];
            
            require(distribution.exists,                                   Errors.INVALID_DISTRIBUTION_ID);
            require(distribution._type  == DistributionType.Repo,          Errors.NOT_REPO_DISTRIBUTION);
            require(distribution.status == DistributionStatus.Distributed, Errors.ALREADY_CLAIMED);
            require(block.timestamp      > distribution.claimDeadline,     Errors.STILL_CLAIMABLE);

            distribution.status = DistributionStatus.Reclaimed;
            
            RepoAccount memory repoAccount = distributionToRepo[distributionId];
            accounts[repoAccount.repoId][repoAccount.accountId].balance[address(distribution.token)] += distribution.amount;
            
            emit ReclaimedRepo(repoAccount.repoId, distributionId, msg.sender, distribution.amount);
        }
        emit ReclaimedRepoBatch(distributionIds);
    }

    /* -------------------------------------------------------------------------- */
    /*                               RECLAIM SOLO                                 */
    /* -------------------------------------------------------------------------- */
    function reclaimSolo(uint[] calldata distributionIds) external {
        require(distributionIds.length <= batchLimit, Errors.BATCH_LIMIT_EXCEEDED);
        
        for (uint i; i < distributionIds.length; ++i) {
            uint              distributionId = distributionIds[i];
            Distribution storage distribution   = distributions[distributionId];
            
            require(distribution.exists,                                   Errors.INVALID_DISTRIBUTION_ID);
            require(distribution._type  == DistributionType.Solo,          Errors.NOT_DIRECT_DISTRIBUTION);
            require(distribution.status == DistributionStatus.Distributed, Errors.ALREADY_CLAIMED);
            require(block.timestamp     >  distribution.claimDeadline,     Errors.STILL_CLAIMABLE);
            
            distribution.status = DistributionStatus.Reclaimed;
            distribution.token.safeTransfer(distribution.payer, distribution.amount);
            
            emit ReclaimedSolo(distributionId, distribution.payer, distribution.amount);
        }
        emit ReclaimedSoloBatch(distributionIds);
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

    function setFee(uint newFee) 
        external 
        onlyOwner 
    {
        require(newFee <= MAX_FEE, Errors.INVALID_FEE);
        fee = newFee;
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

    function setBatchLimit(uint newBatchLimit) 
        external 
        onlyOwner 
    {
        require(newBatchLimit > 0, Errors.INVALID_AMOUNT);
        batchLimit = newBatchLimit;
        emit BatchLimitSet(newBatchLimit);
    }

    /* -------------------------------------------------------------------------- */
    /*                              ONLY REPO ADMIN                              */
    /* -------------------------------------------------------------------------- */
    function addAdmins(uint repoId, uint accountId, address[] calldata admins) 
        external 
        onlyRepoAdmin(repoId, accountId) 
    {
        require(admins.length >  0,          Errors.INVALID_AMOUNT);
        require(admins.length <= batchLimit, Errors.BATCH_LIMIT_EXCEEDED);
        
        Account storage account = accounts[repoId][accountId];
        for (uint i; i < admins.length; ++i) {
            address admin = admins[i];
            require(admin != address(0), Errors.INVALID_ADDRESS);
            if (account.admins.add(admin)) {
                emit AdminSet(repoId, accountId, address(0), admin);
            }
        }
    }

    function removeAdmins(uint repoId, uint accountId, address[] calldata admins) 
        external 
        onlyRepoAdmin(repoId, accountId) 
    {
        require(admins.length > 0,           Errors.INVALID_AMOUNT);
        require(admins.length <= batchLimit, Errors.BATCH_LIMIT_EXCEEDED);
        
        Account storage account = accounts[repoId][accountId];
        
        // Ensure we don't remove all admins
        require(account.admins.length() > admins.length, Errors.CANNOT_REMOVE_ALL_ADMINS);
        
        for (uint i; i < admins.length; ++i) {
            address admin = admins[i];
            if (account.admins.remove(admin)) {
                emit RepoAdminChanged(repoId, admin, address(0));
            }
        }
    }

    function addDistributors(uint repoId, uint accountId, address[] calldata distributors) 
        external 
        onlyRepoAdmin(repoId, accountId) 
    {
        require(distributors.length <= batchLimit, Errors.BATCH_LIMIT_EXCEEDED);
        
        Account storage account = accounts[repoId][accountId];
        for (uint i; i < distributors.length; ++i) {
            address distributor = distributors[i];
            require(distributor != address(0), Errors.INVALID_ADDRESS);
            if (!account.distributors.contains(distributor)) {
                account.distributors.add(distributor);
                emit AddedDistributor(repoId, accountId, distributor);
            }
        }
    }

    function removeDistributors(uint repoId, uint accountId, address[] calldata distributors) 
        external 
        onlyRepoAdmin(repoId, accountId) 
    {
        require(distributors.length <= batchLimit, Errors.BATCH_LIMIT_EXCEEDED);
        
        Account storage account = accounts[repoId][accountId];
        for (uint i; i < distributors.length; ++i) {
            address distributor = distributors[i];
            if (account.distributors.remove(distributor)) {
                emit RemovedDistributor(repoId, accountId, distributor);
            }
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                           DOMAIN‑SEPARATOR LOGIC                           */
    /* -------------------------------------------------------------------------- */
    function _domainSeparator() private view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint chainId,address verifyingContract)"),
                keccak256(bytes("Escrow")),
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
    function getAllAdmins(uint repoId, uint accountId) 
        external 
        view 
        returns (address[] memory admins) 
    {
        EnumerableSet.AddressSet storage adminSet = accounts[repoId][accountId].admins;
        uint len = adminSet.length();
        admins = new address[](len);
        for (uint i; i < len; ++i) {
            admins[i] = adminSet.at(i);
        }
    }

    function getIsAuthorizedAdmin(uint repoId, uint accountId, address admin) 
        external 
        view 
        returns (bool) 
    {
        return accounts[repoId][accountId].admins.contains(admin);
    }

    function getIsAuthorizedDistributor(uint repoId, uint accountId, address distributor) 
        external 
        view 
        returns (bool) 
    {
        return accounts[repoId][accountId].distributors.contains(distributor);
    }

    function canDistribute(uint repoId, uint accountId, address caller) 
        external 
        view 
        returns (bool) 
    {
        return accounts[repoId][accountId].admins.contains(caller) || accounts[repoId][accountId].distributors.contains(caller);
    }

    function getAllDistributors(uint repoId, uint accountId) 
        external 
        view 
        returns (address[] memory distributors) 
    {
        EnumerableSet.AddressSet storage distributorSet = accounts[repoId][accountId].distributors;
        uint len = distributorSet.length();
        distributors = new address[](len);
        for (uint i; i < len; ++i) {
            distributors[i] = distributorSet.at(i);
        }
    }

    function getAccountBalance(uint repoId, uint accountId, address token) 
        external 
        view 
        returns (uint) 
    {
        return accounts[repoId][accountId].balance[token];
    }

    function getAccountHasDistributions(uint repoId, uint accountId) 
        external 
        view 
        returns (bool) 
    {
        return accounts[repoId][accountId].hasDistributions;
    }

    function getAccountExists(uint repoId, uint accountId) 
        external 
        view 
        returns (bool) 
    {
        return accounts[repoId][accountId].exists;
    }

    function getDistribution(uint distributionId) 
        external 
        view 
        returns (Distribution memory) 
    {
        Distribution memory distribution = distributions[distributionId];
        require(distribution.exists, Errors.INVALID_DISTRIBUTION_ID);
        return distribution;
    }

    function getDistributionRepo(uint distributionId) 
        external 
        view 
        returns (RepoAccount memory) 
    {
        require(distributions[distributionId].exists, Errors.INVALID_DISTRIBUTION_ID);
        require(distributions[distributionId]._type == DistributionType.Repo, Errors.NOT_REPO_DISTRIBUTION);
        return distributionToRepo[distributionId];
    }

    function isSoloDistribution(uint distributionId) 
        external 
        view 
        returns (bool) 
    {
        return distributions[distributionId].exists && 
               distributions[distributionId]._type == DistributionType.Solo;
    }

    function getAllWhitelistedTokens() 
        external 
        view 
        returns (address[] memory tokens) 
    {
        uint len = _whitelistedTokens.length();
        tokens   = new address[](len);
        for (uint i; i < len; ++i) tokens[i] = _whitelistedTokens.at(i);
    }

    function isTokenWhitelisted(address token) 
        external 
        view 
        returns (bool) 
    {
        return _whitelistedTokens.contains(token);
    }
}
