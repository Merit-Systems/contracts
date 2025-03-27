// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Deploy}    from "./Deploy.s.sol";
import {Params}    from "../libraries/Params.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

contract DeploySepolia {
    function run() public {
      MockERC20 testToken = new MockERC20("USDC", "USDC", 6);

      address[] memory initialWhitelistedTokens = new address[](2);
      initialWhitelistedTokens[0] = Params.SEPOLIA_WETH;
      initialWhitelistedTokens[1] = Params.SEPOLIA_USDC;
      initialWhitelistedTokens[2] = address(testToken);

      new Deploy().deploy(Params.OWNER, initialWhitelistedTokens);
    }
}
