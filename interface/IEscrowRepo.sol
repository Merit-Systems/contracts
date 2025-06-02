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
    event RecipientAssigned(uint256 indexed repoId, uint256 indexed depositId, address indexed recipient);
    event Claimed(uint256 indexed repoId, uint256 indexed depositId, address recipient, uint256 amount);
    event Reclaimed(uint256 indexed repoId, uint256 indexed depositId, address sender,   uint256 amount);
    event CanClaimSet(address indexed recipient, bool status);
    event TokenWhitelisted(address token);
    event TokenRemovedFromWhitelist(address token);

    event Distribute(uint256 indexed repoId, uint256 indexed depositId, address indexed recipient);
    event BatchDistribute(uint256 indexed repoId, uint256[] depositIds, address[] recipients);

    /* ------------------------------------------------------------------- */
    /*                              FUNCTIONS                              */
    /* ------------------------------------------------------------------- */
    function batchClaim(
        uint256   repoId,
        uint256[] calldata depositIds,
        bool      status,
        uint256   deadline,
        uint8     v,
        bytes32   r,
        bytes32   s
    ) external;

    function batchReclaim(uint256 repoId, uint256[] calldata depositIds) external;
} 