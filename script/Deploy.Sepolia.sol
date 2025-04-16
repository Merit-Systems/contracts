// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Deploy}         from "./Deploy.s.sol";
import {Params}         from "../libraries/Params.sol";
import {MockERC20}      from "solmate/test/utils/mocks/MockERC20.sol";
import {Script}         from "forge-std/Script.sol";
import {CreatePayments} from "./utils/CreatePayments.s.sol";
import {Escrow}         from "../src/Escrow.sol";

contract DeploySepolia is Script {

  uint constant AMOUNT_TO_MINT = 100_000_000 * 10**6;

  function run() public {
    vm.startBroadcast();

    MockERC20 mockUSDC = new MockERC20("USD Coin", "USDC", 6);
    mockUSDC.mint(Params.SEPOLIA_TESTER,       AMOUNT_TO_MINT);
    mockUSDC.mint(Params.SEPOLIA_TESTER_JSON,  AMOUNT_TO_MINT);
    mockUSDC.mint(Params.SEPOLIA_TESTER_SHAFU, AMOUNT_TO_MINT);

    vm.stopBroadcast();

    address[] memory initialWhitelistedTokens = new address[](3);
    initialWhitelistedTokens[0] = Params.SEPOLIA_WETH;
    initialWhitelistedTokens[1] = Params.SEPOLIA_USDC;
    initialWhitelistedTokens[2] = address(mockUSDC);

    Escrow escrow = new Deploy().deploy(Params.OWNER, initialWhitelistedTokens, 0);

    new CreatePayments().deploy(
      address(escrow),
      address(mockUSDC),
      5,
      100 * 10**6,
      Params.SEPOLIA_TESTER_SHAFU,
      Params.SEPOLIA_TESTER_JSON
    );
  }
}
