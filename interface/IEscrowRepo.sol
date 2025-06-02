// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IEscrowRepo {
    /* ------------------------------------------------------------------- */
    /*                                EVENTS                               */
    /* ------------------------------------------------------------------- */
    event RepoAdded(uint256 indexed repoId, address indexed admin);
    event RepoAdminChanged(uint256 indexed repoId, address indexed oldAdmin, address indexed newAdmin);
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
} 