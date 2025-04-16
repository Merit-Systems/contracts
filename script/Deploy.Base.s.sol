// SPDX-License-Identifier: MIT	
pragma solidity ^0.8.26;	

import {Deploy} from "./Deploy.s.sol";	
import {Params} from "../libraries/Params.sol";	
import {Script} from "forge-std/Script.sol";	

contract DeployBase is Deploy {	
    function run() public {	
        address[] memory initialWhitelistedTokens = new address[](1);	
        initialWhitelistedTokens[0] = Params.BASE_USDC;	

        deploy(Params.OWNER, initialWhitelistedTokens, Params.BASE_FEE_BPS);	
    }	
}