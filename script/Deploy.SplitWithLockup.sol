// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SplitWithLockup} from "../src/Payments/SplitWithLockup.sol";
import {Script} from "forge-std/Script.sol";
import {Params} from "../libraries/Params.sol";

contract DeploySplitWithLockup is Script {
    function run() public {
        vm.startBroadcast();
        address[] memory initialWhitelistedTokens = new address[](1);
        initialWhitelistedTokens[0] = address(Params.SEPOLIA_WETH);
        new SplitWithLockup(Params.OWNER, initialWhitelistedTokens);
        vm.stopBroadcast();
    }
}
