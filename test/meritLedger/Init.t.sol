// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "forge-std/Test.sol";

import {Errors}    from "libraries/Errors.sol";
import {Params}    from "libraries/Params.sol";
import {Base_Test} from "./Base.t.sol";

contract Init_Test is Base_Test {

    function test_init() public {
        uint repoId = init();

        (
            uint    totalShares,
            uint    dilutionRate,
            uint    lastSnapshotTime,
            bool    initialized,
            uint    ownerId
        ) = ledger.repos(repoId);

        assertEq(totalShares,       300e18);
        assertEq(dilutionRate,      1_000);
        assertEq(lastSnapshotTime,  block.timestamp);
        assertEq(initialized,       true);
        assertEq(ownerId,           0);
    }

    function test_init_1Contributor_fuzz(uint weight) public {
        vm.assume(weight > 0);

        address[] memory contributors = new address[](1);
        contributors[0] = alice;

        uint   [] memory shares       = new uint   [](1);
        shares[0] = weight;

        vm.prank(Params.OWNER);
        ledger.init(0, alice, contributors, shares, 1_000);
    }

    function test_init_2Contributors_fuzz(uint weight) public {
        uint repoId = 0;

        vm.assume(weight > 0);
        vm.assume(weight < type(uint).max/2);

        address[] memory contributors = new address[](2);
        contributors[0] = alice;
        contributors[1] = bob;

        uint   [] memory shares       = new uint   [](2);
        shares[0] = weight;
        shares[1] = weight;

        vm.prank(Params.OWNER);
        ledger.init(repoId, alice, contributors, shares, 1_000);

        (uint totalShares,,,,) = ledger.repos(repoId);

        assertEq(totalShares, weight * 2);
    }

    function test_init_fail_alreadyInitialized() 
        public 
        _init 
    {
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

    function test_init_fail_zeroShare() public {
        address[] memory contributors = new address[](1);
        contributors[0] = alice;

        uint   [] memory shares       = new uint   [](1);
        shares[0] = 0;

        vm.startPrank(Params.OWNER);
        expectRevert(Errors.ZERO_SHARE);
        ledger.init(0, alice, contributors, shares, 10);
    }
}