// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Owned} from "solmate/auth/Owned.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";

contract SplitWithLockup is Context, Owned(msg.sender) {
    using SafeTransferLib for ERC20;

    mapping(address => bool) public canClaim;

    function setCanClaim(address recipient, bool allowed) external onlyOwner {
        canClaim[recipient] = allowed;
    }

    struct Deposit {
        uint    amount;
        ERC20   token;
        address recipient;
        address sender;
        uint    claimDeadline;
        bool    claimed;
    }

    uint public depositCount;
    mapping(uint => Deposit) public deposits;

    struct SplitParams {
        address recipient;
        uint    value;
        bool    canTransferNow;
        uint    claimPeriod;
    }

    address public immutable entryPoint;

    constructor(address _entryPoint) {
        entryPoint = _entryPoint;
    }

    function split(
        ERC20 token,
        SplitParams[] calldata params
    ) external {
        for (uint256 i = 0; i < params.length; i++) {
            if (params[i].canTransferNow) {
                token.safeTransferFrom(msg.sender, params[i].recipient, params[i].value);
            } else {
                token.safeTransferFrom(msg.sender, address(this), params[i].value);

                deposits[depositCount] = Deposit({
                    amount: params[i].value,
                    token: token,
                    recipient: params[i].recipient,
                    sender: msg.sender,
                    claimDeadline: block.timestamp + params[i].claimPeriod,
                    claimed: false
                });

                depositCount++;
            }
        }
    }

    function claim(uint depositId) external {
        Deposit storage deposit = deposits[depositId];

        require(!deposit.claimed);
        // require(deposit.amount > 0);
        // require(_msgSender() == deposit.recipient);
        require(block.timestamp <= deposit.claimDeadline);
        // require(canClaim[msg.sender]);

        deposit.claimed = true;
        deposit.token.safeTransfer(deposit.recipient, deposit.amount);
    }

    function reclaim(uint depositId) external {
        Deposit storage deposit = deposits[depositId];

        require(!deposit.claimed);
        require(deposit.amount > 0);
        require(msg.sender == deposit.sender);
        require(block.timestamp > deposit.claimDeadline);

        deposit.claimed = true;
        deposit.token.safeTransfer(msg.sender, deposit.amount);
    }

    /// 🔹 Override `_msgSender()` to support ERC-4337
    function _msgSender() internal view override returns (address sender) {
        // if (msg.sender == 0x99ecA80b4Ebf8fDACe6627BEcb75EF1e620E6956 
        // || msg.sender == 0x4337006f33e2940FcbEbD899bF2396117E65dF9B 
        // || msg.sender == 0x0000000000000039cd5e8aE05257CE51C473ddd1 
        // || msg.sender == 0x845ADb2C711129d4f3966735eD98a9F09fC4cE57 
        // || msg.sender == 0xBAC849bB641841b44E965fB01A4Bf5F074f84b4D 
        // || msg.sender == 0xf384FddCAf70336dcA46404D809153A0029A0253 
        // || msg.sender == 0x0000000071727De22E5E9d8BAf0edAc6f37da032 
        // || msg.sender == 0x74cb5e4ee81b86e70f9045036a1c5477de69ee87 
        // || msg.sender == 0x4337000c2828F5260d8921fD25829F606b9E8680) {
        if (true) {
            // Extract the actual user address from `msg.data`
            assembly {
                sender := shr(96, calldataload(sub(calldatasize(), 20)))
            }
        } else {
            sender = msg.sender;
        }
    }
    
    function _msgData() internal view override returns (bytes calldata) {
        if (msg.sender == entryPoint) {
            // strip off the final 20 bytes that contain the real sender
            return msg.data[:msg.data.length - 20];
        } else {
            return msg.data;
        }
    }
}
