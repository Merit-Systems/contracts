// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import {Deploy}        from "../Deploy.s.sol";
import {Params}        from "../../libraries/Params.sol";
import {MockERC20}     from "solmate/test/utils/mocks/MockERC20.sol";
import {Script}        from "forge-std/Script.sol";
import {Escrow}        from "../../src/Escrow.sol";
import {PaymentParams} from "../../src/Escrow.sol";

contract DeploySepolia is Script {
    uint256[] NUM_DEPOSITS = [1, 10, 100, 200, 300, 400, 500, 1000];

    function run() public {
        MockERC20 mockUSDC = new MockERC20("USD Coin", "USDC", 6);
        mockUSDC.mint(Params.SEPOLIA_TESTER, 1000000000000000 * 10**6);

        address[] memory initialWhitelistedTokens = new address[](1);
        initialWhitelistedTokens[0] = address(mockUSDC);

        Escrow escrow = new Deploy().deploy(Params.OWNER, initialWhitelistedTokens, 0);

        for (uint256 j = 0; j < NUM_DEPOSITS.length; j++) {
            uint256 numDeposits = NUM_DEPOSITS[j];
            PaymentParams[] memory paymentParams = new PaymentParams[](numDeposits);
            uint256 baseAmount = 1000000000000000 * 10**6;
            
            // Create deposits with varying amounts
            for (uint256 i = 0; i < numDeposits; i++) {
                paymentParams[i] = PaymentParams({
                    token: mockUSDC,
                    sender: Params.SEPOLIA_TESTER,
                    recipient: Params.SEPOLIA_TESTER,
                    amount: baseAmount * (i + 1), // Each deposit will be a multiple of the base amount
                    claimPeriod: 1000000000000000 * 10**6
                });
            }

            // Mint and approve enough tokens for all deposits
            uint256 totalAmount = baseAmount * ((numDeposits * (numDeposits + 1)) / 2); // Sum of 1+2+3+...+numDeposits
            mockUSDC.mint(address(this), totalAmount);
            mockUSDC.approve(address(escrow), totalAmount);
            
            uint256 gasBefore = gasleft();
            escrow.batchPay(paymentParams, 1, block.timestamp);
            uint256 gasAfter = gasleft();
            console.log("Gas used for %d deposits:", numDeposits, gasBefore - gasAfter);
        }
    }
}
