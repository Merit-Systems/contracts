// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/console.sol";

import {Script}   from "forge-std/Script.sol";
import {Create2}  from "@openzeppelin/contracts/utils/Create2.sol";
import {Escrow}   from "../src/Escrow.sol";
import {Params}   from "../libraries/Params.sol";

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
      bytes memory bytecode = abi.encodePacked(
          type(Escrow).creationCode,
          abi.encode(
              owner,
              signer,
              initialWhitelistedTokens,
              feeBps,
              batchDepositLimit
          )
      );

      vm.startBroadcast();

      // Get the actual deployer address
      address deployer = msg.sender;
      bytes32 initCodeHash = keccak256(bytecode);
      
      console.log("Deployer address:", deployer);
      console.logBytes32(Params.SALT);
      console.logBytes32(initCodeHash);
      
      address predicted = Create2.computeAddress(Params.SALT, initCodeHash, deployer);
      console.log("Predicted Escrow address:", predicted);

      address deployed = Create2.deploy(0, Params.SALT, bytecode);
      
      console.log("Deployed address:", deployed);
      
      vm.stopBroadcast();

      escrow = Escrow(payable(deployed));
    }
}
