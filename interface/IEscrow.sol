// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IEscrow {
    event InitializedRepo(
        uint256 indexed repoId,
        uint256 indexed instanceId,
        address[] admins
    );

    event FundedRepo(
        uint256 indexed repoId,
        uint256 indexed instanceId,
        address indexed token,
        address sender,
        uint256 netAmount,
        uint256 feeAmount,
        bytes data
    );

    event DistributedFromRepoBatch(
        uint256 indexed batchId,
        uint256 indexed repoId,
        uint256 indexed instanceId,
        uint256[] distributionIds,
        bytes data
    );

    event DistributedFromRepo(
        uint256 indexed batchId,
        uint256 indexed distributionId,
        address indexed recipient,
        address token,
        uint256 amount,
        uint256 claimDeadline
    );

    event DistributedFromSenderBatch(
        uint256 indexed batchId,
        uint256[] distributionIds,
        bytes data
    );

    event DistributedFromSender(
        uint256 indexed batchId,
        uint256 indexed distributionId,
        address indexed payer,
        address recipient,
        address token,
        uint256 amount,
        uint256 claimDeadline
    );

    event ClaimedBatch(
        uint256 indexed batchId,
        uint256[] distributionIds,
        address indexed recipient,
        bytes data
    );

    event Claimed(
        uint256 indexed batchId,
        uint256 indexed distributionId,
        address indexed recipient,
        uint256 amount,
        uint256 fee
    );

    event ReclaimedRepoFunds(
        uint256 indexed repoId,
        uint256 indexed instanceId,
        address indexed token,
        address admin,
        uint256 amount
    );

    event ReclaimedRepoDistributionsBatch(
        uint256 indexed batchId,
        uint256 indexed repoId,
        uint256 indexed instanceId,
        uint256[] distributionIds,
        bytes data
    );

    event ReclaimedRepoDistribution(
        uint256 indexed batchId,
        uint256 indexed distributionId,
        address indexed reclaimer,
        uint256 amount
    );


    event ReclaimedSenderDistributionsBatch(
        uint256 indexed batchId,
        uint256[] distributionIds,
        bytes data
    );

    event ReclaimedSenderDistribution(
        uint256 indexed batchId,
        uint256 indexed distributionId,
        address indexed payer,
        uint256 amount
    );


    event AddedAdmin(uint256 indexed repoId, uint256 indexed instanceId, address oldAdmin, address indexed newAdmin);
    event RemovedAdmin(uint256 indexed repoId, uint256 indexed instanceId, address indexed oldAdmin);
    event WhitelistedToken(address indexed token);
    event AddedDistributor(uint256 indexed repoId, uint256 indexed instanceId, address indexed distributor);
    event RemovedDistributor(uint256 indexed repoId, uint256 indexed instanceId, address indexed distributor);
    event BatchLimitSet(uint256 newBatchLimit);
    event FeeOnClaimSet(uint256 oldFee, uint256 newFee);
    event FeeOnFundSet(uint256 oldFee, uint256 newFee);
    event FeeRecipientSet(address indexed oldRecipient, address indexed newRecipient);
    event SignerSet(address indexed oldSigner, address indexed newSigner);
} 