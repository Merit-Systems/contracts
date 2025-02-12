// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "forge-std/Test.sol";

import {Errors}    from "libraries/Errors.sol";
import {Params}    from "libraries/Params.sol";
import {Base_Test} from "./Base.t.sol";

contract Inflation_Test is Base_Test {

    function test_inflate() 
        public
        _init
    {
        uint repoId = 0;

        (
            uint totalSharesBefore,
            uint inflationRate,
            ,
            ,
            ,
            ,
        ) = ledger.repos(repoId);

        vm.startPrank(alice);
        vm.warp(block.timestamp + 365 days);
        ledger.inflate(repoId);

        assertEq(totalSharesBefore, 300e18);
        assertEq(
            totalSharesBefore + (totalSharesBefore * inflationRate*1e14 / 1e18),
            330e18
        );
    }
}