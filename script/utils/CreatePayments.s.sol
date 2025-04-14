// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Deploy}    from "../Deploy.s.sol";
import {Params}    from "../../libraries/Params.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Script} from "forge-std/Script.sol";
import {DepositParams} from "../../src/Escrow.sol";
import {Escrow} from "../../src/Escrow.sol";

contract CreatePayments is Script {
    // NOTE: You need to change these values before running this script
    uint    constant NUMBER_OF_DEPOSITS = 5;
    uint    constant AMOUNT_PER_DEPOSIT = 100 * 10**6;
    address constant ESCROW_ADDRESS     = 0x18578b0168D940623b89Dd0Be880fF994305Fd7e;
    address constant TOKEN              = 0x883066fabE2CC5b8f5dC626bF2eb47C6FBD4BE03;

    function run() public {
      MockERC20 mockUSDC = MockERC20(TOKEN);
      Escrow    escrow   = Escrow   (ESCROW_ADDRESS);

      DepositParams[] memory depositParams = new DepositParams[](NUMBER_OF_DEPOSITS);
      
      for (uint256 i = 0; i < NUMBER_OF_DEPOSITS; i++) {
          depositParams[i] = DepositParams({
              token: mockUSDC,
              sender: Params.SEPOLIA_TESTER_SHAFU,
              recipient: Params.SEPOLIA_TESTER_JSON,
              amount: AMOUNT_PER_DEPOSIT,
              claimPeriod: 10000
          });
      }

      vm.startBroadcast();

      mockUSDC.mint(Params.SEPOLIA_TESTER_SHAFU, AMOUNT_PER_DEPOSIT * NUMBER_OF_DEPOSITS);
      mockUSDC.approve(address(escrow), AMOUNT_PER_DEPOSIT * NUMBER_OF_DEPOSITS);
      escrow.batchDeposit(depositParams, NUMBER_OF_DEPOSITS, block.timestamp);

      vm.stopBroadcast();
    }
}
