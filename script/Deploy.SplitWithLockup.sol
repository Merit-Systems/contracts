// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SplitWithLockup} from "../src/Payments/SplitWithLockup.sol";
import {Script} from "forge-std/Script.sol";
import {Params} from "../libraries/Params.sol";

contract DeploySplitWithLockup is Script {
    function run() public {
        vm.startBroadcast();
        new SplitWithLockup(Params.OWNER);
        vm.stopBroadcast();
    }
}
