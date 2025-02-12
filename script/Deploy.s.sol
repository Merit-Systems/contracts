// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "forge-std/Script.sol";
import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {MeritLedger} from "src/MeritLedger.sol";
import {Params}      from "libraries/Params.sol";

contract Deploy is Script {
    function run() public returns (address) {
        MeritLedger ledger = new MeritLedger(ERC20(Params.MAINNET_USDC));
        ledger.transferOwnership(Params.OWNER);
        return address(ledger);
    }
}