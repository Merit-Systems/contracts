// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Deploy} from "./Deploy.s.sol";
import {Params} from "../libraries/Params.sol";

contract DeploySepolia {
    function run() public {
        address[] memory initialWhitelistedTokens = new address[](2);
        initialWhitelistedTokens[0] = Params.SEPOLIA_WETH;
        initialWhitelistedTokens[1] = Params.SEPOLIA_USDC;

        new Deploy().deploy(Params.OWNER, initialWhitelistedTokens);
    }
}
