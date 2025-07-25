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

/// @author shafu
contract Escrow is Owned, IEscrow {
    using SafeTransferLib   for ERC20;
    using EnumerableSet     for EnumerableSet.AddressSet;
    using FixedPointMathLib for uint;

    /* -------------------------------------------------------------------------- */
    /*                                   CONSTANTS                                */
    /* -------------------------------------------------------------------------- */
    uint16 public constant MAX_FEE = 1_000; // 10 %

    bytes32 public constant SET_ADMIN_TYPEHASH =
        keccak256("SetAdmin(uint256 repoId,uint256 instanceId,address[] admins,uint256 nonce,uint256 signatureDeadline)");
    bytes32 public constant CLAIM_TYPEHASH =
        keccak256("Claim(uint256[] distributionIds,address recipient,uint256 nonce,uint256 signatureDeadline)");

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
        address            payer;
        address            recipient;
        uint               claimDeadline; // unix seconds
        uint               fee;           // fee rate at creation time (basis points)
        DistributionStatus status;        // Distributed → Claimed / Reclaimed
        DistributionType   _type;         // Repo or Solo
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
        uint instanceId;
    }

    /* -------------------------------------------------------------------------- */
    /*                                STATE VARIABLES                             */
    /* -------------------------------------------------------------------------- */
    mapping(uint => mapping(uint => Account)) accounts;                                             // repoId → instanceId → Account
    mapping(uint => mapping(uint => mapping(address => mapping(address => uint)))) public fundings; // repoId → instanceId → token → funder → amount

    mapping(uint => Distribution) public distributions;      // distributionId → Distribution
    mapping(uint => RepoAccount)  public distributionToRepo; // distributionId → RepoAccount (for repo distributions)

    mapping(uint => mapping(uint => uint)) public repoSetAdminNonce;   // repoId → instanceId → nonce
    mapping(address => uint)               public recipientClaimNonce; // recipient → nonce

    uint    public feeOnFund;
    uint    public feeOnClaim;
    address public feeRecipient;
    uint    public batchLimit; 

    EnumerableSet.AddressSet private whitelistedTokens;

    address public signer;

    uint public batchCount;
    uint public distributionCount;

    /* -------------------------------------------------------------------------- */
    /*                               EIP‑712 DOMAIN                               */
    /* -------------------------------------------------------------------------- */
    uint    internal immutable INITIAL_CHAIN_ID;
    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;

    /* -------------------------------------------------------------------------- */
    /*                                 MODIFIERS                                  */
    /* -------------------------------------------------------------------------- */
    modifier onlyRepoAdmin(uint repoId, uint instanceId) {
        require(accounts[repoId][instanceId].admins.contains(msg.sender), Errors.NOT_REPO_ADMIN);
        _;
    }

    modifier onlyRepoAdminOrDistributor(uint repoId, uint instanceId) {
        Account storage account = accounts[repoId][instanceId];
        bool isAdmin            = account.admins.contains(msg.sender);
        bool isDistributor      = account.distributors.contains(msg.sender);
        require(isAdmin || isDistributor, Errors.NOT_REPO_ADMIN_OR_DISTRIBUTOR);
        _;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 CONSTRUCTOR                                */
    /* -------------------------------------------------------------------------- */
    constructor(
        address          _owner,
        address          _signer,
        address[] memory _whitelistedTokens,
        uint             _feeOnClaim,
        uint             _batchLimit
    ) Owned(_owner) {
        require(_feeOnClaim <= MAX_FEE, Errors.INVALID_FEE);

        signer                   = _signer;
        feeRecipient             = _owner;
        feeOnClaim               = _feeOnClaim;
        batchLimit               = _batchLimit;
        INITIAL_CHAIN_ID         = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = _domainSeparator();

        for (uint i; i < _whitelistedTokens.length; ++i) {
            require(whitelistedTokens.add(_whitelistedTokens[i]), Errors.TOKEN_ALREADY_WHITELISTED);
            emit WhitelistedToken(_whitelistedTokens[i]);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                              INIT REPO ADMIN                               */
    /* -------------------------------------------------------------------------- */
    function initRepo(
        uint      repoId,
        uint      instanceId,
        address[] calldata admins,
        uint      signatureDeadline,
        uint8     v,
        bytes32   r,
        bytes32   s
    ) external {
        Account storage account = accounts[repoId][instanceId];

        require(!account.exists,                      Errors.REPO_ALREADY_INITIALIZED);
        require(admins.length   >  0,                 Errors.INVALID_AMOUNT);
        require(admins.length   <= batchLimit,        Errors.BATCH_LIMIT_EXCEEDED);
        require(block.timestamp <= signatureDeadline, Errors.SIGNATURE_EXPIRED);

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    SET_ADMIN_TYPEHASH,
                    repoId,
                    instanceId,
                    keccak256(abi.encode(admins)),
                    repoSetAdminNonce[repoId][instanceId],
                    signatureDeadline
                ))
            )
        );
        require(ECDSA.recover(digest, v, r, s) == signer, Errors.INVALID_SIGNATURE);

        repoSetAdminNonce[repoId][instanceId]++;
        account.exists = true;
        
        for (uint i; i < admins.length; ++i) {
            require(admins[i] != address(0), Errors.INVALID_ADDRESS);
            account.admins.add(admins[i]);
            emit AddedAdmin(repoId, instanceId, address(0), admins[i]);
        }
        
        emit InitializedRepo(repoId, instanceId, admins);
    }

    /* -------------------------------------------------------------------------- */
    /*                                   FUND REPO                                */
    /* -------------------------------------------------------------------------- */
    function fundRepo(
        uint  repoId,
        uint  instanceId,
        ERC20 token,
        uint  amount,
        bytes calldata data
    ) external {
        require(whitelistedTokens.contains(address(token)), Errors.INVALID_TOKEN);
        require(amount > 0,                                 Errors.INVALID_AMOUNT);

        token.safeTransferFrom(msg.sender, address(this), amount);

        uint feeAmount = amount.mulDivUp(feeOnFund, 10_000);
        require(amount > feeAmount, Errors.INVALID_AMOUNT);

        if (feeAmount > 0) token.safeTransfer(feeRecipient, feeAmount);

        uint netAmount = amount - feeAmount;

        accounts[repoId][instanceId].balance[address(token)]     += netAmount;
        fundings[repoId][instanceId][address(token)][msg.sender] += netAmount;

        emit FundedRepo(repoId, instanceId, address(token), msg.sender, netAmount, feeAmount, data);
    }

    /* -------------------------------------------------------------------------- */
    /*                              DISTRIBUTE REPO / SOLO                        */
    /* -------------------------------------------------------------------------- */
    function distributeFromRepo(
        uint                          repoId,
        uint                          instanceId,
        DistributionParams[] calldata _distributions,
        bytes                memory   data
    ) 
        external 
        onlyRepoAdminOrDistributor(repoId, instanceId)
        returns (uint[] memory distributionIds)
    {
        require(_distributions.length >  0,          Errors.EMPTY_ARRAY);
        require(_distributions.length <= batchLimit, Errors.BATCH_LIMIT_EXCEEDED);
        
        Account storage account  = accounts[repoId][instanceId];
        account.hasDistributions = true;
        
        distributionIds = new uint[](_distributions.length);
        uint batchId    = batchCount++;

        for (uint i; i < _distributions.length; ++i) {
            DistributionParams calldata distribution = _distributions[i];
            
            uint balance = account.balance[address(distribution.token)];
            require(balance >= distribution.amount, Errors.INSUFFICIENT_BALANCE);
            account.balance[address(distribution.token)] = balance - distribution.amount;

            uint distributionId = _createDistribution(distribution, DistributionType.Repo);
            distributionIds[i]  = distributionId;

            distributionToRepo[distributionId] = RepoAccount({
                repoId:     repoId,
                instanceId: instanceId
            });

            emit DistributedFromRepo(
                batchId,
                distributionId,
                distribution.recipient,
                address(distribution.token),
                distribution.amount,
                block.timestamp + distribution.claimPeriod
            );
        } 
        emit DistributedFromRepoBatch(batchId, repoId, instanceId, distributionIds, data);
    }

    ///
    function distributeFromSender(
        DistributionParams[] calldata _distributions,
        bytes                calldata data
    ) 
        external 
        returns (uint[] memory distributionIds)
    {
        require(_distributions.length >  0,          Errors.EMPTY_ARRAY);
        require(_distributions.length <= batchLimit, Errors.BATCH_LIMIT_EXCEEDED);
        
        distributionIds = new uint[](_distributions.length);
        uint batchId    = batchCount++;
        
        for (uint i; i < _distributions.length; ++i) {
            DistributionParams calldata distribution = _distributions[i];
            distribution.token.safeTransferFrom(msg.sender, address(this), distribution.amount);
            uint distributionId = _createDistribution(distribution, DistributionType.Solo);
            distributionIds[i]  = distributionId;

            emit DistributedFromSender(
                batchId,
                distributionId,
                msg.sender,
                distribution.recipient,
                address(distribution.token),
                distribution.amount,
                block.timestamp + distribution.claimPeriod
            );
        } 
        emit DistributedFromSenderBatch(batchId, distributionIds, data);
    }

    ///
    function _createDistribution(
        DistributionParams calldata distribution,
        DistributionType            _type
    ) 
        internal 
        returns (uint distributionId) 
    {
        require(distribution.recipient  != address(0),                   Errors.INVALID_ADDRESS);
        require(distribution.amount      > 0,                            Errors.INVALID_AMOUNT);
        require(whitelistedTokens.contains(address(distribution.token)), Errors.INVALID_TOKEN);

        uint feeAmount = distribution.amount.mulDivUp(feeOnClaim, 10_000);
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
            fee:           feeOnClaim
        });
    }

    /* -------------------------------------------------------------------------- */
    /*                                   CLAIM                                    */
    /* -------------------------------------------------------------------------- */
    function claim(
        uint[] memory  distributionIds,
        uint256        signatureDeadline,
        uint8          v,
        bytes32        r,
        bytes32        s,
        bytes calldata data
    ) external {
        require(block.timestamp        <= signatureDeadline, Errors.SIGNATURE_EXPIRED);
        require(distributionIds.length >  0,                 Errors.INVALID_AMOUNT);
        require(distributionIds.length <= batchLimit,        Errors.BATCH_LIMIT_EXCEEDED);

        uint batchId = batchCount++;

        require(ECDSA.recover(
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(
                        CLAIM_TYPEHASH,
                        keccak256(abi.encode(distributionIds)),
                        msg.sender,
                        recipientClaimNonce[msg.sender],
                        signatureDeadline
                    ))
                )
            ), v, r, s) == signer, Errors.INVALID_SIGNATURE);

        recipientClaimNonce[msg.sender]++;

        for (uint i; i < distributionIds.length; ++i) {
            uint distributionId = distributionIds[i];
            Distribution storage distribution = distributions[distributionId];

            require(distribution.exists,                                      Errors.INVALID_DISTRIBUTION_ID);
            require(distribution.status    == DistributionStatus.Distributed, Errors.ALREADY_CLAIMED);
            require(distribution.recipient == msg.sender,                     Errors.INVALID_RECIPIENT);

            distribution.status = DistributionStatus.Claimed;
             
            uint feeAmount = distribution.amount.mulDivUp(distribution.fee, 10_000);
            uint netAmount = distribution.amount - feeAmount;
            
            if (feeAmount > 0) distribution.token.safeTransfer(feeRecipient, feeAmount);
            distribution.token.safeTransfer(msg.sender, netAmount);
            
            emit Claimed(batchId, distributionId, msg.sender, netAmount, feeAmount);
        }
        emit ClaimedBatch(batchId, distributionIds, msg.sender, data);
    }

    /* -------------------------------------------------------------------------- */
    /*                                RECLAIM FUNDS                                */
    /* -------------------------------------------------------------------------- */
    function reclaimRepoFunds(
        uint    repoId,
        uint    instanceId,
        address token,
        uint    amount
    ) 
        external 
    {
        require(whitelistedTokens.contains(token),              Errors.INVALID_TOKEN);
        require(amount > 0,                                     Errors.INVALID_AMOUNT);
        require(!accounts[repoId][instanceId].hasDistributions, Errors.REPO_HAS_DISTRIBUTIONS);
        
        uint funding = fundings[repoId][instanceId][token][msg.sender];
        require(funding >= amount, Errors.INSUFFICIENT_FUNDS);
        
        uint balance = accounts[repoId][instanceId].balance[token];
        require(balance >= amount, Errors.INSUFFICIENT_BALANCE);
        
        accounts[repoId][instanceId].balance[token]     -= amount;
        fundings[repoId][instanceId][token][msg.sender] -= amount;
        
        ERC20(token).safeTransfer(msg.sender, amount);
        
        emit ReclaimedRepoFunds(repoId, instanceId, token, msg.sender, amount);
    }

    /* -------------------------------------------------------------------------- */
    /*                               RECLAIM REPO DISTRIBUTIONS                   */
    /* -------------------------------------------------------------------------- */
    function reclaimRepoDistributions(
        uint            repoId,
        uint            instanceId,
        uint[] calldata distributionIds,
        bytes  calldata data
    ) 
        external 
        onlyRepoAdminOrDistributor(repoId, instanceId) 
    {
        require(distributionIds.length >  0,          Errors.EMPTY_ARRAY);
        require(distributionIds.length <= batchLimit, Errors.BATCH_LIMIT_EXCEEDED);

        uint batchId = batchCount++;
        
        for (uint i; i < distributionIds.length; ++i) {
            uint distributionId = distributionIds[i];
            Distribution storage distribution = distributions     [distributionId];
            RepoAccount  memory repoAccount   = distributionToRepo[distributionId];
            
            require(distribution.exists,                                                  Errors.INVALID_DISTRIBUTION_ID);
            require(distribution._type  == DistributionType.Repo,                         Errors.NOT_REPO_DISTRIBUTION);
            require(distribution.status == DistributionStatus.Distributed,                Errors.ALREADY_CLAIMED);
            require(block.timestamp     >= distribution.claimDeadline,                    Errors.STILL_CLAIMABLE);
            require(repoAccount.repoId == repoId && repoAccount.instanceId == instanceId, Errors.DISTRIBUTION_NOT_FROM_REPO);

            distribution.status = DistributionStatus.Reclaimed;
            
            accounts[repoAccount.repoId][repoAccount.instanceId].balance[address(distribution.token)] += distribution.amount;
            
            emit ReclaimedRepoDistribution(batchId, distributionId, msg.sender, distribution.amount);
        }
        emit ReclaimedRepoDistributionsBatch(batchId, repoId, instanceId, distributionIds, data);
    }

    /* -------------------------------------------------------------------------- */
    /*                               RECLAIM SENDER DISTRIBUTIONS                 */
    /* -------------------------------------------------------------------------- */
    function reclaimSenderDistributions(
        uint[] calldata distributionIds,
        bytes  calldata data
    ) external {
        require(distributionIds.length >  0,          Errors.EMPTY_ARRAY);
        require(distributionIds.length <= batchLimit, Errors.BATCH_LIMIT_EXCEEDED);

        uint batchId = batchCount++;
        
        for (uint i; i < distributionIds.length; ++i) {
            uint                 distributionId = distributionIds[i];
            Distribution storage distribution   = distributions[distributionId];
            
            require(distribution.exists,                                   Errors.INVALID_DISTRIBUTION_ID);
            require(distribution._type  == DistributionType.Solo,          Errors.NOT_DIRECT_DISTRIBUTION);
            require(distribution.status == DistributionStatus.Distributed, Errors.ALREADY_CLAIMED);
            require(block.timestamp     >= distribution.claimDeadline,     Errors.STILL_CLAIMABLE);
            require(msg.sender          == distribution.payer,             Errors.NOT_ORIGINAL_PAYER);
            
            distribution.status = DistributionStatus.Reclaimed;
            distribution.token.safeTransfer(distribution.payer, distribution.amount);
            
            emit ReclaimedSenderDistribution(batchId, distributionId, distribution.payer, distribution.amount);
        }
        emit ReclaimedSenderDistributionsBatch(batchId, distributionIds, data);
    }

    /* -------------------------------------------------------------------------- */
    /*                              ONLY OWNER                                    */
    /* -------------------------------------------------------------------------- */
    function whitelistToken(address token) 
        external 
        onlyOwner 
    {
        require(whitelistedTokens.add(token), Errors.TOKEN_ALREADY_WHITELISTED);
        emit WhitelistedToken(token);
    }

    function setFeeOnFund(uint newFee) 
        external 
        onlyOwner 
    {
        require(newFee <= MAX_FEE, Errors.INVALID_FEE);
        uint oldFee = feeOnFund;
        feeOnFund = newFee;
        emit FeeOnFundSet(oldFee, newFee);
    }

    function setFeeOnClaim(uint newFee) 
        external 
        onlyOwner 
    {
        require(newFee <= MAX_FEE, Errors.INVALID_FEE);
        uint oldFee = feeOnClaim;
        feeOnClaim = newFee;
        emit FeeOnClaimSet(oldFee, newFee);
    }

    function setFeeRecipient(address newRec) 
        external 
        onlyOwner 
    {
        address oldRecipient = feeRecipient;
        feeRecipient = newRec;
        emit FeeRecipientSet(oldRecipient, newRec);
    }

    function setSigner(address newSigner) 
        external 
        onlyOwner 
    {
        address oldSigner = signer;
        signer = newSigner;
        emit SignerSet(oldSigner, newSigner);
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
    function addAdmins(uint repoId, uint instanceId, address[] calldata admins) 
        external 
        onlyRepoAdmin(repoId, instanceId) 
    {
        require(admins.length >  0,          Errors.INVALID_AMOUNT);
        require(admins.length <= batchLimit, Errors.BATCH_LIMIT_EXCEEDED);
        
        Account storage account = accounts[repoId][instanceId];
        for (uint i; i < admins.length; ++i) {
            address admin = admins[i];
            require(admin != address(0), Errors.INVALID_ADDRESS);
            if (account.admins.add(admin)) {
                emit AddedAdmin(repoId, instanceId, address(0), admin);
            }
        }
    }

    function removeAdmins(uint repoId, uint instanceId, address[] calldata admins) 
        external 
        onlyRepoAdmin(repoId, instanceId) 
    {
        require(admins.length >  0,          Errors.INVALID_AMOUNT);
        require(admins.length <= batchLimit, Errors.BATCH_LIMIT_EXCEEDED);
        
        Account storage account = accounts[repoId][instanceId];
        
        // Ensure we don't remove all admins
        require(account.admins.length() > admins.length, Errors.CANNOT_REMOVE_ALL_ADMINS);
        
        for (uint i; i < admins.length; ++i) {
            address admin = admins[i];
            if (account.admins.remove(admin)) {
                emit RemovedAdmin(repoId, instanceId, admin);
            }
        }
    }

    function addDistributors(uint repoId, uint instanceId, address[] calldata distributors) 
        external 
        onlyRepoAdmin(repoId, instanceId) 
    {
        require(distributors.length <= batchLimit, Errors.BATCH_LIMIT_EXCEEDED);
        
        Account storage account = accounts[repoId][instanceId];
        for (uint i; i < distributors.length; ++i) {
            address distributor = distributors[i];
            require(distributor != address(0), Errors.INVALID_ADDRESS);
            if (!account.distributors.contains(distributor)) {
                account.distributors.add(distributor);
                emit AddedDistributor(repoId, instanceId, distributor);
            }
        }
    }

    function removeDistributors(uint repoId, uint instanceId, address[] calldata distributors) 
        external 
        onlyRepoAdmin(repoId, instanceId) 
    {
        require(distributors.length <= batchLimit, Errors.BATCH_LIMIT_EXCEEDED);
        
        Account storage account = accounts[repoId][instanceId];
        for (uint i; i < distributors.length; ++i) {
            address distributor = distributors[i];
            if (account.distributors.remove(distributor)) {
                emit RemovedDistributor(repoId, instanceId, distributor);
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
    function getAllAdmins(uint repoId, uint instanceId) 
        external 
        view 
        returns (address[] memory admins) 
    {
        EnumerableSet.AddressSet storage adminSet = accounts[repoId][instanceId].admins;
        uint len = adminSet.length();
        admins = new address[](len);
        for (uint i; i < len; ++i) {
            admins[i] = adminSet.at(i);
        }
    }

    function getIsAuthorizedAdmin(uint repoId, uint instanceId, address admin) 
        external 
        view 
        returns (bool) 
    {
        return accounts[repoId][instanceId].admins.contains(admin);
    }

    function getIsAuthorizedDistributor(uint repoId, uint instanceId, address distributor) 
        external 
        view 
        returns (bool) 
    {
        return accounts[repoId][instanceId].distributors.contains(distributor);
    }

    function canDistribute(uint repoId, uint instanceId, address caller) 
        external 
        view 
        returns (bool) 
    {
        return accounts[repoId][instanceId].admins.contains(caller) || 
               accounts[repoId][instanceId].distributors.contains(caller);
    }

    function getAllDistributors(uint repoId, uint instanceId) 
        external 
        view 
        returns (address[] memory distributors) 
    {
        EnumerableSet.AddressSet storage distributorSet = accounts[repoId][instanceId].distributors;
        uint len = distributorSet.length();
        distributors = new address[](len);
        for (uint i; i < len; ++i) {
            distributors[i] = distributorSet.at(i);
        }
    }

    function getAccountBalance(uint repoId, uint instanceId, address token) 
        external 
        view 
        returns (uint) 
    {
        return accounts[repoId][instanceId].balance[token];
    }

    function getAccountHasDistributions(uint repoId, uint instanceId) 
        external 
        view 
        returns (bool) 
    {
        return accounts[repoId][instanceId].hasDistributions;
    }

    function getAccountExists(uint repoId, uint instanceId) 
        external 
        view 
        returns (bool) 
    {
        return accounts[repoId][instanceId].exists;
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
        uint len = whitelistedTokens.length();
        tokens   = new address[](len);
        for (uint i; i < len; ++i) tokens[i] = whitelistedTokens.at(i);
    }

    function isTokenWhitelisted(address token) 
        external 
        view 
        returns (bool) 
    {
        return whitelistedTokens.contains(token);
    }

    function getFunding(uint repoId, uint instanceId, address token, address funder) 
        external 
        view 
        returns (uint) 
    {
        return fundings[repoId][instanceId][token][funder];
    }
}
