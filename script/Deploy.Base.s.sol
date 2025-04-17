// SPDX-License-Identifier: MIT	
pragma solidity ^0.8.26;	

import {Deploy} from "./Deploy.s.sol";	
import {Params} from "../libraries/Params.sol";	
import {Script} from "forge-std/Script.sol";	
import {Escrow} from "../src/Escrow.sol";

contract DeployBase is Deploy {	
    function run() public returns (Escrow escrow) {	
        address[] memory initialWhitelistedTokens = new address[](1);	
        initialWhitelistedTokens[0] = Params.BASE_USDC;	

        escrow = deploy(
            Params.OWNER,
            Params.SIGNER,
            initialWhitelistedTokens,
            Params.BASE_FEE_BPS,
            Params.BATCH_DEPOSIT_LIMIT
        );	
    }	
}