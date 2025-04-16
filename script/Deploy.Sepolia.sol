// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {DeployTestBase} from "./Deploy.Test.Base.s.sol";
import {Params} from "../libraries/Params.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Script} from "forge-std/Script.sol";
import {CreatePayments} from "./utils/CreatePayments.s.sol";
import {Escrow} from "../src/Escrow.sol";

contract DeploySepolia is DeployTestBase {
  function run() public {
    address[] memory testers = new address[](3);
    testers[0] = Params.SEPOLIA_TESTER;
    testers[1] = Params.SEPOLIA_TESTER_JSON;
    testers[2] = Params.SEPOLIA_TESTER_SHAFU;

    (Escrow escrow, MockERC20 mockUSDC) = deployTestEnvironment(
      testers,
      Params.SEPOLIA_WETH,
      Params.SEPOLIA_USDC,
      Params.OWNER
    );

    createTestPayments(
      address(escrow),
      address(mockUSDC),
      Params.SEPOLIA_TESTER_SHAFU,
      Params.SEPOLIA_TESTER_JSON
    );
  }
}
