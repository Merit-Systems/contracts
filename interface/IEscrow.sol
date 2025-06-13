// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IEscrow {
    event FundedRepo(
        uint256 indexed repoId,
        address indexed token,
        address indexed sender,
        uint256 amount,
        bytes data
    );

    event DistributedFromRepo(
        uint256 indexed distributionBatchId,
        uint256 indexed distributionId,
        address indexed recipient,
        address token,
        uint256 amount,
        uint256 claimDeadline
    );

    event DistributedFromRepoBatch(
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

    event ClaimedBatch(
        uint256[] distributionIds,
        address indexed recipient,
        uint256 deadline
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

    event ReclaimedRepoBatch(
        uint256[] distributionIds
    );

    event DistributedFromSender(
        uint256 indexed distributionId,
        address indexed payer,
        address indexed recipient,
        address token,
        uint256 amount,
        uint256 claimDeadline
    );

    event ReclaimedSoloBatch(
        uint256[] distributionIds
    );

    event ReclaimedSolo(
        uint256 indexed distributionId,
        address indexed payer,
        uint256 amount
    );

    event DistributedFromSenderBatch(
        uint256 indexed distributionBatchId,
        uint256[] distributionIds,
        bytes data
    );

    event AddedAdmin(uint256 indexed repoId, uint256 indexed accountId, address oldAdmin, address indexed newAdmin);
    event RemovedAdmin(uint256 indexed repoId, uint256 indexed accountId, address indexed oldAdmin);
    event WhitelistedToken(address indexed token);
    event AddedDistributor(uint256 indexed repoId, uint256 indexed accountId, address indexed distributor);
    event RemovedDistributor(uint256 indexed repoId, uint256 indexed accountId, address indexed distributor);
    event BatchLimitSet(uint256 newBatchLimit);
    event FeeSet(uint256 oldFee, uint256 newFee);
    event FeeRecipientSet(address indexed oldRecipient, address indexed newRecipient);
    event SignerSet(address indexed oldSigner, address indexed newSigner);
} 