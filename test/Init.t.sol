// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "forge-std/Test.sol";

import {Errors}    from "libraries/Errors.sol";
import {Params}    from "libraries/Params.sol";
import {Base_Test} from "./Base.t.sol";

contract Init_Test is Base_Test {

    function test_init() public {
        init();
    }

    function test_init_fail_alreadyInitialized() public {
        init();

        expectRevert(Errors.ALREADY_INITIALIZED);
        init();
    }

    function test_init_fail_lengthMismatch() public {
        address[] memory contributors = new address[](2);
        contributors[0] = alice;
        contributors[1] = bob;

        uint   [] memory shares       = new uint   [](1);
        shares[0] = 100;

        vm.startPrank(Params.OWNER);
        expectRevert(Errors.LENGTH_MISMATCH);
        ledger.init(0, alice, contributors, shares, 10);
    }
}