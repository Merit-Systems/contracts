// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Deploy} from "./Deploy.Core.s.sol";
import {Params} from "../libraries/Params.sol";
import {Script} from "forge-std/Script.sol";
import {Escrow} from "../src/Escrow.sol";
import {console} from "forge-std/console.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

contract DeployBaseSepolia is Deploy {
    function run() public returns (Escrow escrow) {
        vm.startBroadcast();
        MockERC20 mockUSDC = new MockERC20("USD Coin", "USDC", 6);
        mockUSDC.mint(Params.BASESEPOLIA_OWNER, 1_000_000 * 10**6); // Mint 1M USDC
        vm.stopBroadcast();

        address[] memory initialWhitelistedTokens = new address[](2);
        initialWhitelistedTokens[0] = address(mockUSDC);
        initialWhitelistedTokens[1] = 0xBFB1Dd9080d9D2C590Aa0DF4dd12f6af9eA26C03;

        escrow = deploy(
            Params.BASESEPOLIA_OWNER,
            Params.BASESEPOLIA_SIGNER,
            initialWhitelistedTokens,
            Params.BASESEPOLIA_FEE_BPS,
            Params.BATCH_LIMIT
        );

        console.log("Mock USDC deployed at:", address(mockUSDC));
        console.log("Escrow deployed at:", address(escrow));
    }
} 