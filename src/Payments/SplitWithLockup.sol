// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20}           from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

contract SplitWithLockup {
    using SafeTransferLib for ERC20;

    address public immutable owner;

    mapping(address => bool) public canClaim;

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

    constructor() { owner = msg.sender; }

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

        // require(!deposit.claimed);
        // require(block.timestamp <= deposit.claimDeadline);
        require(deposit.recipient == msg.sender);
        require(canClaim[msg.sender]);

        deposit.claimed = true;
        deposit.token.safeTransfer(deposit.recipient, deposit.amount);
    }

    function reclaim(uint depositId) external {
        Deposit storage deposit = deposits[depositId];

        require(!deposit.claimed);
        require(block.timestamp > deposit.claimDeadline);
        // require(deposit.sender == msg.sender);

        deposit.claimed = true;
        deposit.token.safeTransfer(deposit.sender, deposit.amount);
    }

    function setCanClaim(
        address recipient,
        bool status,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        bytes32 messageHash = keccak256(
            abi.encodePacked("setCanClaim", address(this), recipient, status)
        );

        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );

        address signer = ecrecover(ethSignedMessageHash, v, r, s);
        require(signer == owner, "Invalid signature: Not the owner");

        canClaim[recipient] = status;
    }

    function getDepositsBySender(address sender) external view returns (uint[] memory) {
        return senderDeposits[sender];
    }

    function getDepositsByRecipient(address recipient) external view returns (uint[] memory) {
        return recipientDeposits[recipient];
    }
}
