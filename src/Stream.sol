// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ud60x18 } from "@prb/math/src/UD60x18.sol";
import { ISablierLockup } from "@sablier/lockup/src/interfaces/ISablierLockup.sol";
import { Broker, Lockup, LockupLinear } from "@sablier/lockup/src/types/DataTypes.sol";

contract LockupLinearStreamCreator {
    IERC20 public constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ISablierLockup public constant LOCKUP = ISablierLockup(0x7C01AA3783577E15fD7e272443D44B92d5b21056);

    /// @dev For this function to work, the sender must have approved this dummy contract to spend USDC.
    function createStream(uint128 totalAmount, address recipient) public returns (uint256 streamId) {
        USDC.transferFrom(msg.sender, address(this), totalAmount);
        USDC.approve(address(LOCKUP), totalAmount);

        Lockup.CreateWithDurations memory params;

        params.sender = msg.sender; // The sender will be able to cancel the stream
        params.recipient = recipient; 
        params.totalAmount = totalAmount; 
        params.token = USDC; 
        params.cancelable = true; 
        params.transferable = true; 
        // params.broker = Broker(address(0), ud60x18(0)); // Optional parameter for charging a fee

        LockupLinear.UnlockAmounts memory unlockAmounts = LockupLinear.UnlockAmounts({ start: 0, cliff: 0 });
        LockupLinear.Durations memory durations = LockupLinear.Durations({
            cliff: 0, // Setting a cliff of 0
            total: 52 weeks // Setting a total duration of ~1 year
         });

        // Create the LockupLinear stream using a function that sets the start time to `block.timestamp`
        streamId = LOCKUP.createWithDurationsLL(params, unlockAmounts, durations);
    }
}