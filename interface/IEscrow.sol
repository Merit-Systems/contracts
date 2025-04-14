// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "solmate/tokens/ERC20.sol";

enum Status {
    Deposited, // Initial state
    Claimed,   // Claimed by recipient
    Reclaimed  // Reclaimed by sender
}

struct PaymentParams {
    uint    amount;      // Total token amount
    ERC20   token;       // Token to deposit
    address sender;      // Funding account
    address recipient;   // Claiming account
    uint    claimPeriod; // Time window for recipient to claim
}

/**
 * @title IEscrow
 * @author shafu
 * @notice Interface for the Escrow contract.
 *         Defines the external functions and events for an escrow system where:
 *         - Senders deposit whitelisted ERC20 tokens intended for specific recipients.
 *         - Recipients can claim their deposits, requiring authorization via an EIP-712 signature from the owner.
 *         - Senders can reclaim deposits after a specified deadline if they haven't been claimed by the recipient.
 *         - A protocol fee can be configured and applied to deposits.
 */
interface IEscrow {
    event Deposited                (uint indexed paymentId, address indexed token, address indexed recipient, address sender, uint amount, uint claimDeadline);
    event Claimed                  (uint indexed paymentId, address indexed recipient, uint amount);
    event Reclaimed                (uint indexed paymentId, address indexed sender,    uint amount);
    event CanClaimSet              (address indexed recipient, bool status);
    event ProtocolFeeSet           (uint    newFeeBps);
    event FeeRecipientSet          (address newFeeRecipient);
    event TokenWhitelisted         (address indexed token);
    event TokenRemovedFromWhitelist(address indexed token);
    event BatchDeposited           (uint indexed batchId, uint repoId, uint timestamp, uint[] paymentIds);

    /**
     * @notice Deposits tokens into the escrow on behalf of a specified sender and recipient.
     * @dev A fee may be taken from the deposit if a protocol fee is set.
     * @param param A `PaymentParams` struct containing:
     * - `token`: The token to deposit.
     * - `sender`: The account responsible for funding the deposit.
     * - `recipient`: The account that can claim the deposited tokens.
     * - `amount`: The total amount of tokens to deposit (before any fee).
     * - `claimPeriod`: How long the recipient has to claim before the sender can reclaim.
     * @return paymentId The ID of the newly created payment.
     */
    function pay(PaymentParams calldata param) external returns (uint paymentId);

    /**
     * @notice Allows batch creation of multiple deposits in a single transaction.
     * @param params An array of `PaymentParams` structs for each deposit.
     * @param repoId The ID of the repository.
     * @param timestamp The timestamp of the batch deposit.
     * @return paymentIds An array of newly assigned payment IDs.
     */
    function batchPay(PaymentParams[] calldata params, uint repoId, uint timestamp) external returns (uint[] memory paymentIds);

    /**
     * @notice Claims the tokens of a single deposit, if the caller is authorized by signature.
     * @dev Calls `setCanClaim` first to verify the signature and then claims if authorized.
     * @param paymentId The ID of the payment to claim.
     * @param recipient The recipient address specified in the signature.
     * @param status The status boolean included in the signature (true means authorized).
     * @param deadline The deadline by which the signature must be used.
     * @param v Component of the ECDSA signature.
     * @param r Component of the ECDSA signature.
     * @param s Component of the ECDSA signature.
     */
    function claim(
        uint    paymentId,
        address recipient,
        bool    status,
        uint256 deadline,
        uint8   v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
     * @notice Claims multiple deposits in a single transaction, if the caller is authorized by signature.
     * @dev Similar to `claim` but operates on an array of payment IDs.
     * @param paymentIds An array of payment IDs to be claimed.
     * @param recipient The recipient address specified in the signature.
     * @param status The status boolean included in the signature (true means authorized).
     * @param deadline The deadline by which the signature must be used.
     * @param v Component of the ECDSA signature.
     * @param r Component of the ECDSA signature.
     * @param s Component of the ECDSA signature.
     */
    function batchClaim(
        uint[] calldata paymentIds,
        address         recipient,
        bool            status,
        uint256         deadline,
        uint8           v,
        bytes32         r,
        bytes32         s
    ) external;

    /**
     * @notice Reclaims a payment on behalf of the sender, if the payment is still claimable.
     * @param paymentId The ID of the payment to reclaim.
     */
    function reclaim(uint paymentId) external;


    /**
     * @notice Allows reclaiming multiple payments in a single transaction.
     * @param paymentIds An array of payment IDs to reclaim.
     */
    function batchReclaim(uint[] calldata paymentIds) external;
}
