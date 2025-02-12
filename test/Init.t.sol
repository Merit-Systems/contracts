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
            uint    inflationRate,
            uint    lastSnapshotTime,
            bool    initialized,
            uint    ownerId,
            bytes32 paymentMerkleRoot,
            uint    newSharesPerUpdate
        ) = ledger.repos(repoId);

        assertEq(totalShares,        300);
        assertEq(inflationRate,      10);
        assertEq(lastSnapshotTime,   block.timestamp);
        assertEq(initialized,        true);
        assertEq(ownerId,            0);
        assertEq(paymentMerkleRoot,  bytes32(0));
        assertEq(newSharesPerUpdate, 0);
    }

    function test_init_fail_alreadyInitialized() 
        public 
        _init() 
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