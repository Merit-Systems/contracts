// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/console.sol";

import {Script} from "forge-std/Script.sol";
import {Escrow} from "../src/Escrow.sol";
import {Params} from "../libraries/Params.sol";

contract Deploy is Script {
    function deploy(
      address          owner,
      address          signer,
      address[] memory initialWhitelistedTokens,
      uint             feeBps,
      uint             batchDepositLimit
    )
      public
      returns (Escrow escrow)
    {
      // Get contract creation bytecode
      bytes memory bytecode = type(Escrow).creationCode;
      
      // Encode constructor arguments
      bytes memory args = abi.encode(
          owner,
          signer,
          initialWhitelistedTokens,
          feeBps,
          batchDepositLimit
      );
      
      // Calculate the init code hash
      bytes memory initCode = bytes.concat(bytecode, args);
      bytes32 initCodeHash = keccak256(initCode);
      console.log("Init code hash:");
      console.logBytes32(initCodeHash);

      vm.startBroadcast();

      escrow = new Escrow{salt: Params.SALT}(
          owner,
          signer,
          initialWhitelistedTokens,
          feeBps,
          batchDepositLimit
      );

      vm.stopBroadcast();
    }
}
