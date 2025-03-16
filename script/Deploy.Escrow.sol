// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Escrow} from "../src/Payments/Escrow.sol";
import {Script} from "forge-std/Script.sol";
import {Params} from "../libraries/Params.sol";

contract DeployEscrow is Script {
    function run(address owner, address[] memory initialWhitelistedTokens) 
        public 
        returns (Escrow escrow)
    {
        vm.startBroadcast();

        bytes32 salt = bytes32(uint256(0x123)); 
        escrow = new Escrow{salt: salt}(owner, initialWhitelistedTokens);
        
        vm.stopBroadcast();
    }
}
