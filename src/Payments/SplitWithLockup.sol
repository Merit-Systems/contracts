// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ECDSA}            from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ERC20}            from "solmate/tokens/ERC20.sol";
import {SafeTransferLib}  from "solmate/utils/SafeTransferLib.sol";
import {Owned}            from "solmate/auth/Owned.sol";
import {ISplitWithLockup} from "../../interface/ISplitWithLockup.sol";
import {Errors}           from "../../libraries/Errors.sol";

struct DepositParams {
    ERC20   token;
    address sender;
    address recipient;
    uint    amount;
    uint    claimPeriod;
}

contract SplitWithLockup is Owned, ISplitWithLockup {
    using SafeTransferLib for ERC20;

    mapping(address => bool) public canClaim;
    mapping(address => uint) public recipientNonces;

    struct Deposit {
        uint    amount;
        ERC20   token;
        address recipient;
        address sender;
        uint    claimDeadline;
        bool    claimed;
    }

    uint public depositCount;

    mapping(uint    => Deposit) public deposits;
    mapping(address => uint[])  public senderDeposits;
    mapping(address => uint[])  public recipientDeposits;

    bytes32 public constant CLAIM_TYPEHASH = keccak256("Claim(address recipient,bool status,uint256 nonce)");

    uint256 internal immutable CLAIM_INITIAL_CHAIN_ID;
    bytes32 internal immutable CLAIM_INITIAL_DOMAIN_SEPARATOR;

    constructor(address _owner) Owned(_owner) { 
        CLAIM_INITIAL_CHAIN_ID         = block.chainid;
        CLAIM_INITIAL_DOMAIN_SEPARATOR = _computeClaimDomainSeparator();
    }

    function deposit(DepositParams calldata param)
        public 
        returns (uint depositId) 
    {
        require(param.token      != ERC20(address(0)), Errors.INVALID_ADDRESS);
        require(param.sender     != address(0),        Errors.INVALID_ADDRESS);
        require(param.recipient  != address(0),        Errors.INVALID_ADDRESS);
        require(param.amount      > 0,                 Errors.INVALID_AMOUNT);
        require(param.claimPeriod > 0,                 Errors.INVALID_CLAIM_PERIOD);

        param.token.safeTransferFrom(msg.sender, address(this), param.amount);

        deposits[depositCount] = Deposit({
            amount:        param.amount,
            token:         param.token,
            recipient:     param.recipient,
            sender:        param.sender,
            claimDeadline: block.timestamp + param.claimPeriod,
            claimed:       false
        });

        senderDeposits   [param.sender]   .push(depositCount);
        recipientDeposits[param.recipient].push(depositCount);

        emit DepositCreated(
            depositCount,
            address(param.token),
            param.recipient,
            param.sender,
            param.amount,
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

    function claim(
        uint    depositId,
        address recipient,
        bool    status,
        uint8   v,
        bytes32 r,
        bytes32 s
    ) external {
        setCanClaim(recipient, status, v, r, s);
        require(canClaim[recipient], Errors.NO_PAYMENT_PERMISSION);
        _claim(depositId, recipient);
    }

    function batchClaim(
        uint[] calldata depositIds,
        address         recipient,
        bool            status,
        uint8           v,
        bytes32         r,
        bytes32         s
    ) external {
        setCanClaim(recipient, status, v, r, s);
        require(canClaim[recipient], Errors.NO_PAYMENT_PERMISSION);

        for (uint256 i = 0; i < depositIds.length; i++) {
            _claim(depositIds[i], recipient);
        }
    }

    function _claim(uint depositId, address recipient) internal {
        Deposit storage _deposit = deposits[depositId];

        require(_deposit.recipient == recipient,           Errors.INVALID_RECIPIENT);
        require(!_deposit.claimed,                         Errors.ALREADY_CLAIMED);
        require(block.timestamp <= _deposit.claimDeadline, Errors.CLAIM_EXPIRED);
        
        _deposit.claimed = true;
        _deposit.token.safeTransfer(_deposit.recipient, _deposit.amount);

        emit Claimed(depositId, _deposit.recipient, _deposit.amount);
    }

    function reclaim(uint depositId) external {
        _reclaim(depositId);
    }

    function batchReclaim(uint[] calldata depositIds) external {
        for (uint256 i = 0; i < depositIds.length; i++) {
            _reclaim(depositIds[i]);
        }
    }

    function _reclaim(uint depositId) internal {
        Deposit storage _deposit = deposits[depositId];

        require(!_deposit.claimed,                        Errors.ALREADY_CLAIMED);
        require(block.timestamp > _deposit.claimDeadline, Errors.STILL_CLAIMABLE);
        
        _deposit.claimed = true;
        _deposit.token.safeTransfer(_deposit.sender, _deposit.amount);

        emit Reclaimed(depositId, _deposit.sender, _deposit.amount);
    }

    function setCanClaim(
        address recipient,
        bool    status,
        uint8   v,
        bytes32 r,
        bytes32 s
    ) public {
        if (canClaim[recipient] == status) return;

        bytes32 structHash = keccak256(
            abi.encode(
                CLAIM_TYPEHASH,
                recipient,
                status,
                recipientNonces[recipient]
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
                keccak256(bytes("SplitWithLockup")), 
                keccak256("1"),
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

    function getDepositsBySender(address sender) external view returns (uint[] memory) {
        return senderDeposits[sender];
    }

    function getDepositsByRecipient(address recipient) external view returns (uint[] memory) {
        return recipientDeposits[recipient];
    }
}
