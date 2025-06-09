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
        keccak256("Claim(uint256 repoId,uint256 accountId,uint256[] distributionIds,address recipient,uint256 nonce,uint256 deadline)");

    /* -------------------------------------------------------------------------- */
    /*                                     TYPES                                  */
    /* -------------------------------------------------------------------------- */
    struct Account {
        mapping(address => uint256) balance;                 // token → balance
        Distribution[]              distributions;           // distributions
        address                     admin;                   // admin
        mapping(address => bool)    authorizedDistributors;  // distributor → authorized
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
        uint256 claimDeadline; // unix seconds
        Status  status;        // Distributed → Claimed / Reclaimed
    }

    struct DistributionParams {
        uint256 amount;
        address recipient;
        uint32  claimPeriod; // seconds
        ERC20   token;
    }

    /* -------------------------------------------------------------------------- */
    /*                                STATE VARIABLES                             */
    /* -------------------------------------------------------------------------- */
    mapping(uint256 => mapping(uint256 => Account)) public accounts;  // repoId → accountId → Account

    mapping(address => uint256)  public recipientNonce; // recipient → nonce
    uint256                      public ownerNonce;    

    uint16  public protocolFeeBps;
    address public feeRecipient;

    EnumerableSet.AddressSet private _whitelistedTokens;

    address public signer;

    uint256 public distributionBatchCount;

    /* -------------------------------------------------------------------------- */
    /*                               EIP‑712 DOMAIN                               */
    /* -------------------------------------------------------------------------- */
    uint256 internal immutable INITIAL_CHAIN_ID;
    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;

    /* -------------------------------------------------------------------------- */
    /*                                 MODIFIERS                                  */
    /* -------------------------------------------------------------------------- */
    modifier hasAdmin(uint256 repoId, uint256 accountId) {
        require(accounts[repoId][accountId].admin != address(0), Errors.NO_ADMIN_SET);
        _;
    }

    modifier isRepoAdmin(uint256 repoId, uint256 accountId) {
        require(msg.sender == accounts[repoId][accountId].admin, Errors.NOT_REPO_ADMIN);
        _;
    }

    modifier isAuthorizedDistributor(uint256 repoId, uint256 accountId) {
        require(
            msg.sender == accounts[repoId][accountId].admin || 
            accounts[repoId][accountId].authorizedDistributors[msg.sender], 
            Errors.NOT_REPO_ADMIN
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
    /*                                 SET ADMIN                                  */
    /* -------------------------------------------------------------------------- */
    function setAdmin(
        uint256 repoId,
        uint256 accountId,
        address admin,
        uint256 deadline,
        uint8   v,
        bytes32 r,
        bytes32 s
    ) external {
        require(admin != address(0), Errors.INVALID_ADDRESS);
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
    /*                                     FUND                                   */
    /* -------------------------------------------------------------------------- */
    function fund(
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
    /*                                DISTRIBUTE                                  */
    /* -------------------------------------------------------------------------- */
    function distribute(
        uint256                       repoId,
        uint256                       accountId,
        DistributionParams[] calldata params,
        bytes                memory   data
    ) 
        external 
        isAuthorizedDistributor(repoId, accountId) 
        returns (uint256[] memory distributionIds)
    {
        uint256 distributionBatchId = distributionBatchCount++;
        distributionIds = new uint256[](params.length);
        for (uint256 i; i < params.length; ++i) {
            DistributionParams calldata param = params[i];
            
            require(param.recipient  != address(0),                    Errors.INVALID_ADDRESS);
            require(param.amount      > 0,                             Errors.INVALID_AMOUNT);
            require(param.claimPeriod > 0,                             Errors.INVALID_CLAIM_PERIOD);
            require(_whitelistedTokens.contains(address(param.token)), Errors.INVALID_TOKEN);

            uint256 balance = accounts[repoId][accountId].balance[address(param.token)];
            require(balance >= param.amount, Errors.INSUFFICIENT_BALANCE);
            accounts[repoId][accountId].balance[address(param.token)] = balance - param.amount;

            uint256 claimDeadline = block.timestamp + param.claimPeriod;

            uint256 distributionId = accounts[repoId][accountId].distributions.length;
            accounts[repoId][accountId].distributions.push(
                Distribution({
                    amount:        param.amount,
                    token:         param.token,
                    recipient:     param.recipient,
                    claimDeadline: claimDeadline,
                    status:        Status.Distributed
                })
            );

            distributionIds[i] = distributionId;
            emit Distributed(distributionBatchId, distributionId, param.recipient, address(param.token), param.amount, claimDeadline);
        } 
        emit DistributedBatch(distributionBatchId, repoId, accountId, distributionIds, data);
    }

    /* -------------------------------------------------------------------------- */
    /*                                   CLAIM                                    */
    /* -------------------------------------------------------------------------- */
    function claim(
        uint256          repoId,
        uint256          accountId,
        uint256[] memory distributionIds,
        uint256          deadline,
        uint8            v,
        bytes32          r,
        bytes32          s
    ) external hasAdmin(repoId, accountId) {
        require(block.timestamp <= deadline, Errors.SIGNATURE_EXPIRED);
        require(distributionIds.length > 0,  Errors.INVALID_AMOUNT);

        require(ECDSA.recover(
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(
                        CLAIM_TYPEHASH,
                        repoId,
                        accountId,
                        keccak256(abi.encodePacked(distributionIds)),
                        msg.sender,
                        recipientNonce[msg.sender],
                        deadline
                    ))
                )
            ), v, r, s) == signer, Errors.INVALID_SIGNATURE);

        recipientNonce[msg.sender]++;

        Account storage account = accounts[repoId][accountId];

        for (uint256 i; i < distributionIds.length; ++i) {
            uint256 distributionId = distributionIds[i];
            Distribution storage distribution = account.distributions[distributionId];

            require(distribution.status    == Status.Distributed,         Errors.ALREADY_CLAIMED);
            require(distribution.recipient == msg.sender,                 Errors.INVALID_RECIPIENT);
            require(block.timestamp        <= distribution.claimDeadline, Errors.CLAIM_DEADLINE_PASSED);

            distribution.status = Status.Claimed;
             
            uint256 fee       = distribution.amount.mulDivUp(protocolFeeBps, 10_000);
            uint256 netAmount = distribution.amount - fee;
            require(netAmount > 0, Errors.INVALID_AMOUNT);
            
            if (fee > 0) distribution.token.safeTransfer(feeRecipient, fee);
            distribution.token.safeTransfer(msg.sender, netAmount);
            emit Claimed(repoId, distributionId, msg.sender, netAmount, fee);
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
        require(_whitelistedTokens.contains(token), Errors.INVALID_TOKEN);
        require(amount > 0, Errors.INVALID_AMOUNT);
        require(accounts[repoId][accountId].distributions.length == 0, Errors.REPO_HAS_DISTRIBUTIONS);
        
        uint256 balance = accounts[repoId][accountId].balance[token];
        require(balance >= amount, Errors.INSUFFICIENT_BALANCE);
        
        accounts[repoId][accountId].balance[token] = balance - amount;
        ERC20(token).safeTransfer(msg.sender, amount);
        
        emit Reclaimed(repoId, type(uint256).max, msg.sender, amount);
    }

    /* -------------------------------------------------------------------------- */
    /*                            RECLAIM DISTRIBUTION                            */
    /* -------------------------------------------------------------------------- */
    function reclaimDistribution(
        uint256 repoId,
        uint256 accountId,
        uint256 distributionId
    ) 
        external 
    {
        _reclaimDistribution(repoId, accountId, distributionId);
    }

    function batchReclaimDistribution(
        uint256            repoId,
        uint256            accountId,
        uint256[] calldata distributionIds
    ) 
        external 
    {
        for (uint256 i; i < distributionIds.length; ++i) _reclaimDistribution(repoId, accountId, distributionIds[i]);
    }

    function _reclaimDistribution(
        uint256 repoId,
        uint256 accountId,
        uint256 distributionId
    ) 
        internal 
    {
        Distribution storage d = accounts[repoId][accountId].distributions[distributionId];

        require(distributionId < accounts[repoId][accountId].distributions.length, Errors.INVALID_DISTRIBUTION_ID);
        require(d.status == Status.Distributed,                                  Errors.ALREADY_CLAIMED);
        require(block.timestamp > d.claimDeadline,                               Errors.STILL_CLAIMABLE);

        d.status = Status.Reclaimed;
        accounts[repoId][accountId].balance[address(d.token)] += d.amount;
        emit Reclaimed(repoId, distributionId, msg.sender, d.amount);
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

        address old = accounts[repoId][accountId].admin;
        accounts[repoId][accountId].admin = newAdmin;
        emit RepoAdminChanged(repoId, old, newAdmin);
    }

    /* -------------------------------------------------------------------------- */
    /*                            AUTHORIZE DISTRIBUTOR                           */
    /* -------------------------------------------------------------------------- */
    function authorizeDistributor(uint256 repoId, uint256 accountId, address distributor) 
        external 
        isRepoAdmin(repoId, accountId) 
    {
        _authorizeDistributor(repoId, accountId, distributor);
    }

    function batchAuthorizeDistributors(uint256 repoId, uint256 accountId, address[] calldata distributors) 
        external 
        isRepoAdmin(repoId, accountId) 
    {
        for (uint256 i = 0; i < distributors.length; i++) {
            _authorizeDistributor(repoId, accountId, distributors[i]);
        }
    }

    function _authorizeDistributor(uint256 repoId, uint256 accountId, address distributor) internal {
        require(distributor != address(0), Errors.INVALID_ADDRESS);
        if (!accounts[repoId][accountId].authorizedDistributors[distributor]) {
            accounts[repoId][accountId].authorizedDistributors[distributor] = true;
            emit DistributorAuthorized(repoId, accountId, distributor);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                           DEAUTHORIZE DISTRIBUTOR                          */
    /* -------------------------------------------------------------------------- */
    function deauthorizeDistributor(uint256 repoId, uint256 accountId, address distributor) external isRepoAdmin(repoId, accountId) {
        _deauthorizeDistributor(repoId, accountId, distributor);
    }


    function batchDeauthorizeDistributors(uint256 repoId, uint256 accountId, address[] calldata distributors) external isRepoAdmin(repoId, accountId) {
        for (uint256 i = 0; i < distributors.length; i++) {
            _deauthorizeDistributor(repoId, accountId, distributors[i]);
        }
    }

    function _deauthorizeDistributor(uint256 repoId, uint256 accountId, address distributor) internal {
        if (accounts[repoId][accountId].authorizedDistributors[distributor]) {
            accounts[repoId][accountId].authorizedDistributors[distributor] = false;
            emit DistributorDeauthorized(repoId, accountId, distributor);
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

    function getAccountDistributionsCount(uint256 repoId, uint256 accountId) 
        external 
        view 
        returns (uint256) 
    {
        return accounts[repoId][accountId].distributions.length;
    }

    function getAccountDistribution(uint256 repoId, uint256 accountId, uint256 distributionId) 
        external 
        view 
        returns (Distribution memory) 
    {
        require(distributionId < accounts[repoId][accountId].distributions.length, Errors.INVALID_CLAIM_ID);
        return accounts[repoId][accountId].distributions[distributionId];
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
