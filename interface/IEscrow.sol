// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IEscrow {
    event Funded(
        uint256 indexed repoId,
        address indexed token,
        address indexed sender,
        uint256 amount
    );

    event DistributedRepo(
        uint256 indexed repoId,
        uint256 indexed claimId,
        address indexed recipient,
        address token,
        uint256 amount,
        uint256 claimDeadline
    );

    event DistributedRepoBatch(
        uint256 indexed distributionBatchId,
        uint256 indexed repoId,
        uint256 indexed accountId,
        uint256[] distributionIds,
        bytes data
    );

    event Claimed(
        uint256 indexed distributionId,
        address indexed recipient,
        uint256 amount,
        uint256 fee
    );

    event ReclaimedFund(
        uint256 indexed repoId,
        address indexed admin,
        uint256 amount
    );

    event ReclaimedRepo(
        uint256 indexed repoId,
        uint256 indexed distributionId,
        address indexed admin,
        uint256 amount
    );

    event DistributedSolo(
        uint256 indexed distributionId,
        address indexed payer,
        address indexed recipient,
        address token,
        uint256 amount,
        uint256 claimDeadline
    );

    event ReclaimedSolo(
        uint256 indexed distributionId,
        address indexed payer,
        uint256 amount
    );

    event DistributedSoloBatch(
        uint256 indexed distributionBatchId,
        uint256[] distributionIds
    );

    event AdminSet(uint256 indexed repoId, uint256 indexed accountId, address oldAdmin, address indexed newAdmin);
    event RepoAdminChanged(uint256 indexed repoId, address indexed oldAdmin, address indexed newAdmin);
    event TokenWhitelisted(address indexed token);
    event TokenRemovedFromWhitelist(address indexed token);
    event AddedDistributor(uint256 indexed repoId, uint256 indexed accountId, address indexed distributor);
    event RemovedDistributor(uint256 indexed repoId, uint256 indexed accountId, address indexed distributor);
} 