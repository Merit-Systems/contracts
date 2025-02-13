// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "forge-std/Test.sol";

import {Errors}      from "libraries/Errors.sol";
import {Params}      from "libraries/Params.sol";
import {Base_Test}   from "./Base.t.sol";
import {MeritLedger} from "../src/MeritLedger.sol";

contract Update_Test is Base_Test {
    function test_update() 
        public 
        _init
    {
        (uint totalSharesBefore, uint dilutionRate,,,) = ledger.repos(0);

        vm.startPrank(alice);
        vm.warp(block.timestamp + 365 days);

        MeritLedger.PullRequest[] memory pullRequests = new MeritLedger.PullRequest[](2);
        pullRequests[0] = MeritLedger.PullRequest(alice, 100e18);
        pullRequests[1] = MeritLedger.PullRequest(bob,   200e18);

        ledger.update(0, pullRequests);

        (uint totalSharesAfter,,,,) = ledger.repos(0);

        assertEq(totalSharesBefore, 300e18);
        assertEq(totalSharesAfter,  totalSharesBefore + 30e18);
        assertEq(
            totalSharesAfter,
            totalSharesBefore + (totalSharesBefore * (dilutionRate * 1e14) / 1e18)
        );
    }

    function test_update_fail_notInitialized() 
        public 
    {
        vm.startPrank(alice);
        vm.warp(block.timestamp + 1);

        MeritLedger.PullRequest[] memory pullRequests = new MeritLedger.PullRequest[](0);

        expectRevert(Errors.NOT_INITIALIZED);
        ledger.update(0, pullRequests);
    }

    function test_update_fail_noPullRequests() 
        public 
        _init
    {
        vm.startPrank(alice);
        vm.warp(block.timestamp + 1);

        MeritLedger.PullRequest[] memory pullRequests = new MeritLedger.PullRequest[](0);

        expectRevert(Errors.NO_PULL_REQUESTS);
        ledger.update(0, pullRequests);
    }

    function test_update_fail_noTimeElapsed() 
        public 
        _init
    {
        vm.startPrank(alice);

        MeritLedger.PullRequest[] memory pullRequests = new MeritLedger.PullRequest[](1);
        pullRequests[0] = MeritLedger.PullRequest(alice, 100e18);

        expectRevert(Errors.NO_TIME_ELAPSED);
        ledger.update(0, pullRequests);
    }

    function test_update_fail_noWeights() 
        public 
        _init
    {
        vm.startPrank(alice);
        vm.warp(block.timestamp + 1 days);

        MeritLedger.PullRequest[] memory pullRequests = new MeritLedger.PullRequest[](1);
        pullRequests[0] = MeritLedger.PullRequest(alice, 0);

        expectRevert(Errors.NO_WEIGHTS);
        ledger.update(0, pullRequests);
    }
}