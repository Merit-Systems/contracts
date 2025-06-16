// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {console} from "forge-std/console.sol";

import {Escrow} from "../src/Escrow.sol";
import {IEscrow} from "../interface/IEscrow.sol";
import {EventEmitter} from "./EventEmitter.s.sol";

contract DeployAnvil is EventEmitter {
    
    function run() external {
        vm.startBroadcast(OWNER_PRIVATE_KEY);
        
        // Deploy mock ERC20 tokens for testing
        token1 = new MockERC20("Test Token 1", "TKN1", 18);
        token2 = new MockERC20("Test Token 2", "TKN2", 6);
        
        // Prepare initial whitelisted tokens
        address[] memory initialTokens = new address[](2);
        initialTokens[0] = address(token1);
        initialTokens[1] = address(token2);
        
        // Deploy Escrow contract
        escrow = new Escrow(
            OWNER,
            SIGNER,
            initialTokens,
            FEE_BPS,
            BATCH_LIMIT
        );

        console.log("--------------------------------");
        console.log("Escrow deployed at", address(escrow));
        console.log("--------------------------------");
        
        vm.stopBroadcast();
        
        // Now test all event-emitting functions from EventEmitter
        testAllEventEmittingFunctions();
        // Test additional scenarios for more events from EventEmitter
        testAdditionalEventScenarios();
    }
} 