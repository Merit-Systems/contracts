// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Escrow} from "../src/Payments/Escrow.sol";
import {DepositParams} from "../interface/IEscrow.sol";
import {Deploy} from "../script/Deploy.s.sol";

contract Gas_Test is Test {
    Escrow escrow;
    MockERC20 mockUSDC;
    address owner;
    address tester;

    function setUp() public {
        owner = makeAddr("owner");
        tester = makeAddr("tester");
        
        mockUSDC = new MockERC20("USD Coin", "USDC", 6);
        
        address[] memory initialWhitelistedTokens = new address[](1);
        initialWhitelistedTokens[0] = address(mockUSDC);
        
        escrow = new Deploy().deploy(owner, initialWhitelistedTokens, 0);
    }

    function test_measureBatchDepositGas() public {
        uint256[] memory batchSizes = new uint256[](5);
        batchSizes[0] = 1;
        batchSizes[1] = 10;
        batchSizes[2] = 50;
        batchSizes[3] = 100;
        batchSizes[4] = 1000;

        for (uint256 i = 0; i < batchSizes.length; i++) {
            uint256 batchSize = batchSizes[i];
            DepositParams[] memory depositParams = new DepositParams[](batchSize);
            uint256 baseAmount = 1000000; // 1 USDC (6 decimals)
            
            // Create deposits with varying amounts
            for (uint256 j = 0; j < batchSize; j++) {
                depositParams[j] = DepositParams({
                    token: mockUSDC,
                    sender: tester,
                    recipient: tester,
                    amount: baseAmount * (j + 1),
                    claimPeriod: 1 days
                });
            }

            // Mint and approve enough tokens for all deposits
            uint256 totalAmount = baseAmount * ((batchSize * (batchSize + 1)) / 2);
            mockUSDC.mint(address(this), totalAmount);
            mockUSDC.approve(address(escrow), totalAmount);
            
            // Measure gas
            uint256 gasBefore = gasleft();
            escrow.batchDeposit(depositParams, 1, block.timestamp);
            uint256 gasAfter = gasleft();
            uint256 gasUsed = gasBefore - gasAfter;
            
            console2.log("Batch size:", batchSize);
            console2.log("Gas used:", gasUsed);
            console2.log("Gas per deposit:", gasUsed / batchSize);
            console2.log("-------------------");
        }
    }
} 