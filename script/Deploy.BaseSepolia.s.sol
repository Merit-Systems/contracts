// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Deploy}    from "./Deploy.s.sol";
import {Params}    from "../libraries/Params.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Script} from "forge-std/Script.sol";

contract DeployBaseSepolia is Script {
    function run() public {
      vm.startBroadcast();

      MockERC20 mockUSDC = new MockERC20("USD Coin", "USDC", 6);
      mockUSDC.mint(Params.BASE_SEPOLIA_TESTER, 1000000000000000 * 10**6);

      vm.stopBroadcast();

      address[] memory initialWhitelistedTokens = new address[](3);
      initialWhitelistedTokens[0] = Params.BASE_SEPOLIA_WETH;
      initialWhitelistedTokens[1] = Params.BASE_SEPOLIA_USDC;
      initialWhitelistedTokens[2] = address(mockUSDC);

      new Deploy().deploy(Params.OWNER, initialWhitelistedTokens, 0);
    }
}