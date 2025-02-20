// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Owned} from "solmate/auth/Owned.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

contract SplitWithLockup is Owned(msg.sender) {
    mapping(address => bool) public canClaim;

    function setCanClaim(address recipient, bool allowed) external onlyOwner {
        canClaim[recipient] = allowed;
    }

    struct Deposit {
        uint256 amount;
        ERC20   token;
        address recipient;
        address sender;
        uint256 claimDeadline;
        bool    claimed;
    }

    uint256 public depositCount;
    mapping(uint256 => Deposit) public deposits;

    function split(
        ERC20 token,
        address[] calldata recipients,
        uint256[] calldata values,
        bool[]    calldata canTransferNow,
        uint256[] calldata claimPeriods
    ) external {
        require(
            recipients.length == values.length && 
            recipients.length == canTransferNow.length &&
            recipients.length == claimPeriods.length
        );

        for (uint256 i = 0; i < recipients.length; i++) {
            if (canTransferNow[i]) {
                require(token.transferFrom(msg.sender, recipients[i], values[i]));
            } else {
                require(token.transferFrom(msg.sender, address(this), values[i]));

                deposits[depositCount] = Deposit({
                    amount: values[i],
                    token: token,
                    recipient: recipients[i],
                    sender: msg.sender,
                    claimDeadline: block.timestamp + claimPeriods[i],
                    claimed: false
                });

                depositCount++;
            }
        }
    }

    function claim(uint256 depositId) external {
        Deposit storage deposit = deposits[depositId];

        require(!deposit.claimed);
        require(deposit.amount > 0);
        require(msg.sender == deposit.recipient);
        require(block.timestamp <= deposit.claimDeadline);
        require(canClaim[msg.sender]);

        deposit.claimed = true;
        require(deposit.token.transfer(msg.sender, deposit.amount));
    }

    function reclaim(uint256 depositId) external {
        Deposit storage deposit = deposits[depositId];

        require(!deposit.claimed);
        require(deposit.amount > 0);
        require(msg.sender == deposit.sender);
        require(block.timestamp > deposit.claimDeadline);

        deposit.claimed = true;
        require(deposit.token.transfer(msg.sender, deposit.amount));
    }
}
