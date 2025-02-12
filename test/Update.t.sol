// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "forge-std/Test.sol";

import {Errors}    from "libraries/Errors.sol";
import {Params}    from "libraries/Params.sol";
import {Base_Test} from "./Base.t.sol";
import {PullRequest} from "../src/MeritLedger.sol";

contract Update_Test is Base_Test {
    function test_update() 
        public 
        _init
    {
        (
            uint totalSharesBefore,
            uint inflationRate,
            ,
            ,
            ,
            ,
        ) = ledger.repos(0);

        vm.startPrank(alice);
        vm.warp(block.timestamp + 365 days);

        PullRequest[] memory pullRequests = new PullRequest[](2);
        pullRequests[0] = PullRequest(alice, 100e18);
        pullRequests[1] = PullRequest(bob,   200e18);

        ledger.update(0, pullRequests);

        (
            uint totalSharesAfter,
            ,
            ,
            ,
            ,
            ,
        ) = ledger.repos(0);

        assertEq(totalSharesBefore, 300e18);
        assertEq(totalSharesAfter,  totalSharesBefore + 30e18);
        assertEq(
            totalSharesAfter,
            totalSharesBefore + (totalSharesBefore * (inflationRate * 1e14) / 1e18)
        );
    }
}