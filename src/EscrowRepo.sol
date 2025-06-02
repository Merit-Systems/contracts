// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Owned}           from "solmate/auth/Owned.sol";
import {ERC20}           from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {EnumerableSet}   from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ECDSA}           from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/*═══════════════════════════════════════════════════════════════════════*\
│                                 ERRORS                                 │
\*═══════════════════════════════════════════════════════════════════════*/
library Errors {
    string internal constant INVALID_ADDRESS          = "INVALID_ADDRESS";
    string internal constant INVALID_AMOUNT           = "INVALID_AMOUNT";
    string internal constant INVALID_TOKEN            = "INVALID_TOKEN";
    string internal constant INVALID_CLAIM_PERIOD     = "INVALID_CLAIM_PERIOD";
    string internal constant INVALID_DEPOSIT_ID       = "INVALID_DEPOSIT_ID";
    string internal constant ALREADY_CLAIMED          = "ALREADY_CLAIMED";
    string internal constant STILL_CLAIMABLE          = "STILL_CLAIMABLE";
    string internal constant SIGNATURE_EXPIRED        = "SIG_EXPIRED";
    string internal constant INVALID_SIGNATURE        = "BAD_SIG";
    string internal constant NO_CLAIM_PERMISSION      = "NO_CLAIM_PERMISSION";
    string internal constant TOKEN_ALREADY_WHITELISTED= "TOKEN_ALREADY_WL";
    string internal constant TOKEN_NOT_WHITELISTED    = "TOKEN_NOT_WL";
    string internal constant REPO_EXISTS              = "REPO_EXISTS";
    string internal constant REPO_UNKNOWN             = "REPO_UNKNOWN";
}

