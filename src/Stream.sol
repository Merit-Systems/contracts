// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20}                       from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ud60x18}                      from "@prb/math/src/UD60x18.sol";
import {ISablierLockup}               from "@sablier/lockup/src/interfaces/ISablierLockup.sol";
import {Broker, Lockup, LockupLinear} from "@sablier/lockup/src/types/DataTypes.sol";

contract StreamCreator {
    IERC20         public immutable token;
    ISablierLockup public immutable lockup;

    constructor(address _token, address _lockup) {
        token  = IERC20(_token);
        lockup = ISablierLockup(_lockup);
    }

    function create(
        uint128 totalAmount,
        address recipient,
        uint40  duration
    ) 
        external 
        returns (uint256 streamId)
    {
        token.transferFrom(msg.sender, address(this), totalAmount);
        token.approve(address(lockup), totalAmount);

        Lockup.CreateWithDurations memory params;

        params.sender       = msg.sender;
        params.recipient    = recipient;
        params.totalAmount  = totalAmount;
        params.token        = token;
        params.cancelable   = false;
        params.transferable = false;

        LockupLinear.UnlockAmounts memory unlockAmounts = LockupLinear.UnlockAmounts({ start: 0, cliff: 0 });
        LockupLinear.Durations memory durations = LockupLinear.Durations({
            cliff: 0,
            total: duration
         });

        streamId = lockup.createWithDurationsLL(params, unlockAmounts, durations);
    }
}