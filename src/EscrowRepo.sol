// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Owned}           from "solmate/auth/Owned.sol";
import {ERC20}           from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {EnumerableSet}   from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ECDSA}           from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {IEscrowRepo}     from "../interface/IEscrowRepo.sol";
import {Errors}          from "../libraries/EscrowRepoErrors.sol";

contract EscrowRepo is Owned, IEscrowRepo {
    using SafeTransferLib for ERC20;
    using EnumerableSet   for EnumerableSet.AddressSet;

    /* -------------------------------------------------------------------------- */
    /*                                   CONSTANTS                                */
    /* -------------------------------------------------------------------------- */
    uint16 public constant MAX_FEE_BPS = 1_000; // 10 %

    bytes32 public constant ADD_REPO_TYPEHASH =
        keccak256("AddRepo(uint256 repoId,address admin,uint256 nonce,uint256 deadline)");
    bytes32 public constant ADD_ACCOUNT_TYPEHASH =
        keccak256("AddAccount(uint256 repoId,address admin,uint256 nonce,uint256 deadline)");
    bytes32 public constant CLAIM_TYPEHASH =
        keccak256("Claim(address recipient,bool status,uint256 nonce,uint256 deadline)");

    /* -------------------------------------------------------------------------- */
    /*                                     TYPES                                  */
    /* -------------------------------------------------------------------------- */
    struct Repo {
        bool                                            exists;
        uint256                                         accountCount;
        mapping(uint256 => mapping(address => uint256)) balance;              // accountId → token → balance
        mapping(uint256 => Deposit[])                   deposits;             // accountId → deposits
        mapping(uint256 => address)                     admin;                // accountId → admin
        mapping(uint256 => mapping(address => bool))    authorizedDepositors; // accountId → depositor → authorized
    }

    enum Status { Deposited, Claimed, Reclaimed }

    struct Deposit {
        uint256 amount;
        ERC20   token;
        address recipient;
        uint256 claimDeadline; // unix seconds
        Status  status;        // Deposited → Claimed / Reclaimed
    }

    struct DepositParams {
        uint256 amount;
        address recipient;
        uint32  claimPeriod; // seconds
        ERC20   token;
    }

    /* -------------------------------------------------------------------------- */
    /*                                STATE VARIABLES                             */
    /* -------------------------------------------------------------------------- */
    mapping(uint256 => Repo)     public repos;          // repoId → Repo

    mapping(address => bool)     public canClaim;       // recipient → canClaim
    mapping(address => uint256)  public recipientNonce; // recipient → nonce
    uint256                      public ownerNonce;    

    uint16  public protocolFeeBps;
    address public feeRecipient;

    EnumerableSet.AddressSet private _whitelistedTokens;

    address public signer;

    /* -------------------------------------------------------------------------- */
    /*                               EIP‑712 DOMAIN                               */
    /* -------------------------------------------------------------------------- */
    uint256 internal immutable INITIAL_CHAIN_ID;
    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;

    /* -------------------------------------------------------------------------- */
    /*                                 MODIFIERS                                  */
    /* -------------------------------------------------------------------------- */
    modifier accountExists(uint256 repoId, uint256 accountId) {
        require(repos[repoId].exists,                   Errors.REPO_UNKNOWN);
        require(accountId < repos[repoId].accountCount, Errors.ACCOUNT_UNKNOWN);
        _;
    }

    modifier isRepoAdmin(uint256 repoId, uint256 accountId) {
        require(msg.sender == repos[repoId].admin[accountId], Errors.NOT_REPO_ADMIN);
        _;
    }

    modifier isAuthorizedDepositor(uint256 repoId, uint256 accountId) {
        require(
            msg.sender == repos[repoId].admin[accountId] || 
            repos[repoId].authorizedDepositors[accountId][msg.sender], 
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
    /*                              ADMIN REGISTRY                                */
    /* -------------------------------------------------------------------------- */
    function addRepo(
        uint256 repoId,
        address admin,
        uint256 deadline,
        uint8   v,
        bytes32 r,
        bytes32 s
    ) 
      external 
      returns (uint256)
    {
        require(!repos[repoId].exists,       Errors.REPO_EXISTS);
        require(admin != address(0),         Errors.INVALID_ADDRESS);
        require(block.timestamp <= deadline, Errors.SIGNATURE_EXPIRED);

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    ADD_REPO_TYPEHASH,
                    repoId,
                    admin,
                    ownerNonce,
                    deadline
                ))
            )
        );
        require(ECDSA.recover(digest, v, r, s) == owner, Errors.INVALID_SIGNATURE);

        ownerNonce++;
        repos[repoId].exists = true;
        
        emit RepoAdded(repoId, admin);
        return _addAccount(repoId, admin); // Create the first account for this repo
    }

    function addAccount(
        uint256 repoId,
        address admin,
        uint256 deadline,
        uint8   v,
        bytes32 r,
        bytes32 s
    ) 
        external 
        returns (uint256) 
    {
        require(repos[repoId].exists,        Errors.REPO_UNKNOWN);
        require(admin != address(0),         Errors.INVALID_ADDRESS);
        require(block.timestamp <= deadline, Errors.SIGNATURE_EXPIRED);

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    ADD_ACCOUNT_TYPEHASH,
                    repoId,
                    admin,
                    ownerNonce,
                    deadline
                ))
            )
        );
        require(ECDSA.recover(digest, v, r, s) == owner, Errors.INVALID_SIGNATURE);

        ownerNonce++;
        
        return _addAccount(repoId, admin); 
    }

    function _addAccount(uint256 repoId, address admin) internal returns (uint256) {
        uint256 accountId = repos[repoId].accountCount;
        repos[repoId].admin[accountId] = admin;
        repos[repoId].accountCount++;
        emit AccountAdded(repoId, accountId, admin);
        return accountId;
    }

    /* -------------------------------------------------------------------------- */
    /*                                     FUND                                   */
    /* -------------------------------------------------------------------------- */
    function fund(
        uint256 repoId,
        uint256 accountId,
        ERC20   token,
        uint256 amount
    ) 
        external 
        accountExists(repoId, accountId)
    {
        require(_whitelistedTokens.contains(address(token)), Errors.INVALID_TOKEN);
        require(amount > 0,                                  Errors.INVALID_AMOUNT);

        uint256 fee    = (protocolFeeBps == 0) ? 0 : (amount * protocolFeeBps + 9_999) / 10_000;
        uint256 netAmt = amount - fee;

        token.safeTransferFrom(msg.sender, address(this), amount);
        if (fee > 0) token.safeTransfer(feeRecipient, fee);

        repos[repoId].balance[accountId][address(token)] += netAmt;

        emit Funded(repoId, address(token), msg.sender, netAmt, fee);
    }

    /* -------------------------------------------------------------------------- */
    /*                                  DEPOSIT                                   */
    /* -------------------------------------------------------------------------- */
    function deposit(
        uint256 repoId,
        uint256 accountId,
        DepositParams calldata d
    ) 
        external 
        accountExists        (repoId, accountId) 
        isAuthorizedDepositor(repoId, accountId) 
        returns (uint256)
    {
        return _deposit(repoId, accountId, d);
    }

    function batchDeposit(
        uint256 repoId,
        uint256 accountId,
        DepositParams[] calldata ds
    ) 
        external 
        accountExists        (repoId, accountId) 
        isAuthorizedDepositor(repoId, accountId) 
        returns (uint256[] memory depositIds)
    {
        depositIds = new uint256[](ds.length);
        for (uint256 i; i < ds.length; ++i) {
            depositIds[i] = _deposit(repoId, accountId, ds[i]);
        } 
    }

    function _deposit(
        uint256 repoId,
        uint256 accountId,
        DepositParams calldata d
    ) 
        internal 
        returns (uint256) 
    {
        require(d.recipient != address(0),                             Errors.INVALID_ADDRESS);
        require(_whitelistedTokens.contains(address(d.token)),         Errors.INVALID_TOKEN);
        require(d.amount > 0,                                          Errors.INVALID_AMOUNT);
        require(d.claimPeriod > 0 && d.claimPeriod < type(uint32).max, Errors.INVALID_CLAIM_PERIOD);

        uint256 balance = repos[repoId].balance[accountId][address(d.token)];
        require(balance >= d.amount, Errors.INSUFFICIENT_ACCOUNT_BALANCE);
        repos[repoId].balance[accountId][address(d.token)] = balance - d.amount;

        uint256 claimDeadline = block.timestamp + d.claimPeriod;

        uint256 depositId = repos[repoId].deposits[accountId].length;
        repos[repoId].deposits[accountId].push(
            Deposit({
                amount:        d.amount,
                token:         d.token,
                recipient:     d.recipient,
                claimDeadline: claimDeadline,
                status:        Status.Deposited
            })
        );

        emit Deposited(repoId, depositId, d.recipient, address(d.token), d.amount, claimDeadline);

        return depositId;
    }

    /* -------------------------------------------------------------------------- */
    /*                                   CLAIM                                    */
    /* -------------------------------------------------------------------------- */
    function claim(
        uint256 repoId,
        uint256 accountId,
        uint256 depositId,
        bool    status,
        uint256 deadline,
        uint8   v, bytes32 r, bytes32 s
    ) external accountExists(repoId, accountId) {
        _setCanClaim(msg.sender, status, deadline, v, r, s);
        require(canClaim[msg.sender], Errors.NO_CLAIM_PERMISSION);
        _claim(repoId, accountId, depositId, msg.sender);
    }

    function batchClaim(
        uint256 repoId,
        uint256 accountId,
        uint256[] calldata depositIds,
        bool    status,
        uint256 deadline,
        uint8   v, bytes32 r, bytes32 s
    ) external accountExists(repoId, accountId) {
        _setCanClaim(msg.sender, status, deadline, v, r, s);
        require(canClaim[msg.sender], Errors.NO_CLAIM_PERMISSION);
        for (uint256 i; i < depositIds.length; ++i) _claim(repoId, accountId, depositIds[i], msg.sender);
    }

    function _claim(uint256 repoId, uint256 accountId, uint256 depositId, address recipient) internal {
        require(depositId < repos[repoId].deposits[accountId].length, Errors.INVALID_CLAIM_ID);
        Deposit storage d = repos[repoId].deposits[accountId][depositId];

        require(d.status    == Status.Deposited, Errors.ALREADY_CLAIMED);
        require(d.recipient == recipient,        Errors.INVALID_ADDRESS);
        require(block.timestamp <= d.claimDeadline,   Errors.CLAIM_DEADLINE_PASSED);

        d.status = Status.Claimed;
        d.token.safeTransfer(recipient, d.amount);
        emit Claimed(repoId, depositId, recipient, d.amount);
    }

    /* -------------------------------------------------------------------------- */
    /*                                RECLAIM FUND                                */
    /* -------------------------------------------------------------------------- */
    function reclaimFund(uint256 repoId, uint256 accountId, address token, uint256 amount) 
        external 
        accountExists(repoId, accountId)
        isRepoAdmin(repoId, accountId) 
    {
        require(_whitelistedTokens.contains(token), Errors.INVALID_TOKEN);
        require(amount > 0, Errors.INVALID_AMOUNT);
        require(repos[repoId].deposits[accountId].length == 0, Errors.REPO_HAS_DEPOSITS);
        
        uint256 bal = repos[repoId].balance[accountId][token];
        require(bal >= amount, Errors.INSUFFICIENT_ACCOUNT_BALANCE);
        
        repos[repoId].balance[accountId][token] = bal - amount;
        ERC20(token).safeTransfer(msg.sender, amount);
        
        emit Reclaimed(repoId, type(uint256).max, msg.sender, amount);
    }

    /* -------------------------------------------------------------------------- */
    /*                                RECLAIM DEPOSIT                            */
    /* -------------------------------------------------------------------------- */
    function reclaimDeposit(uint256 repoId, uint256 accountId, uint256 depositId) 
        external 
        accountExists(repoId, accountId)
        isRepoAdmin(repoId, accountId) 
    {
        _reclaimDeposit(repoId, accountId, depositId);
    }

    function batchReclaimDeposit(uint256 repoId, uint256 accountId, uint256[] calldata depositIds) external isRepoAdmin(repoId, accountId) {
        for (uint256 i; i < depositIds.length; ++i) _reclaimDeposit(repoId, accountId, depositIds[i]);
    }

    function _reclaimDeposit(uint256 repoId, uint256 accountId, uint256 depositId) internal {
        require(depositId < repos[repoId].deposits[accountId].length, Errors.INVALID_CLAIM_ID);

        Deposit storage d = repos[repoId].deposits[accountId][depositId];
        require(d.status     == Status.Deposited, Errors.ALREADY_CLAIMED);
        require(block.timestamp > d.claimDeadline,     Errors.STILL_CLAIMABLE);

        d.status = Status.Reclaimed;
        repos[repoId].balance[accountId][address(d.token)] += d.amount;
        emit Reclaimed(repoId, depositId, msg.sender, d.amount);
    }

    /* -------------------------------------------------------------------------- */
    /*                              ONLY OWNER                                    */
    /* -------------------------------------------------------------------------- */
    function addWhitelistedToken(address token) external onlyOwner {
        require(_whitelistedTokens.add(token), Errors.TOKEN_ALREADY_WHITELISTED);
        emit TokenWhitelisted(token);
    }
    function removeWhitelistedToken(address token) external onlyOwner {
        require(_whitelistedTokens.remove(token), Errors.TOKEN_NOT_WHITELISTED);
        emit TokenRemovedFromWhitelist(token);
    }

    function setProtocolFee(uint16 newFeeBps) external onlyOwner {
        require(newFeeBps <= MAX_FEE_BPS, Errors.INVALID_FEE_BPS);
        protocolFeeBps = newFeeBps;
    }
    function setFeeRecipient(address newRec) external onlyOwner {
        feeRecipient = newRec;
    }
    function setSigner(address newSigner) external onlyOwner {
        signer = newSigner;
    }

    /* -------------------------------------------------------------------------- */
    /*                               SET REPO ADMIN                              */
    /* -------------------------------------------------------------------------- */
    function setRepoAdmin(uint256 repoId, uint256 accountId, address newAdmin) 
        external 
        accountExists(repoId, accountId)
        isRepoAdmin(repoId, accountId) 
    {
        require(newAdmin != address(0), Errors.INVALID_ADDRESS);

        address old = repos[repoId].admin[accountId];
        repos[repoId].admin[accountId] = newAdmin;
        emit RepoAdminChanged(repoId, old, newAdmin);
    }



    /* -------------------------------------------------------------------------- */
    /*                               AUTHORIZE DEPOSITOR                          */
    /* -------------------------------------------------------------------------- */
    function authorizeDepositor(uint256 repoId, uint256 accountId, address depositor) 
        external 
        accountExists(repoId, accountId)
        isRepoAdmin(repoId, accountId) 
    {
        _authorizeDepositor(repoId, accountId, depositor);
    }

    function batchAuthorizeDepositors(uint256 repoId, uint256 accountId, address[] calldata depositors) 
        external 
        accountExists(repoId, accountId)
        isRepoAdmin(repoId, accountId) 
    {
        for (uint256 i = 0; i < depositors.length; i++) {
            _authorizeDepositor(repoId, accountId, depositors[i]);
        }
    }

    function _authorizeDepositor(uint256 repoId, uint256 accountId, address depositor) internal {
        require(depositor != address(0), Errors.INVALID_ADDRESS);
        if (!repos[repoId].authorizedDepositors[accountId][depositor]) {
            repos[repoId].authorizedDepositors[accountId][depositor] = true;
            emit DepositorAuthorized(repoId, accountId, depositor);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                               DEAUTHORIZE DEPOSITOR                        */
    /* -------------------------------------------------------------------------- */
    function deauthorizeDepositor(uint256 repoId, uint256 accountId, address depositor) external isRepoAdmin(repoId, accountId) {
        _deauthorizeDepositor(repoId, accountId, depositor);
    }


    function batchDeauthorizeDepositors(uint256 repoId, uint256 accountId, address[] calldata depositors) external isRepoAdmin(repoId, accountId) {
        for (uint256 i = 0; i < depositors.length; i++) {
            _deauthorizeDepositor(repoId, accountId, depositors[i]);
        }
    }

    function _deauthorizeDepositor(uint256 repoId, uint256 accountId, address depositor) internal {
        if (repos[repoId].authorizedDepositors[accountId][depositor]) {
            repos[repoId].authorizedDepositors[accountId][depositor] = false;
            emit DepositorDeauthorized(repoId, accountId, depositor);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                         INTERNAL: canClaim EIP‑712                         */
    /* -------------------------------------------------------------------------- */
    function _setCanClaim(
        address recipient,
        bool    status,
        uint256 deadline,
        uint8   v, bytes32 r, bytes32 s
    ) internal {
        if (canClaim[recipient] == status) return;
        require(block.timestamp <= deadline, Errors.SIGNATURE_EXPIRED);

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    CLAIM_TYPEHASH,
                    recipient,
                    status,
                    recipientNonce[recipient],
                    deadline
                ))
            )
        );
        require(ECDSA.recover(digest, v, r, s) == signer, Errors.INVALID_SIGNATURE);

        recipientNonce[recipient]++;
        canClaim[recipient] = status;
        emit CanClaimSet(recipient, status);
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
    function repoExists(uint256 repoId) external view returns (bool) {
        return repos[repoId].exists;
    }

    function getRepoAccountCount(uint256 repoId) external view returns (uint256) {
        return repos[repoId].accountCount;
    }

    function getRepoLatestAccountId(uint256 repoId) external view returns (uint256) {
        require(repos[repoId].exists, Errors.REPO_UNKNOWN);
        require(repos[repoId].accountCount > 0, Errors.NO_ACCOUNTS_EXIST);
        return repos[repoId].accountCount - 1;
    }

    function getAccountAdmin(uint256 repoId, uint256 accountId) external view accountExists(repoId, accountId) returns (address) {
        return repos[repoId].admin[accountId];
    }

    function getAllAccountAdmins(uint256 repoId) external view returns (address[] memory) {
        uint256 count = repos[repoId].accountCount;
        address[] memory admins = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            admins[i] = repos[repoId].admin[i];
        }
        return admins;
    }

    function getIsAuthorizedDepositor(uint256 repoId, uint256 accountId, address depositor) external view accountExists(repoId, accountId) returns (bool) {
        return repos[repoId].authorizedDepositors[accountId][depositor];
    }

    function canDeposit(uint256 repoId, uint256 accountId, address caller) external view accountExists(repoId, accountId) returns (bool) {
        return caller == repos[repoId].admin[accountId] || repos[repoId].authorizedDepositors[accountId][caller];
    }

    function getAccountBalance(uint256 repoId, uint256 accountId, address token) external view accountExists(repoId, accountId) returns (uint256) {
        return repos[repoId].balance[accountId][token];
    }

    function getAccountDepositsCount(uint256 repoId, uint256 accountId) external view accountExists(repoId, accountId) returns (uint256) {
        return repos[repoId].deposits[accountId].length;
    }

    function getAccountDeposit(uint256 repoId, uint256 accountId, uint256 depositId) external view accountExists(repoId, accountId) returns (Deposit memory) {
        require(depositId < repos[repoId].deposits[accountId].length, Errors.INVALID_CLAIM_ID);
        return repos[repoId].deposits[accountId][depositId];
    }

    function getAllWhitelistedTokens() external view returns (address[] memory tokens) {
        uint256 len = _whitelistedTokens.length();
        tokens = new address[](len);
        for (uint256 i; i < len; ++i) tokens[i] = _whitelistedTokens.at(i);
    }

    function isTokenWhitelisted(address token) external view returns (bool) {
        return _whitelistedTokens.contains(token);
    }
}
