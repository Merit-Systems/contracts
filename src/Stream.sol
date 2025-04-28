// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20}                        from "solmate/tokens/ERC20.sol";
import {ud60x18}                      from "@prb/math/src/UD60x18.sol";
import {ISablierLockup}               from "@sablier/lockup/src/interfaces/ISablierLockup.sol";
import {Broker, Lockup, LockupLinear} from "@sablier/lockup/src/types/DataTypes.sol";

contract StreamCreator {
    ERC20          public immutable token;
    ISablierLockup public immutable lockup;

    constructor(address _token, address _lockup) {
        token  = ERC20(_token);
        lockup = ISablierLockup(_lockup);
    }

}