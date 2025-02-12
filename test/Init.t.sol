// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "forge-std/Test.sol";

import {Errors}    from "libraries/Errors.sol";
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
}