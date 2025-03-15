// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface ISplitWithLockup {
    event DepositCreated(
        uint    indexed depositId,
        address indexed token,
        address indexed recipient,
        address         sender,
        uint            amount,
        uint            claimDeadline
    );

    event Claimed(
        uint    indexed depositId,
        address indexed recipient,
        uint            amount
    );

    event Reclaimed(
        uint    indexed depositId,
        address indexed sender,
        uint            amount
    );

    event CanClaimSet(
        address indexed recipient,
        bool            status
    );

    event TokenWhitelisted(address indexed token);
    event TokenRemovedFromWhitelist(address indexed token);
}
