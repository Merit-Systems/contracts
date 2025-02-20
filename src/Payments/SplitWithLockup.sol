// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Owned} from "solmate/auth/Owned.sol";

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

contract SplitWithLockup is Owned(msg.sender) {
    mapping(address => bool) public canClaim;

    function setCanClaim(address recipient, bool allowed) external onlyOwner {
        canClaim[recipient] = allowed;
    }

    uint256 public claimPeriod = 90 days; // 3 months

    struct Deposit {
        uint256 amount;
        IERC20 token;
        address recipient;
        address sender;
        uint256 claimDeadline;
        bool claimed;
    }

    uint256 public depositCount;
    mapping(uint256 => Deposit) public deposits;

    function split(
        IERC20 token,
        address[] calldata recipients,
        uint256[] calldata values,
        bool[] calldata canTransferNow
    ) external {
        require(
            recipients.length == values.length && 
            recipients.length == canTransferNow.length
        );

        for (uint256 i = 0; i < recipients.length; i++) {
            if (canTransferNow[i]) {
                // Transfer directly to the recipient
                require(
                    token.transferFrom(msg.sender, recipients[i], values[i])
                );
            } else {
                // Transfer into the contract and record a deposit
                require(
                    token.transferFrom(msg.sender, address(this), values[i])
                );

                deposits[depositCount] = Deposit({
                    amount: values[i],
                    token: token,
                    recipient: recipients[i],
                    sender: msg.sender,
                    claimDeadline: block.timestamp + claimPeriod,
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

        // Check if the owner has granted permission to this recipient
        require(canClaim[msg.sender]);

        deposit.claimed = true;
        require(
            deposit.token.transfer(msg.sender, deposit.amount)
        );
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
