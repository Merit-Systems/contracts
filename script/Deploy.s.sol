// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Escrow} from "../src/Payments/Escrow.sol";
import {Params} from "../libraries/Params.sol";
import {Script} from "forge-std/Script.sol";

contract Deploy is Script {
    function deploy(
        address          owner,
        address[] memory initialWhitelistedTokens,
        uint             feeBps
    ) 
        public 
        returns (Escrow escrow)
    {
        vm.startBroadcast();

        escrow = new Escrow(
            owner,
            initialWhitelistedTokens,
            feeBps
        );

        vm.stopBroadcast();
    }
}
