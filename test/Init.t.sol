// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "forge-std/Test.sol";

import {Errors}    from "libraries/Errors.sol";
import {Base_Test} from "./Base.t.sol";

contract Init_Test is Base_Test {

    function test_init() public {
        uint    repoId = 0;

        address[] memory contributors = new address[](2);
        contributors[0] = alice;
        contributors[1] = bob;

        uint   [] memory shares       = new uint   [](2);
        shares[0] = 100;
        shares[1] = 200;

        uint inflationRate = 10;

        ledger.init(repoId, alice, contributors, shares, inflationRate);
    }

}