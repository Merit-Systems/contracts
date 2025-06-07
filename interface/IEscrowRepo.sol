// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IEscrowRepo {
    event Funded(
        uint256 indexed repoId,
        address indexed token,
        address indexed sender,
        uint256 amount,
        uint256 fee
    );

    event Deposited(
        uint256 indexed repoId,
        uint256 indexed claimId,
        address indexed recipient,
        address token,
        uint256 amount,
        uint256 claimDeadline
    );

    event Claimed(
        uint256 indexed repoId,
        uint256 indexed claimId,
        address indexed recipient,
        uint256 amount
    );

    event Reclaimed(
        uint256 indexed repoId,
        uint256 indexed claimId,
        address indexed admin,
        uint256 amount
    );

    event CanClaimSet(address indexed recipient, bool status);
    event AdminSet(uint256 indexed repoId, uint256 indexed accountId, address indexed oldAdmin, address indexed newAdmin);
    event RepoAdminChanged(uint256 indexed repoId, address indexed oldAdmin, address indexed newAdmin);
    event TokenWhitelisted(address indexed token);
    event TokenRemovedFromWhitelist(address indexed token);
    event DepositorAuthorized(uint256 indexed repoId, uint256 indexed accountId, address indexed depositor);
    event DepositorDeauthorized(uint256 indexed repoId, uint256 indexed accountId, address indexed depositor);
} 