// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Deploy}         from "./Deploy.s.sol";
import {Params}         from "../libraries/Params.sol";
import {MockERC20}      from "solmate/test/utils/mocks/MockERC20.sol";
import {Script}         from "forge-std/Script.sol";
import {CreatePayments} from "./utils/CreatePayments.s.sol";
import {Escrow}         from "../src/Escrow.sol";
import {DepositEncoder} from "../libraries/Encoder.sol";

abstract contract DeployTestBase is Deploy {
    uint constant AMOUNT_TO_MINT = 100_000_000 * 10**6;
    
    Escrow    public escrow;
    MockERC20 public mockUSDC;

    function deployTestEnvironment(
        address[] memory testers,
        address weth,
        address usdc,
        address owner,
        address signer
    ) internal {
        vm.startBroadcast();

        mockUSDC = new MockERC20("USD Coin", "USDC", 6);
        for (uint i = 0; i < testers.length; i++) {
            mockUSDC.mint(testers[i], AMOUNT_TO_MINT);
        }

        vm.stopBroadcast();

        address[] memory initialWhitelistedTokens = new address[](3);
        initialWhitelistedTokens[0] = weth;
        initialWhitelistedTokens[1] = usdc;
        initialWhitelistedTokens[2] = address(mockUSDC);

        escrow = deploy(owner, signer, initialWhitelistedTokens, 0, Params.BATCH_DEPOSIT_LIMIT);
    }

    function createTestPayments(
        address sender,
        address recipient
    ) internal {
        new CreatePayments().createPayment(
            address(escrow),
            address(mockUSDC),
            5,
            100 * 10**6,
            sender,
            recipient,
            DepositEncoder.DEPOSIT_TYPE.REPO,
            100
        );
    }
}
