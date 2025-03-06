// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20}           from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {Owned}           from "solmate/auth/Owned.sol";

contract SplitWithLockup is Owned {
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
    mapping(uint => Deposit) public deposits;

    mapping(address => uint[]) public senderDeposits;
    mapping(address => uint[]) public recipientDeposits;

    struct SplitParams {
        address recipient;
        uint    value;
        bool    canTransferNow;
        uint    claimPeriod;
        address sender;
    }
    bytes32 public constant CLAIM_TYPEHASH = keccak256("Claim(address recipient,bool status,uint256 nonce)");

    uint256 internal immutable CLAIM_INITIAL_CHAIN_ID;
    bytes32 internal immutable CLAIM_INITIAL_DOMAIN_SEPARATOR;

    constructor() Owned(msg.sender) { 
        CLAIM_INITIAL_CHAIN_ID         = block.chainid;
        CLAIM_INITIAL_DOMAIN_SEPARATOR = _computeClaimDomainSeparator();
    }

    function split(
        ERC20 token,
        SplitParams[] calldata params
    ) external {
        for (uint256 i = 0; i < params.length; i++) {
            if (params[i].canTransferNow) {
                token.safeTransferFrom(msg.sender, params[i].recipient, params[i].value);
            } else {
                token.safeTransferFrom(msg.sender, address(this), params[i].value);

                deposits[depositCount] = Deposit({
                    amount:        params[i].value,
                    token:         token,
                    recipient:     params[i].recipient,
                    sender:        params[i].sender,
                    claimDeadline: block.timestamp + params[i].claimPeriod,
                    claimed:       false
                });

                senderDeposits[params[i].sender].push(depositCount);
                recipientDeposits[params[i].recipient].push(depositCount);

                depositCount++;
            }
        }
    }

    function claim(uint depositId) external {
        Deposit storage deposit = deposits[depositId];

        require(!deposit.claimed);
        require(block.timestamp <= deposit.claimDeadline);

        deposit.claimed = true;
        deposit.token.safeTransfer(deposit.recipient, deposit.amount);
    }

    function batchClaim(uint[] calldata depositIds) external {
        for (uint256 i = 0; i < depositIds.length; i++) {
            Deposit storage deposit = deposits[depositIds[i]];

            require(!deposit.claimed);
            require(block.timestamp <= deposit.claimDeadline);

            deposit.claimed = true;
            deposit.token.safeTransfer(deposit.recipient, deposit.amount);
        }
    }

    function claimWithSignature(uint depositId, address recipient, bool status, uint8 v, bytes32 r, bytes32 s) external {
        setCanClaim(recipient, status, v, r, s);
        require(canClaim[recipient]);

        Deposit storage deposit = deposits[depositId];

        require(!deposit.claimed);
        require(block.timestamp <= deposit.claimDeadline);

        deposit.claimed = true;
        deposit.token.safeTransfer(deposit.recipient, deposit.amount);
    }

    function batchClaimWithSignature(
        uint[] calldata depositIds,
        address recipient,
        bool status,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        setCanClaim(recipient, status, v, r, s);
        require(canClaim[recipient]);
        
        for (uint256 i = 0; i < depositIds.length; i++) {
            Deposit storage deposit = deposits[depositIds[i]];

            require(!deposit.claimed);
            require(block.timestamp <= deposit.claimDeadline);

            deposit.claimed = true;
            deposit.token.safeTransfer(deposit.recipient, deposit.amount);
        }
    }

    function reclaim(uint depositId) external {
        Deposit storage deposit = deposits[depositId];

        require(!deposit.claimed);
        require(block.timestamp > deposit.claimDeadline);

        deposit.claimed = true;
        deposit.token.safeTransfer(deposit.sender, deposit.amount);
    }


    function setCanClaim(
        address recipient,
        bool status,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
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

        address signer = ecrecover(digest, v, r, s);
        require(signer == owner, "Invalid signature");

        recipientNonces[recipient]++;

        canClaim[recipient] = status;
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
