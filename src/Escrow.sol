// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20}             from "solmate/tokens/ERC20.sol";
import {SafeTransferLib}   from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Owned}             from "solmate/auth/Owned.sol";
import {ECDSA}             from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EnumerableSet}     from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IEscrow, PaymentParams, Status} from "../interface/IEscrow.sol";
import {Errors}                         from "../libraries/Errors.sol";

contract Escrow is Owned, IEscrow {
    using SafeTransferLib   for ERC20;
    using EnumerableSet     for EnumerableSet.AddressSet;
    using FixedPointMathLib for uint256;

    uint    public constant MAX_FEE_BPS    = 1000; // 10%
    bytes32 public constant CLAIM_TYPEHASH = keccak256("Claim(address recipient,bool status,uint256 nonce,uint256 deadline)");

    uint256 internal immutable CLAIM_INITIAL_CHAIN_ID;
    bytes32 internal immutable CLAIM_INITIAL_DOMAIN_SEPARATOR;

    EnumerableSet.AddressSet private _whitelistedTokens;

    mapping(address => bool) public canClaim;
    mapping(address => uint) public recipientNonces;

    struct Payment {
        uint    amount;
        ERC20   token;
        address sender;
        address recipient;
        uint    claimDeadline;
        Status  status;
    }

    mapping(uint    => Payment) public payments;
    mapping(address => uint[])  public senderPayments;
    mapping(address => uint[])  public recipientPayments;

    uint    public paymentCount;
    uint    public batchCount;
    uint    public protocolFeeBps;
    address public feeRecipient;

    constructor(
        address          _owner,
        address[] memory _initialWhitelistedTokens,
        uint             _initialFeeBps
    ) Owned(_owner) {
        require(_initialFeeBps <= MAX_FEE_BPS, Errors.INVALID_FEE);
        feeRecipient                   = _owner;
        protocolFeeBps                 = _initialFeeBps;
        CLAIM_INITIAL_CHAIN_ID         = block.chainid;
        CLAIM_INITIAL_DOMAIN_SEPARATOR = _computeClaimDomainSeparator();

        for (uint256 i = 0; i < _initialWhitelistedTokens.length; i++) {
            _whitelistedTokens.add(_initialWhitelistedTokens[i]);
            emit TokenWhitelisted(_initialWhitelistedTokens[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                DEPOSIT
    //////////////////////////////////////////////////////////////*/
    /// @inheritdoc IEscrow
    function pay(PaymentParams calldata param)
        public
        returns (uint)
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
            feeAmount      = param.amount.mulDivUp(protocolFeeBps, 10_000);
            amountToEscrow = param.amount - feeAmount;
            require(amountToEscrow > 0, Errors.INVALID_AMOUNT_AFTER_FEE);
        }

        param.token.safeTransferFrom(msg.sender, address(this), param.amount);

        if (feeAmount > 0) {
            param.token.safeTransfer(feeRecipient, feeAmount);
        }

        payments[paymentCount] = Payment({
            amount:        amountToEscrow,
            token:         param.token,
            recipient:     param.recipient,
            sender:        param.sender,
            claimDeadline: block.timestamp + param.claimPeriod,
            status:        Status.Deposited
        });

        senderPayments   [param.sender]   .push(paymentCount);
        recipientPayments[param.recipient].push(paymentCount);

        emit Deposited(
            paymentCount,
            address(param.token),
            param.recipient,
            param.sender,
            amountToEscrow,
            block.timestamp + param.claimPeriod
        );

        return paymentCount++;
    }

    /// @inheritdoc IEscrow
    function batchPay(
        PaymentParams[] calldata params,
        uint repoId,
        uint timestamp
    ) 
        external 
        returns (uint[] memory paymentIds) 
    {
        paymentIds = new uint[](params.length);

        for (uint256 i = 0; i < params.length; i++) {
            paymentIds[i] = pay(params[i]);
        }

        emit BatchDeposited(batchCount++, repoId, timestamp, paymentIds);
    }

    /*//////////////////////////////////////////////////////////////
                                CLAIM
    //////////////////////////////////////////////////////////////*/
    /// @inheritdoc IEscrow
    function claim(
        uint    paymentId,
        address recipient,
        bool    status,
        uint256 deadline,
        uint8   v,
        bytes32 r,
        bytes32 s
    ) external {
        setCanClaim(recipient, status, deadline, v, r, s);
        require(canClaim[recipient], Errors.NO_PAYMENT_PERMISSION);
        _claim(paymentId, recipient);
    }

    /// @inheritdoc IEscrow
    function batchClaim(
        uint[] calldata paymentIds,
        address         recipient,
        bool            status,
        uint256         deadline,
        uint8           v,
        bytes32         r,
        bytes32         s
    ) external {
        setCanClaim(recipient, status, deadline, v, r, s);
        require(canClaim[recipient], Errors.NO_PAYMENT_PERMISSION);

        for (uint256 i = 0; i < paymentIds.length; i++) {
            _claim(paymentIds[i], recipient);
        }
    }

    function _claim(uint paymentId, address recipient) internal {
        require(paymentId < paymentCount, Errors.INVALID_PAYMENT_ID);
        Payment storage _payment = payments[paymentId];

        require(_payment.recipient == recipient,     Errors.INVALID_RECIPIENT);
        require(_payment.status == Status.Deposited, Errors.ALREADY_CLAIMED);
        
        _payment.status = Status.Claimed;
        _payment.token.safeTransfer(_payment.recipient, _payment.amount);

        emit Claimed(paymentId, _payment.recipient, _payment.amount);
    }

    /*//////////////////////////////////////////////////////////////
                                RECLAIM
    //////////////////////////////////////////////////////////////*/
    /// @inheritdoc IEscrow
    function reclaim(uint paymentId) external {
        _reclaim(paymentId);
    }

    /// @inheritdoc IEscrow
    function batchReclaim(uint[] calldata paymentIds) external {
        for (uint256 i = 0; i < paymentIds.length; i++) {
            _reclaim(paymentIds[i]);
        }
    }

    function _reclaim(uint paymentId) internal {
        require(paymentId < paymentCount, Errors.INVALID_PAYMENT_ID);
        Payment storage _payment = payments[paymentId];

        require(_payment.status == Status.Deposited,      Errors.ALREADY_CLAIMED);
        require(block.timestamp > _payment.claimDeadline, Errors.STILL_CLAIMABLE);
        
        _payment.status = Status.Reclaimed;
        _payment.token.safeTransfer(_payment.sender, _payment.amount);

        emit Reclaimed(paymentId, _payment.sender, _payment.amount);
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
    function getPaymentsBySender(address sender) external view returns (uint[] memory) {
        return senderPayments[sender];
    }

    function getPaymentsByRecipient(address recipient) external view returns (uint[] memory) {
        return recipientPayments[recipient];
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