/*═══════════════════════════════════════════════════════════════════════*\
│                                CONTRACT                                │
\*═══════════════════════════════════════════════════════════════════════*/
contract RepoEscrow is Owned {
    using SafeTransferLib for ERC20;
    using EnumerableSet   for EnumerableSet.AddressSet;

    /* ------------------------------------------------------------------- */
    /*                             CONSTANTS                               */
    /* ------------------------------------------------------------------- */
    uint16  public constant MAX_FEE_BPS    = 1_000; // 10 %
    bytes32 public constant CLAIM_TYPEHASH =
        keccak256("Claim(uint256 repoId,address recipient,bool status,uint256 nonce,uint256 deadline)");

    /* ------------------------------------------------------------------- */
    /*                               TYPES                                 */
    /* ------------------------------------------------------------------- */
    enum Status { Deposited, Claimed, Reclaimed }

    struct Deposit {
        uint256 amount;
        ERC20   token;
        address sender;
        address recipient;
        uint32  claimDeadline;
        Status  status;
    }

    struct DepositParams {
        uint256 repoId;
        ERC20   token;
        address sender;
        address recipient;
        uint256 amount;
        uint32  claimPeriod; // seconds
    }

    /* ------------------------------------------------------------------- */
    /*                            REPO REGISTRY                            */
    /* ------------------------------------------------------------------- */
    struct RepoInfo {
        address admin;
        bool    exists;
    }
    mapping(uint256 => RepoInfo) public repoInfo; // repoId → info

    /* ------------------------------------------------------------------- */
    /*                           ESCROW STORAGE                            */
    /* ------------------------------------------------------------------- */
    mapping(uint256 => Deposit[]) private _repoDeposits;   // repoId → deposits[]
    mapping(address => bool)      public  canClaim;        // off-chain signer toggles this
    mapping(address => uint256)   public  recipientNonce;  // EIP-712 replay protection

    /* Whitelisting & fees */
    EnumerableSet.AddressSet private _whitelistedTokens;
    uint16  public protocolFeeBps;
    address public feeRecipient;

    /* Signature domain separator */
    uint256 internal immutable INITIAL_CHAIN_ID;
    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;

    address public signer; // trusted off-chain signer for `setCanClaim`

    /* ------------------------------------------------------------------- */
    /*                                EVENTS                               */
    /* ------------------------------------------------------------------- */
    event RepoAdded(uint256 indexed repoId, address indexed admin);
    event Deposited(
        uint256 indexed repoId,
        uint256 indexed depositId,
        address token,
        address indexed recipient,
        address sender,
        uint256 netAmount,
        uint256 feeAmount,
        uint32  claimDeadline
    );
    event Claimed(uint256 indexed repoId, uint256 indexed depositId, address recipient, uint256 amount);
    event Reclaimed(uint256 indexed repoId, uint256 indexed depositId, address sender,   uint256 amount);
    event CanClaimSet(address indexed recipient, bool status);
    event TokenWhitelisted(address token);
    event TokenRemovedFromWhitelist(address token);

    /* ------------------------------------------------------------------- */
    /*                             CONSTRUCTOR                             */
    /* ------------------------------------------------------------------- */
    constructor(
        address _owner,
        address _signer,
        address[] memory initialWhitelist,
        uint16  initialFeeBps
    ) Owned(_owner) {
        require(initialFeeBps <= MAX_FEE_BPS, "fee too high");
        signer            = _signer;
        feeRecipient      = _owner;
        protocolFeeBps    = initialFeeBps;
        INITIAL_CHAIN_ID  = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = _domainSeparator();

        for (uint256 i; i < initialWhitelist.length; ++i) {
            _whitelistedTokens.add(initialWhitelist[i]);
            emit TokenWhitelisted(initialWhitelist[i]);
        }
    }

    /* ------------------------------------------------------------------- */
    /*                           OWNER-ONLY OPS                            */
    /* ------------------------------------------------------------------- */
    function addRepo(uint256 repoId, address admin) external onlyOwner {
        require(!repoInfo[repoId].exists, Errors.REPO_EXISTS);
        require(admin != address(0),       Errors.INVALID_ADDRESS);
        repoInfo[repoId] = RepoInfo({admin: admin, exists: true});
        emit RepoAdded(repoId, admin);
    }

    function addWhitelistedToken(address token) external onlyOwner {
        require(_whitelistedTokens.add(token), Errors.TOKEN_ALREADY_WHITELISTED);
        emit TokenWhitelisted(token);
    }
    function removeWhitelistedToken(address token) external onlyOwner {
        require(_whitelistedTokens.remove(token), Errors.TOKEN_NOT_WHITELISTED);
        emit TokenRemovedFromWhitelist(token);
    }

    function setProtocolFee(uint16 newFeeBps) external onlyOwner {
        require(newFeeBps <= MAX_FEE_BPS, "fee too high");
        protocolFeeBps = newFeeBps;
    }
    function setFeeRecipient(address newRec) external onlyOwner {
        feeRecipient = newRec;
    }
    function setSigner(address newSigner) external onlyOwner {
        signer = newSigner;
    }

    /* ------------------------------------------------------------------- */
    /*                                DEPOSIT                              */
    /* ------------------------------------------------------------------- */
    function deposit(DepositParams calldata p) external returns (uint256 depositId) {
        require(repoInfo[p.repoId].exists,              Errors.REPO_UNKNOWN);
        require(p.token != ERC20(address(0)),           Errors.INVALID_TOKEN);
        require(_whitelistedTokens.contains(address(p.token)), Errors.INVALID_TOKEN);
        require(p.sender    != address(0) && p.recipient != address(0), Errors.INVALID_ADDRESS);
        require(p.amount    > 0,                        Errors.INVALID_AMOUNT);
        require(p.claimPeriod > 0 && p.claimPeriod < type(uint32).max, Errors.INVALID_CLAIM_PERIOD);

        /* ---- fee calc ---- */
        uint256 fee    = (protocolFeeBps == 0) ? 0 : (p.amount * protocolFeeBps + 9_999) / 10_000;
        uint256 netAmt = p.amount - fee;

        /* ---- pull tokens ---- */
        p.token.safeTransferFrom(msg.sender, address(this), p.amount);
        if (fee > 0) p.token.safeTransfer(feeRecipient, fee);

        /* ---- store deposit ---- */
        depositId = _repoDeposits[p.repoId].length;
        _repoDeposits[p.repoId].push(
            Deposit({
                amount:        netAmt,
                token:         p.token,
                sender:        p.sender,
                recipient:     p.recipient,
                claimDeadline: uint32(block.timestamp + p.claimPeriod),
                status:        Status.Deposited
            })
        );

        emit Deposited(
            p.repoId,
            depositId,
            address(p.token),
            p.recipient,
            p.sender,
            netAmt,
            fee,
            uint32(block.timestamp + p.claimPeriod)
        );
    }

    /* ------------------------------------------------------------------- */
    /*                                 CLAIM                               */
    /* ------------------------------------------------------------------- */
    function claim(
        uint256 repoId,
        uint256 depositId,
        bool    status,
        uint256 deadline,
        uint8   v,
        bytes32 r,
        bytes32 s
    ) external {
        /* Toggle canClaim via EIP-712 sig (same pattern as your Escrow).   */
        _setCanClaim(repoId, msg.sender, status, deadline, v, r, s);
        require(canClaim[msg.sender], Errors.NO_CLAIM_PERMISSION);

        Deposit storage d = _repoDeposits[repoId][depositId];
        require(d.status == Status.Deposited, Errors.ALREADY_CLAIMED);
        require(d.recipient == msg.sender,    Errors.INVALID_ADDRESS);

        d.status = Status.Claimed;
        d.token.safeTransfer(d.recipient, d.amount);
        emit Claimed(repoId, depositId, d.recipient, d.amount);
    }

    /* ------------------------------------------------------------------- */
    /*                                RECLAIM                              */
    /* ------------------------------------------------------------------- */
    function reclaim(uint256 repoId, uint256 depositId) external {
        Deposit storage d = _repoDeposits[repoId][depositId];
        require(d.status == Status.Deposited,      Errors.ALREADY_CLAIMED);
        require(block.timestamp > d.claimDeadline, Errors.STILL_CLAIMABLE);
        require(d.sender == msg.sender,            Errors.INVALID_ADDRESS);

        d.status = Status.Reclaimed;
        d.token.safeTransfer(d.sender, d.amount);
        emit Reclaimed(repoId, depositId, d.sender, d.amount);
    }

    /* ------------------------------------------------------------------- */
    /*                           INTERNAL: canClaim                        */
    /* ------------------------------------------------------------------- */
    function _setCanClaim(
        uint256 repoId,
        address recipient,
        bool    status,
        uint256 deadline,
        uint8   v,
        bytes32 r,
        bytes32 s
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
        address recovered = ECDSA.recover(digest, v, r, s);
        require(recovered == signer, Errors.INVALID_SIGNATURE);

        recipientNonce[recipient]++;
        canClaim[recipient] = status;
        emit CanClaimSet(recipient, status);
    }

    /* ------------------------------------------------------------------- */
    /*                         DOMAIN-SEPARATOR LOGIC                      */
    /* ------------------------------------------------------------------- */
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

    /* ------------------------------------------------------------------- */
    /*                               GETTERS                               */
    /* ------------------------------------------------------------------- */
    function depositsOf(uint256 repoId) external view returns (Deposit[] memory) {
        return _repoDeposits[repoId];
    }
    function whitelist() external view returns (address[] memory tokens) {
        uint256 len = _whitelistedTokens.length();
        tokens = new address[](len);
        for (uint256 i; i < len; ++i) tokens[i] = _whitelistedTokens.at(i);
    }
}
