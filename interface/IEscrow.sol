// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

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
    event DepositCreated(
        uint    indexed depositId,
        address indexed token,
        address indexed recipient,
        address         sender,
        uint            amount,
        uint            claimDeadline
    );

    event Claimed                  (uint indexed depositId, address indexed recipient, uint amount);
    event Reclaimed                (uint indexed depositId, address indexed sender,    uint amount);
    event CanClaimSet              (address indexed recipient, bool status);
    event TokenWhitelisted         (address indexed token);
    event TokenRemovedFromWhitelist(address indexed token);
    event ProtocolFeeSet           (uint    newFeeBps);
    event FeeRecipientSet          (address newFeeRecipient);
}
