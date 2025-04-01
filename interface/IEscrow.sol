// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "solmate/tokens/ERC20.sol";

enum Status {
    Deposited,
    Claimed,
    Reclaimed
}

struct DepositParams {
    ERC20   token;
    address sender;
    address recipient;
    uint    amount;
    uint    claimPeriod;
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
    event Deposited                (uint indexed depositId, address indexed token, address indexed recipient, address sender, uint amount, uint claimDeadline);
    event Claimed                  (uint indexed depositId, address indexed recipient, uint amount);
    event Reclaimed                (uint indexed depositId, address indexed sender,    uint amount);
    event CanClaimSet              (address indexed recipient, bool status);
    event ProtocolFeeSet           (uint    newFeeBps);
    event FeeRecipientSet          (address newFeeRecipient);
    event TokenWhitelisted         (address indexed token);
    event TokenRemovedFromWhitelist(address indexed token);

    /**
     * @notice Deposits tokens into the escrow on behalf of a specified sender and recipient.
     * @dev A fee may be taken from the deposit if a protocol fee is set.
     * @param param A `DepositParams` struct containing:
     * - `token`: The token to deposit.
     * - `sender`: The account responsible for funding the deposit.
     * - `recipient`: The account that can claim the deposited tokens.
     * - `amount`: The total amount of tokens to deposit (before any fee).
     * - `claimPeriod`: How long the recipient has to claim before the sender can reclaim.
     * @return depositId The ID of the newly created deposit.
     */
    function deposit(DepositParams calldata param) external returns (uint depositId);
}
