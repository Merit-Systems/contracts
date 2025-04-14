// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Deploy}    from "../Deploy.s.sol";
import {Params}    from "../../libraries/Params.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Script} from "forge-std/Script.sol";
import {DepositParams} from "../../src/Escrow.sol";
import {Escrow} from "../../src/Escrow.sol";
contract CreatePayments is Script {
    function run() public {
      MockERC20 mockUSDC = MockERC20(0x883066fabE2CC5b8f5dC626bF2eb47C6FBD4BE03);
      Escrow    escrow   = Escrow(0x18578b0168D940623b89Dd0Be880fF994305Fd7e);

      vm.startBroadcast();
      mockUSDC.mint(Params.SEPOLIA_TESTER_SHAFU, 100 * 10**6);

      DepositParams[] memory depositParams = new DepositParams[](1);
      depositParams[0] = DepositParams({
          token: mockUSDC,
          sender: Params.SEPOLIA_TESTER_SHAFU,
          recipient: Params.SEPOLIA_TESTER_JSON,
          amount: 100 * 10**6,
          claimPeriod: 10000
      });

      mockUSDC.approve(address(escrow), 100 * 10**6);
      escrow.batchDeposit(depositParams, 1, block.timestamp);

      vm.stopBroadcast();
    }
}
