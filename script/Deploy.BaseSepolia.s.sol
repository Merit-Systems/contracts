// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Deploy} from "./Deploy.Core.s.sol";
import {Params} from "../libraries/Params.sol";
import {Script} from "forge-std/Script.sol";
import {Escrow} from "../src/Escrow.sol";
import {console} from "forge-std/console.sol";
import {EventEmitter} from "./EventEmitter.s.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

contract DeployBaseSepolia is Deploy, EventEmitter {
    function run() public returns (Escrow escrow) {
        // Initialize EventEmitter with Base Sepolia addresses
        initialize(
            Params.BASESEPOLIA_OWNER,
            Params.BASESEPOLIA_SIGNER,
            Params.BASESEPOLIA_TESTER,
            Params.BASESEPOLIA_TESTER_JSON,
            Params.BASESEPOLIA_TESTER_SHAFU,
            Params.BASESEPOLIA_FEE_BPS,
            Params.BATCH_LIMIT,
            vm.envUint("OWNER_PRIVATE_KEY"),
            vm.envUint("SIGNER_PRIVATE_KEY")
        );

        // Deploy mock ERC20 tokens for testing
        token1 = new MockERC20("BaseSepolia USDC 1", "bUSDC1", 6);
        token2 = new MockERC20("BaseSepolia USDC 2", "bUSDC2", 6);
        
        // Prepare initial whitelisted tokens
        address[] memory initialWhitelistedTokens = new address[](3);
        initialWhitelistedTokens[0] = Params.BASESEPOLIA_USDC;
        initialWhitelistedTokens[1] = address(token1);
        initialWhitelistedTokens[2] = address(token2);

        escrow = deploy(
            Params.BASESEPOLIA_OWNER,
            Params.BASESEPOLIA_SIGNER,
            initialWhitelistedTokens,
            Params.BASESEPOLIA_FEE_BPS,
            Params.BATCH_LIMIT
        );

        console.log("Escrow deployed at:", address(escrow));
        console.log("BaseSepolia USDC 1 deployed at:", address(token1));
        console.log("BaseSepolia USDC 2 deployed at:", address(token2));

        // Test all event-emitting functions
        testAllEventEmittingFunctions();
        // Test additional scenarios for more events
        testAdditionalEventScenarios();
    }
} 