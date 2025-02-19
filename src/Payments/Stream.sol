// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ud60x18 } from "@prb/math/src/UD60x18.sol";
import { ISablierLockup } from "@sablier/lockup/src/interfaces/ISablierLockup.sol";
import { Broker, Lockup, LockupLinear } from "@sablier/lockup/src/types/DataTypes.sol";

contract Stream {
    IERC20 public constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ISablierLockup public constant LOCKUP = ISablierLockup(0x7C01AA3783577E15fD7e272443D44B92d5b21056);

    function createStream(uint128 totalAmount, address recipient, uint40 duration) public returns (uint256 streamId) {
        USDC.transferFrom(msg.sender, address(this), totalAmount);
        USDC.approve(address(LOCKUP), totalAmount);

        Lockup.CreateWithDurations memory params;

        params.sender       = msg.sender; 
        params.recipient    = recipient; 
        params.totalAmount  = totalAmount; 
        params.token        = USDC; 
        params.cancelable   = true; 
        params.transferable = true; 
        // params.broker = Broker(address(0), ud60x18(0)); // Optional parameter for charging a fee

        LockupLinear.UnlockAmounts memory unlockAmounts = LockupLinear.UnlockAmounts({ start: 0, cliff: 0 });
        LockupLinear.Durations memory durations = LockupLinear.Durations({
            cliff: 0,        // no cliff
            total: duration
         });

        streamId = LOCKUP.createWithDurationsLL(params, unlockAmounts, durations);
    }
}