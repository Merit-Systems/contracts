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
    uint16  public constant MAX_FEE_BPS  = 1_000; // 10 %

    bytes32 public constant CLAIM_TYPEHASH     =
        keccak256("Claim(uint256 repoId,address recipient,bool status,uint256 nonce,uint256 deadline)");
    bytes32 public constant ADD_REPO_TYPEHASH  =
        keccak256("AddRepo(uint256 repoId,address admin,uint256 nonce,uint256 deadline)");

    /* -------------------------------------------------------------------------- */
    /*                                     TYPES                                  */
    /* -------------------------------------------------------------------------- */
    enum Status { Deposited, Claimed, Reclaimed }

    struct Deposit {
        uint256 amount;
        ERC20   token;
        address sender;          // who sent the funds
        address recipient;       // chosen later by repo-admin
        uint32  claimDeadline;   // unix-seconds
        Status  status;
    }

    struct DepositParams {
        uint256 repoId;
        ERC20   token;
        uint256 amount;
        uint32  claimPeriod;     // seconds
    }

    /* -------------------------------------------------------------------------- */
    /*                                STATE  — REGISTRY                           */
    /* -------------------------------------------------------------------------- */
    mapping(uint256 => address) public repoAdmin;      // repoId → admin address

    /* -------------------------------------------------------------------------- */
    /*                                STATE — ESCROW                              */
    /* -------------------------------------------------------------------------- */
    mapping(uint256 => Deposit[]) private _repoDeposits;   // repoId → deposits[]
    mapping(address => bool)      public  canClaim;        // off-chain signer toggles this
    mapping(address => uint256)   public  recipientNonce;  // EIP-712 replay protection
    uint256 public ownerNonce;                             // for addRepo sigs

    /* -------------------------------------------------------------------------- */
    /*                             FEES & WHITELIST                               */
    /* -------------------------------------------------------------------------- */
    EnumerableSet.AddressSet private _whitelistedTokens;
    uint16  public protocolFeeBps;
    address public feeRecipient;

    /* -------------------------------------------------------------------------- */
    /*                               EIP-712 DOMAIN                               */
    /* -------------------------------------------------------------------------- */
    uint256 internal immutable INITIAL_CHAIN_ID;
    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;

    /* -------------------------------------------------------------------------- */
    /*                                OFF-CHAIN SIGS                              */
    /* -------------------------------------------------------------------------- */
    address public signer; // trusted backend that signs {repoId,recipient,status}

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
    /*                               REPO-ADMIN OPs                              */
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
    /*                                   DEPOSIT                                  */
    /* -------------------------------------------------------------------------- */

    function deposit(DepositParams calldata p) external returns (uint256 depositId) {
        require(repoAdmin[p.repoId] != address(0),              Errors.REPO_UNKNOWN);
        require(p.token != ERC20(address(0)),                   Errors.INVALID_TOKEN);
        require(_whitelistedTokens.contains(address(p.token)),  Errors.INVALID_TOKEN);
        require(p.amount > 0,                                   Errors.INVALID_AMOUNT);
        require(p.claimPeriod > 0 && p.claimPeriod < type(uint32).max, Errors.INVALID_CLAIM_PERIOD);

        /* fee */
        uint256 fee    = (protocolFeeBps == 0) ? 0 : (p.amount * protocolFeeBps + 9_999) / 10_000;
        uint256 netAmt = p.amount - fee;

        /* transfer funds */
        p.token.safeTransferFrom(msg.sender, address(this), p.amount);
        if (fee > 0) p.token.safeTransfer(feeRecipient, fee);

        /* store escrow record */
        depositId = _repoDeposits[p.repoId].length;
        _repoDeposits[p.repoId].push(
            Deposit({
                amount:        netAmt,
                token:         p.token,
                sender:        msg.sender,
                recipient:     address(0), // chosen later
                claimDeadline: uint32(block.timestamp + p.claimPeriod),
                status:        Status.Deposited
            })
        );

        emit Deposited(
            p.repoId,
            depositId,
            address(p.token),
            address(0),
            msg.sender,
            netAmt,
            fee,
            uint32(block.timestamp + p.claimPeriod)
        );
    }

    /* -------------------------------------------------------------------------- */
    /*                           DISTRIBUTE                                       */
    /* -------------------------------------------------------------------------- */

    /// @notice Assign a recipient to one deposit
    function distribute(
        uint256 repoId,
        uint256 depositId,
        address recipient
    ) external {
        _distribute(repoId, depositId, recipient);
    }

    /// @notice Batch-assign recipients (aka "distribute")
    function batchDistribute(
        uint256 repoId,
        uint256[] calldata depositIds,
        address[] calldata recipients
    ) external {
        require(depositIds.length == recipients.length, Errors.ARRAY_LENGTH_MISMATCH);
        for (uint256 i; i < depositIds.length; ++i) {
            _distribute(repoId, depositIds[i], recipients[i]);
        }
    }

    function _distribute(uint256 repoId, uint256 depositId, address recipient) internal {
        require(msg.sender == repoAdmin[repoId],             Errors.NOT_REPO_ADMIN);
        require(recipient != address(0),                     Errors.INVALID_ADDRESS);
        require(depositId < _repoDeposits[repoId].length,    Errors.INVALID_DEPOSIT_ID);

        Deposit storage d = _repoDeposits[repoId][depositId];
        require(d.status   == Status.Deposited,              Errors.ALREADY_CLAIMED);
        require(d.recipient == address(0),                   Errors.RECIPIENT_ALREADY_SET);

        d.recipient = recipient;
        emit Distribute(repoId, depositId, recipient);
    }

    /* -------------------------------------------------------------------------- */
    /*                                   CLAIM                                    */
    /* -------------------------------------------------------------------------- */
    function claim(
        uint256 repoId,
        uint256 depositId,
        bool    status,
        uint256 deadline,
        uint8   v, bytes32 r, bytes32 s
    ) external {
        _setCanClaim(repoId, msg.sender, status, deadline, v, r, s);
        require(canClaim[msg.sender], Errors.NO_CLAIM_PERMISSION);
        _claim(repoId, depositId, msg.sender);
    }

    function batchClaim(
        uint256 repoId,
        uint256[] calldata depositIds,
        bool    status,
        uint256 deadline,
        uint8   v, bytes32 r, bytes32 s
    ) external {
        _setCanClaim(repoId, msg.sender, status, deadline, v, r, s);
        require(canClaim[msg.sender], Errors.NO_CLAIM_PERMISSION);

        for (uint256 i; i < depositIds.length; ++i) {
            _claim(repoId, depositIds[i], msg.sender);
        }
    }

    function _claim(uint256 repoId, uint256 depositId, address recipient) internal {
        require(depositId < _repoDeposits[repoId].length, Errors.INVALID_DEPOSIT_ID);
        Deposit storage d = _repoDeposits[repoId][depositId];

        require(d.status    == Status.Deposited, Errors.ALREADY_CLAIMED);
        require(d.recipient != address(0),       Errors.RECIPIENT_NOT_SET);
        require(d.recipient == recipient,        Errors.INVALID_ADDRESS);

        d.status = Status.Claimed;
        d.token.safeTransfer(recipient, d.amount);
        emit Claimed(repoId, depositId, recipient, d.amount);
    }

    /* -------------------------------------------------------------------------- */
    /*                                   RECLAIM                                  */
    /* -------------------------------------------------------------------------- */
    function reclaimDistribute(uint256 repoId, uint256 depositId) external {
        _reclaimDistribute(repoId, depositId);
    }

    function batchReclaimDistribute(uint256 repoId, uint256[] calldata depositIds) external {
        for (uint256 i; i < depositIds.length; ++i) {
            _reclaimDistribute(repoId, depositIds[i]);
        }
    }

    function _reclaimDistribute(uint256 repoId, uint256 depositId) internal {
        require(msg.sender == repoAdmin[repoId],            Errors.NOT_REPO_ADMIN);
        require(depositId < _repoDeposits[repoId].length,   Errors.INVALID_DEPOSIT_ID);

        Deposit storage d = _repoDeposits[repoId][depositId];
        require(d.status       == Status.Deposited,     Errors.ALREADY_CLAIMED);
        require(block.timestamp > d.claimDeadline,      Errors.STILL_CLAIMABLE);

        d.status = Status.Reclaimed;
        d.token.safeTransfer(msg.sender, d.amount);
        emit Reclaimed(repoId, depositId, msg.sender, d.amount);
    }

    /* -------------------------------------------------------------------------- */
    /*                         INTERNAL: canClaim EIP-712                         */
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
    /*                           DOMAIN-SEPARATOR LOGIC                           */
    /* -------------------------------------------------------------------------- */
    function _domainSeparator() private view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("RepoEscrow")),
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
    /*                                    GETTERS                                 */
    /* -------------------------------------------------------------------------- */
    function depositsOf(uint256 repoId) external view returns (Deposit[] memory) {
        return _repoDeposits[repoId];
    }
    function whitelist() external view returns (address[] memory tokens) {
        uint256 len = _whitelistedTokens.length();
        tokens = new address[](len);
        for (uint256 i; i < len; ++i) {
            tokens[i] = _whitelistedTokens.at(i);
        }
    }
}