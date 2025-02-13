// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "forge-std/Test.sol";

import {Errors}      from "libraries/Errors.sol";
import {Params}      from "libraries/Params.sol";
import {Base_Test}   from "./Base.t.sol";
import {PullRequest} from "../src/MeritLedger.sol";

contract Claim_Test is Base_Test {
    function test_claim() 
        public 
        _init
    {
        // deal(Params.MAINNET_USDC, address(ledger), 100e18);
        // vm.startPrank(alice);
        // vm.warp(block.timestamp + 365 days);
    }
}