// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SplitWithLockup} from "../src/Payments/SplitWithLockup.sol";

contract DeploySplitWithLockup {
    function run() public returns (SplitWithLockup splitWithLockup) {
        splitWithLockup = new SplitWithLockup();
        return splitWithLockup;
    }
}
