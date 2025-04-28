// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {DeployTestBase} from "./Deploy.Test.Base.s.sol";
import {Params}         from "../libraries/Params.sol";
import {Script}         from "forge-std/Script.sol";
import {CreatePayments} from "./utils/CreatePayments.s.sol";
import {Escrow}         from "../src/Escrow.sol";

contract DeployBaseSepolia is DeployTestBase {
    function run() public {
        address[] memory testers = new address[](3);
        testers[0] = Params.BASESEPOLIA_TESTER;
        testers[1] = Params.BASESEPOLIA_TESTER_JSON;
        testers[2] = Params.BASESEPOLIA_TESTER_SHAFU;

        deployTestEnvironment(
            testers,
            Params.BASESEPOLIA_WETH,
            Params.BASESEPOLIA_USDC,
            Params.BASESEPOLIA_OWNER,
            Params.BASESEPOLIA_SIGNER
        );

        createTestPayments(
            Params.BASESEPOLIA_TESTER_SHAFU,
            Params.BASESEPOLIA_TESTER_JSON
        );
    }
}