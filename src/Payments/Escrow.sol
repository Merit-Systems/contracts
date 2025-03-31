// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ECDSA}           from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ERC20}           from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Owned}           from "solmate/auth/Owned.sol";
import {IEscrow}         from "../../interface/IEscrow.sol";
import {Errors}          from "../../libraries/Errors.sol";
import {EnumerableSet}   from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

enum Status {
    Deposited,
    Claimed,
    Reclaimed
}

struct DepositParams {
    ERC20   token;
    address sender;
    address recipient;
    uint    amount;
    uint    claimPeriod;
}

contract Escrow is Owned, IEscrow {
    using SafeTransferLib for ERC20;
    using EnumerableSet   for EnumerableSet.AddressSet;
    using FixedPointMathLib for uint256;

    mapping(address => bool) public canClaim;
    mapping(address => uint) public recipientNonces;

    struct Deposit {
        uint    amount;
        ERC20   token;
        address sender;
        address recipient;
        uint    claimDeadline;
        Status  state;
    }

    uint public depositCount;

    mapping(uint    => Deposit) public deposits;
    mapping(address => uint[])  public senderDeposits;
    mapping(address => uint[])  public recipientDeposits;

    bytes32 public constant CLAIM_TYPEHASH = keccak256("Claim(address recipient,bool status,uint256 nonce,uint256 deadline)");

    uint256 internal immutable CLAIM_INITIAL_CHAIN_ID;
    bytes32 internal immutable CLAIM_INITIAL_DOMAIN_SEPARATOR;

    EnumerableSet.AddressSet private _whitelistedTokens;

    uint    public protocolFeeBps;
    address public feeRecipient;
    uint    public constant MAX_FEE_BPS = 1000;

    event ProtocolFeeSet(uint newFeeBps);
    event FeeRecipientSet(address newFeeRecipient);

    constructor(address _owner, address[] memory initialWhitelistedTokens, uint initialFeeBps) Owned(_owner) {
        require(initialFeeBps <= MAX_FEE_BPS, Errors.INVALID_FEE);
        CLAIM_INITIAL_CHAIN_ID         = block.chainid;
        CLAIM_INITIAL_DOMAIN_SEPARATOR = _computeClaimDomainSeparator();
        feeRecipient = _owner;
        protocolFeeBps = initialFeeBps;

        for (uint256 i = 0; i < initialWhitelistedTokens.length; i++) {
            _whitelistedTokens.add(initialWhitelistedTokens[i]);
            emit TokenWhitelisted(initialWhitelistedTokens[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                DEPOSIT
    //////////////////////////////////////////////////////////////*/
    function deposit(DepositParams calldata param)
        public
        returns (uint depositId)
    {
        require(param.token      != ERC20(address(0)),             Errors.INVALID_ADDRESS);
        require(param.sender     != address(0),                    Errors.INVALID_ADDRESS);
        require(param.recipient  != address(0),                    Errors.INVALID_ADDRESS);
        require(param.amount      > 0,                             Errors.INVALID_AMOUNT);
        require(param.claimPeriod > 0,                             Errors.INVALID_CLAIM_PERIOD);
        require(_whitelistedTokens.contains(address(param.token)), Errors.INVALID_TOKEN);

        uint feeAmount;
        uint amountToEscrow = param.amount;
        if (protocolFeeBps > 0) {
            feeAmount = param.amount.mulDivDown(protocolFeeBps, 10_000);
            amountToEscrow = param.amount - feeAmount;
            require(amountToEscrow > 0, Errors.INVALID_AMOUNT_AFTER_FEE);
        }

        param.token.safeTransferFrom(msg.sender, address(this), param.amount);

        if (feeAmount > 0) {
            param.token.safeTransfer(feeRecipient, feeAmount);
        }

        deposits[depositCount] = Deposit({
            amount:        amountToEscrow,
            token:         param.token,
            recipient:     param.recipient,
            sender:        param.sender,
            claimDeadline: block.timestamp + param.claimPeriod,
            state:         Status.Deposited
        });

        senderDeposits   [param.sender]   .push(depositCount);
        recipientDeposits[param.recipient].push(depositCount);

        emit DepositCreated(
            depositCount,
            address(param.token),
            param.recipient,
            param.sender,
            amountToEscrow,
            block.timestamp + param.claimPeriod
        );

        return depositCount++;
    }

    function batchDeposit(
        DepositParams[] calldata params
    ) 
        external 
        returns (uint[] memory depositIds) 
    {
        depositIds = new uint[](params.length);

        for (uint256 i = 0; i < params.length; i++) {
            depositIds[i] = deposit(params[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                CLAIM
    //////////////////////////////////////////////////////////////*/
    function claim(
        uint    depositId,
        address recipient,
        bool    status,
        uint256 deadline,
        uint8   v,
        bytes32 r,
        bytes32 s
    ) external {
        setCanClaim(recipient, status, deadline, v, r, s);
        require(canClaim[recipient], Errors.NO_PAYMENT_PERMISSION);
        _claim(depositId, recipient);
    }

    function batchClaim(
        uint[] calldata depositIds,
        address         recipient,
        bool            status,
        uint256         deadline,
        uint8           v,
        bytes32         r,
        bytes32         s
    ) external {
        setCanClaim(recipient, status, deadline, v, r, s);
        require(canClaim[recipient], Errors.NO_PAYMENT_PERMISSION);

        for (uint256 i = 0; i < depositIds.length; i++) {
            _claim(depositIds[i], recipient);
        }
    }

    function _claim(uint depositId, address recipient) internal {
        require(depositId < depositCount, Errors.INVALID_DEPOSIT_ID);
        Deposit storage _deposit = deposits[depositId];

        require(_deposit.recipient == recipient,    Errors.INVALID_RECIPIENT);
        require(_deposit.state == Status.Deposited, Errors.ALREADY_CLAIMED);
        
        _deposit.state = Status.Claimed;
        _deposit.token.safeTransfer(_deposit.recipient, _deposit.amount);

        emit Claimed(depositId, _deposit.recipient, _deposit.amount);
    }

    /*//////////////////////////////////////////////////////////////
                                RECLAIM
    //////////////////////////////////////////////////////////////*/
    function reclaim(uint depositId) external {
        _reclaim(depositId);
    }

    function batchReclaim(uint[] calldata depositIds) external {
        for (uint256 i = 0; i < depositIds.length; i++) {
            _reclaim(depositIds[i]);
        }
    }

    function _reclaim(uint depositId) internal {
        require(depositId < depositCount, Errors.INVALID_DEPOSIT_ID);
        Deposit storage _deposit = deposits[depositId];

        require(_deposit.state == Status.Deposited,       Errors.ALREADY_CLAIMED);
        require(block.timestamp > _deposit.claimDeadline, Errors.STILL_CLAIMABLE);
        
        _deposit.state = Status.Reclaimed;
        _deposit.token.safeTransfer(_deposit.sender, _deposit.amount);

        emit Reclaimed(depositId, _deposit.sender, _deposit.amount);
    }

    /*//////////////////////////////////////////////////////////////
                               SIGNATURE
    //////////////////////////////////////////////////////////////*/
    function setCanClaim(
        address recipient,
        bool    status,
        uint256 deadline,
        uint8   v,
        bytes32 r,
        bytes32 s
    ) public {
        if (canClaim[recipient] == status) return;
        
        require(block.timestamp <= deadline, Errors.SIGNATURE_EXPIRED);

        bytes32 structHash = keccak256(
            abi.encode(
                CLAIM_TYPEHASH,
                recipient,
                status,
                recipientNonces[recipient],
                deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", CLAIM_DOMAIN_SEPARATOR(), structHash)
        );

        address signer = ECDSA.recover(digest, v, r, s);
        require(signer == owner, Errors.INVALID_SIGNATURE);

        recipientNonces[recipient]++;

        canClaim[recipient] = status;

        emit CanClaimSet(recipient, status);
    }

    function _computeClaimDomainSeparator() internal view returns (bytes32) {
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

    function CLAIM_DOMAIN_SEPARATOR() public view returns (bytes32) {
        if (block.chainid == CLAIM_INITIAL_CHAIN_ID) {
            return CLAIM_INITIAL_DOMAIN_SEPARATOR;
        }
        return _computeClaimDomainSeparator();
    }

    /*//////////////////////////////////////////////////////////////
                               WHITELIST
    //////////////////////////////////////////////////////////////*/
    function addWhitelistedToken(address token) external onlyOwner {
        require(token != address(0), Errors.INVALID_ADDRESS);
        require(_whitelistedTokens.add(token), Errors.TOKEN_ALREADY_WHITELISTED);
        emit TokenWhitelisted(token);
    }

    function removeWhitelistedToken(address token) external onlyOwner {
        require(_whitelistedTokens.remove(token), Errors.TOKEN_NOT_WHITELISTED);
        emit TokenRemovedFromWhitelist(token);
    }

    function isTokenWhitelisted(address token) public view returns (bool) {
        return _whitelistedTokens.contains(token);
    }

    function getWhitelistedTokens() external view returns (address[] memory) {
        uint256 length = _whitelistedTokens.length();
        address[] memory tokens = new address[](length);
        
        for (uint256 i = 0; i < length; i++) {
            tokens[i] = _whitelistedTokens.at(i);
        }
        
        return tokens;
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/
    function getDepositsBySender(address sender) external view returns (uint[] memory) {
        return senderDeposits[sender];
    }

    function getDepositsByRecipient(address recipient) external view returns (uint[] memory) {
        return recipientDeposits[recipient];
    }

    /*//////////////////////////////////////////////////////////////
                                FEE MANAGEMENT (Owner Only)
    //////////////////////////////////////////////////////////////*/

    function setProtocolFeeBps(uint _newFeeBps) external onlyOwner {
        require(_newFeeBps <= MAX_FEE_BPS, Errors.INVALID_FEE);
        protocolFeeBps = _newFeeBps;
        emit ProtocolFeeSet(_newFeeBps);
    }

    function setFeeRecipient(address _newFeeRecipient) external onlyOwner {
        require(_newFeeRecipient != address(0), Errors.INVALID_ADDRESS);
        feeRecipient = _newFeeRecipient;
        emit FeeRecipientSet(_newFeeRecipient);
    }

}
