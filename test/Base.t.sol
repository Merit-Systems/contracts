// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "forge-std/Test.sol";

import {MeritLedger} from "src/MeritLedger.sol";
import {Deploy}      from "../script/Deploy.s.sol";

contract Base_Test is Test {

    MeritLedger ledger;

    address alice;
    address bob;

    function setUp() public {
        Deploy deploy = new Deploy();
        ledger = MeritLedger(deploy.run());

        alice = makeAddr("alice");
        bob   = makeAddr("bob");
    }
}