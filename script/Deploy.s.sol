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

      bytes32 salt = keccak256(abi.encodePacked(Params.SALT));

      vm.startBroadcast();
      address deployed = Create2.deploy(0, salt, bytecode);
      vm.stopBroadcast();

      escrow = Escrow(payable(deployed));
    }
}
