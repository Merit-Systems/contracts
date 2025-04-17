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
    uint    constant REPO_ID            = 1234;

    function run() public {
      deploy(
        ESCROW_ADDRESS,
        TOKEN,
        NUMBER_OF_DEPOSITS,
        AMOUNT_PER_DEPOSIT,
        Params.SEPOLIA_TESTER_SHAFU,
        Params.SEPOLIA_TESTER_JSON
        );
    }

    function deploy(
        address escrowAddress,
        address token,
        uint256 numberOfDeposits,
        uint256 amountPerDeposit,
        address sender,
        address recipient
    ) public {
      MockERC20 mockUSDC = MockERC20(token);
      Escrow    escrow   = Escrow(escrowAddress);

      DepositParams[] memory depositParams = new DepositParams[](numberOfDeposits);
      
      for (uint256 i = 0; i < numberOfDeposits; i++) {
          depositParams[i] = DepositParams({
              token: mockUSDC,
              sender: sender,
              recipient: recipient,
              amount: amountPerDeposit,
              claimPeriod: 10000
          });
      }

      vm.startBroadcast();

      mockUSDC.mint(sender, amountPerDeposit * numberOfDeposits);
      mockUSDC.approve(address(escrow), amountPerDeposit * numberOfDeposits);
      escrow.batchDeposit(depositParams, abi.encode(REPO_ID, block.timestamp));

      vm.stopBroadcast();
        
    }
}
