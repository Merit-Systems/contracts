// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Owned} from "solmate/auth/Owned.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

contract SplitWithLockup is Owned(msg.sender) {
    using SafeTransferLib for ERC20;

    mapping(address => bool) public canClaim;

    function setCanClaim(address recipient, bool allowed) external onlyOwner {
        canClaim[recipient] = allowed;
    }

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

    struct SplitParams {
        address recipient;
        uint    value;
        bool    canTransferNow;
        uint    claimPeriod;
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
                    amount: params[i].value,
                    token: token,
                    recipient: params[i].recipient,
                    sender: msg.sender,
                    claimDeadline: block.timestamp + params[i].claimPeriod,
                    claimed: false
                });

                depositCount++;
            }
        }
    }

    function claim(uint depositId) external {
        Deposit storage deposit = deposits[depositId];

        require(!deposit.claimed);
        require(deposit.amount > 0);
        require(msg.sender == deposit.recipient);
        require(block.timestamp <= deposit.claimDeadline);
        require(canClaim[msg.sender]);

        deposit.claimed = true;
        deposit.token.safeTransfer(msg.sender, deposit.amount);
    }

    function reclaim(uint depositId) external {
        Deposit storage deposit = deposits[depositId];

        require(!deposit.claimed);
        require(deposit.amount > 0);
        require(msg.sender == deposit.sender);
        require(block.timestamp > deposit.claimDeadline);

        deposit.claimed = true;
        deposit.token.safeTransfer(msg.sender, deposit.amount);
    }
}
