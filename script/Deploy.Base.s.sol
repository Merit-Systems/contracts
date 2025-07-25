// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Deploy} from "./Deploy.Core.s.sol";
import {Params} from "../libraries/Params.sol";
import {Script} from "forge-std/Script.sol";
import {Escrow} from "../src/Escrow.sol";
import {console} from "forge-std/console.sol";

contract DeployBase is Deploy {
    function run() public returns (Escrow escrow) {
        address[] memory initialWhitelistedTokens = new address[](1);
        initialWhitelistedTokens[0] = Params.BASE_USDC;

        escrow = deploy(
            Params.BASE_OWNER,
            Params.BASE_SIGNER,
            initialWhitelistedTokens,
            Params.BASE_FEE_ON_CLAIM_BPS,
            Params.BATCH_LIMIT
        );

        console.log("Escrow deployed at:", address(escrow));
    }
} 