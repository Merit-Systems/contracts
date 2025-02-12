// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "forge-std/Test.sol";

import {MeritLedger} from "src/MeritLedger.sol";
import {Params}      from "libraries/Params.sol";
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

    function expectRevert(string memory message) public {
        vm.expectRevert(bytes(message));
    }

    function init() internal returns (uint) {
        uint repoId = 0;

        address[] memory contributors = new address[](2);
        contributors[0] = alice;
        contributors[1] = bob;

        uint   [] memory shares       = new uint   [](2);
        shares[0] = 100e18;
        shares[1] = 200e18;

        uint inflationRate = 1_000;

        vm.prank(Params.OWNER);
        ledger.init(repoId, alice, contributors, shares, inflationRate);
        return repoId;
    }

    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier _init() {
        init();
        _;
    }
}