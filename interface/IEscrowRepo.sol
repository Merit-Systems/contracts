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

    event Distributed(
        uint256 indexed repoId,
        uint256 indexed claimId,
        address indexed recipient,
        address token,
        uint256 amount,
        uint256 claimDeadline
    );

    event DistributedBatch(
        uint256 indexed distributionBatchId,
        uint256 indexed repoId,
        uint256 indexed accountId,
        uint256[] distributionIds,
        bytes data
    );

    event Claimed(
        uint256 indexed repoId,
        uint256 indexed claimId,
        address indexed recipient,
        uint256 amount,
        uint256 fee
    );

    event Reclaimed(
        uint256 indexed repoId,
        uint256 indexed claimId,
        address indexed admin,
        uint256 amount
    );

    event AdminSet(uint256 indexed repoId, uint256 indexed accountId, address oldAdmin, address indexed newAdmin);
    event RepoAdminChanged(uint256 indexed repoId, address indexed oldAdmin, address indexed newAdmin);
    event TokenWhitelisted(address indexed token);
    event TokenRemovedFromWhitelist(address indexed token);
    event DistributorAuthorized(uint256 indexed repoId, uint256 indexed accountId, address indexed distributor);
    event DistributorDeauthorized(uint256 indexed repoId, uint256 indexed accountId, address indexed distributor);
} 