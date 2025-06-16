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
    // Anvil default addresses and keys
    address constant ANVIL_OWNER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address constant ANVIL_SIGNER = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address constant ANVIL_USER1 = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    address constant ANVIL_USER2 = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;
    address constant ANVIL_RECIPIENT = 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65;
    
    uint256 constant ANVIL_OWNER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 constant ANVIL_SIGNER_KEY = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    
    function run() external {
        // Initialize EventEmitter with Anvil addresses
        initialize(
            ANVIL_OWNER,
            ANVIL_SIGNER,
            ANVIL_USER1,
            ANVIL_USER2,
            ANVIL_RECIPIENT,
            250, // 2.5% fee
            10,  // batch limit
            ANVIL_OWNER_KEY,
            ANVIL_SIGNER_KEY
        );
        
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