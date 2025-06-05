// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/*
 * EscrowRepo v2 — funding pool ➜ claimable lots
 * ----------------------------------------------------
 * 1. fund()       — Anyone can fund a repo (tokens flow ➜ contract pool).
 * 2. deposit()    — Repo admin slices pool into claimable lots for recipients.
 * 3. claim()      — Recipients (if canClaim=true) pull their lots.
 * 4. reclaim()    — Admin recovers expired lots.
 *
 * Design notes
 * -------------
 * • Pooled balances per repo/token kept in `_pooled`.
 * • Provenance of funding tracked via `Funding[]`.
 * • Actual payable obligations live in `Claim[]`.
 * • Protocol fee is charged up‑front on fund().
 */

import {Owned}           from "solmate/auth/Owned.sol";
import {ERC20}           from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {EnumerableSet}   from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ECDSA}           from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {IEscrowRepo}     from "../interface/IEscrowRepo.sol";
import {Errors}          from "../libraries/EscrowRepoErrors.sol";

contract EscrowRepo is Owned {
    using SafeTransferLib for ERC20;
    using EnumerableSet   for EnumerableSet.AddressSet;

    /* -------------------------------------------------------------------------- */
    /*                                   CONSTANTS                                */
    /* -------------------------------------------------------------------------- */
    uint16  public constant MAX_FEE_BPS  = 1_000; // 10 %

    /*
     * Claim(authorise) & AddRepo EIP‑712 type hashes
     * NOTE: claimId is NOT part of the signed data. Only (repo,recipient,status)
     *       This lets backend toggle claim‑ability once per repo per user.
     */
    bytes32 public constant CLAIM_TYPEHASH     =
        keccak256("Claim(uint256 repoId,address recipient,bool status,uint256 nonce,uint256 deadline)");
    bytes32 public constant ADD_REPO_TYPEHASH  =
        keccak256("AddRepo(uint256 repoId,address admin,uint256 nonce,uint256 deadline)");

    /* -------------------------------------------------------------------------- */
    /*                                     TYPES                                  */
    /* -------------------------------------------------------------------------- */
    enum Status { Deposited, Claimed, Reclaimed }

    struct Funding {
        uint256 amount;
        ERC20   token;
        address sender;      // originator of funds
    }

    struct Claim {
        uint256 amount;
        ERC20   token;
        address recipient;
        uint32  deadline;    // unix seconds
        Status  status;      // Deposited → Claimed / Reclaimed
    }

    struct FundParams {
        uint256 repoId;
        ERC20   token;
        uint256 amount;
    }

    struct DepositParams {
        uint256 repoId;
        uint256 amount;
        address recipient;
        uint32  claimPeriod; // seconds
        ERC20   token;
    }

    /* -------------------------------------------------------------------------- */
    /*                                STATE  — REGISTRY                           */
    /* -------------------------------------------------------------------------- */
    mapping(uint256 => address) public repoAdmin;      // repoId → admin

    /* -------------------------------------------------------------------------- */
    /*                                STATE — POOL & CLAIMS                       */
    /* -------------------------------------------------------------------------- */
    mapping(uint256 => Funding[])  private _fundings;    // repoId → inbound deposits
    mapping(uint256 => Claim[])    private _claims;      // repoId → claimable lots
    mapping(uint256 => mapping(address => uint256)) private _pooled; // repoId → token → balance

    mapping(address => bool)      public  canClaim;        // off‑chain signer toggles this
    mapping(address => uint256)   public  recipientNonce;  // EIP‑712 replay protection
    uint256 public ownerNonce;                             // for addRepo sigs

    /* -------------------------------------------------------------------------- */
    /*                             FEES & WHITELIST                               */
    /* -------------------------------------------------------------------------- */
    EnumerableSet.AddressSet private _whitelistedTokens;
    uint16  public protocolFeeBps;
    address public feeRecipient;

    /* -------------------------------------------------------------------------- */
    /*                               EIP‑712 DOMAIN                               */
    /* -------------------------------------------------------------------------- */
    uint256 internal immutable INITIAL_CHAIN_ID;
    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;

    /* -------------------------------------------------------------------------- */
    /*                                OFF‑CHAIN SIGS                              */
    /* -------------------------------------------------------------------------- */
    address public signer; // trusted backend that signs {repoId,recipient,status}

    /* -------------------------------------------------------------------------- */
    /*                                 EVENTS                                     */
    /* -------------------------------------------------------------------------- */
    event Funded(
        uint256 indexed repoId,
        uint256 indexed fundingId,
        address indexed token,
        address sender,
        uint256 amount,
        uint256 fee
    );

    event Deposited(
        uint256 indexed repoId,
        uint256 indexed claimId,
        address indexed recipient,
        address token,
        uint256 amount,
        uint32  deadline
    );

    event Claimed(
        uint256 indexed repoId,
        uint256 indexed claimId,
        address indexed recipient,
        uint256 amount
    );

    event Reclaimed(
        uint256 indexed repoId,
        uint256 indexed claimId,
        address indexed admin,
        uint256 amount
    );

    event CanClaimSet(address indexed recipient, bool status);
    event RepoAdded(uint256 indexed repoId, address indexed admin);
    event RepoAdminChanged(uint256 indexed repoId, address indexed oldAdmin, address indexed newAdmin);
    event TokenWhitelisted(address indexed token);
    event TokenRemovedFromWhitelist(address indexed token);

    /* -------------------------------------------------------------------------- */
    /*                                 CONSTRUCTOR                                */
    /* -------------------------------------------------------------------------- */
    constructor(
        address _owner,
        address _signer,
        address[] memory initialWhitelist,
        uint16  initialFeeBps
    ) Owned(_owner) {
        require(initialFeeBps <= MAX_FEE_BPS, Errors.INVALID_FEE_BPS);

        signer                   = _signer;
        feeRecipient             = _owner;
        protocolFeeBps           = initialFeeBps;
        INITIAL_CHAIN_ID         = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = _domainSeparator();

        for (uint256 i; i < initialWhitelist.length; ++i) {
            _whitelistedTokens.add(initialWhitelist[i]);
            emit TokenWhitelisted(initialWhitelist[i]);
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
    ) external {
        require(repoAdmin[repoId] == address(0), Errors.REPO_EXISTS);
        require(admin != address(0),             Errors.INVALID_ADDRESS);
        require(block.timestamp <= deadline,     Errors.SIGNATURE_EXPIRED);

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
        repoAdmin[repoId] = admin;
        emit RepoAdded(repoId, admin);
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
    /*                               REPO‑ADMIN OPs                              */
    /* -------------------------------------------------------------------------- */

    function setRepoAdmin(uint256 repoId, address newAdmin) external {
        require(repoAdmin[repoId] != address(0), Errors.REPO_UNKNOWN);
        require(msg.sender == repoAdmin[repoId], Errors.NOT_REPO_ADMIN);
        require(newAdmin != address(0),          Errors.INVALID_ADDRESS);

        address old = repoAdmin[repoId];
        repoAdmin[repoId] = newAdmin;
        emit RepoAdminChanged(repoId, old, newAdmin);
    }

    /* -------------------------------------------------------------------------- */
    /*                                     FUND                                   */
    /* -------------------------------------------------------------------------- */

    function fund(FundParams calldata p) external returns (uint256 fundingId) {
        require(repoAdmin[p.repoId] != address(0),              Errors.REPO_UNKNOWN);
        require(_whitelistedTokens.contains(address(p.token)),  Errors.INVALID_TOKEN);
        require(p.amount > 0,                                   Errors.INVALID_AMOUNT);

        /* fee */
        uint256 fee    = (protocolFeeBps == 0) ? 0 : (p.amount * protocolFeeBps + 9_999) / 10_000;
        uint256 netAmt = p.amount - fee;

        /* transfer funds */
        p.token.safeTransferFrom(msg.sender, address(this), p.amount);
        if (fee > 0) p.token.safeTransfer(feeRecipient, fee);

        /* pool balance */
        _pooled[p.repoId][address(p.token)] += netAmt;

        /* store funding record */
        fundingId = _fundings[p.repoId].length;
        _fundings[p.repoId].push(Funding({amount: netAmt, token: p.token, sender: msg.sender}));

        emit Funded(p.repoId, fundingId, address(p.token), msg.sender, netAmt, fee);
    }

    /* -------------------------------------------------------------------------- */
    /*                                  DEPOSIT                                   */
    /* -------------------------------------------------------------------------- */

    function deposit(DepositParams calldata d) external returns (uint256 claimId) {
        _deposit(d);
        claimId = _claims[d.repoId].length - 1;
    }

    function batchDeposit(DepositParams[] calldata ds) external {
        for (uint256 i; i < ds.length; ++i) _deposit(ds[i]);
    }

    function _deposit(DepositParams calldata d) internal {
        require(msg.sender == repoAdmin[d.repoId],            Errors.NOT_REPO_ADMIN);
        require(d.recipient != address(0),                    Errors.INVALID_ADDRESS);
        require(_whitelistedTokens.contains(address(d.token)),Errors.INVALID_TOKEN);
        require(d.amount > 0,                                 Errors.INVALID_AMOUNT);
        require(d.claimPeriod > 0 && d.claimPeriod < type(uint32).max, Errors.INVALID_CLAIM_PERIOD);

        uint256 bal = _pooled[d.repoId][address(d.token)];
        require(bal >= d.amount, Errors.INSUFFICIENT_POOL_BALANCE);
        _pooled[d.repoId][address(d.token)] = bal - d.amount;

        uint32 deadline = uint32(block.timestamp + d.claimPeriod);

        uint256 claimId = _claims[d.repoId].length;
        _claims[d.repoId].push(
            Claim({
                amount:     d.amount,
                token:      d.token,
                recipient:  d.recipient,
                deadline:   deadline,
                status:     Status.Deposited
            })
        );

        emit Deposited(d.repoId, claimId, d.recipient, address(d.token), d.amount, deadline);
    }

    /* -------------------------------------------------------------------------- */
    /*                                   CLAIM                                    */
    /* -------------------------------------------------------------------------- */
    function claim(
        uint256 repoId,
        uint256 claimId,
        bool    status,
        uint256 deadline,
        uint8   v, bytes32 r, bytes32 s
    ) external {
        _setCanClaim(repoId, msg.sender, status, deadline, v, r, s);
        require(canClaim[msg.sender], Errors.NO_CLAIM_PERMISSION);
        _claim(repoId, claimId, msg.sender);
    }

    function batchClaim(
        uint256 repoId,
        uint256[] calldata claimIds,
        bool    status,
        uint256 deadline,
        uint8   v, bytes32 r, bytes32 s
    ) external {
        _setCanClaim(repoId, msg.sender, status, deadline, v, r, s);
        require(canClaim[msg.sender], Errors.NO_CLAIM_PERMISSION);
        for (uint256 i; i < claimIds.length; ++i) _claim(repoId, claimIds[i], msg.sender);
    }

    function _claim(uint256 repoId, uint256 claimId, address recipient) internal {
        require(claimId < _claims[repoId].length, Errors.INVALID_CLAIM_ID);
        Claim storage c = _claims[repoId][claimId];

        require(c.status    == Status.Deposited, Errors.ALREADY_CLAIMED);
        require(c.recipient == recipient,        Errors.INVALID_ADDRESS);
        require(block.timestamp <= c.deadline,   Errors.CLAIM_DEADLINE_PASSED);

        c.status = Status.Claimed;
        c.token.safeTransfer(recipient, c.amount);
        emit Claimed(repoId, claimId, recipient, c.amount);
    }

    /* -------------------------------------------------------------------------- */
    /*                                   RECLAIM                                  */
    /* -------------------------------------------------------------------------- */
    function reclaim(uint256 repoId, uint256 claimId) external {
        _reclaim(repoId, claimId);
    }

    function batchReclaim(uint256 repoId, uint256[] calldata claimIds) external {
        for (uint256 i; i < claimIds.length; ++i) _reclaim(repoId, claimIds[i]);
    }

    function _reclaim(uint256 repoId, uint256 claimId) internal {
        require(msg.sender == repoAdmin[repoId],            Errors.NOT_REPO_ADMIN);
        require(claimId < _claims[repoId].length,           Errors.INVALID_CLAIM_ID);

        Claim storage c = _claims[repoId][claimId];
        require(c.status     == Status.Deposited, Errors.ALREADY_CLAIMED);
        require(block.timestamp > c.deadline,     Errors.STILL_CLAIMABLE);

        c.status = Status.Reclaimed;
        _pooled[repoId][address(c.token)] += c.amount;
        emit Reclaimed(repoId, claimId, msg.sender, c.amount);
    }

    /* -------------------------------------------------------------------------- */
    /*                                RECLAIM FUND                                */
    /* -------------------------------------------------------------------------- */
    function reclaimFund(uint256 repoId, address token, uint256 amount) external {
        require(msg.sender == repoAdmin[repoId], Errors.NOT_REPO_ADMIN);
        require(_whitelistedTokens.contains(token), Errors.INVALID_TOKEN);
        require(amount > 0, Errors.INVALID_AMOUNT);
        require(_claims[repoId].length == 0, Errors.REPO_HAS_DEPOSITS);
        
        uint256 bal = _pooled[repoId][token];
        require(bal >= amount, Errors.INSUFFICIENT_POOL_BALANCE);
        
        _pooled[repoId][token] = bal - amount;
        ERC20(token).safeTransfer(msg.sender, amount);
        
        emit Reclaimed(repoId, type(uint256).max, msg.sender, amount);
    }

    /* -------------------------------------------------------------------------- */
    /*                         INTERNAL: canClaim EIP‑712                         */
    /* -------------------------------------------------------------------------- */
    function _setCanClaim(
        uint256 repoId,
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
                    repoId,
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
                keccak256(bytes("RepoEscrow")),
                keccak256(bytes("2")), // version 2
                block.chainid,
                address(this)
            )
        );
    }
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return block.chainid == INITIAL_CHAIN_ID ? INITIAL_DOMAIN_SEPARATOR : _domainSeparator();
    }

    /* -------------------------------------------------------------------------- */
    /*                                    GETTERS                                 */
    /* -------------------------------------------------------------------------- */

    function fundingsOf(uint256 repoId) external view returns (Funding[] memory) {
        return _fundings[repoId];
    }

    function claimsOf(uint256 repoId) external view returns (Claim[] memory) {
        return _claims[repoId];
    }

    function poolBalance(uint256 repoId, address token) external view returns (uint256) {
        return _pooled[repoId][token];
    }

    function whitelist() external view returns (address[] memory tokens) {
        uint256 len = _whitelistedTokens.length();
        tokens = new address[](len);
        for (uint256 i; i < len; ++i) tokens[i] = _whitelistedTokens.at(i);
    }
}
