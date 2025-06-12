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
      uint             batchLimit
    )
      public
      returns (Escrow escrow)
    {
      /*//////////////////////////////////////////////////////////////
                            PRINT INIT CODE HASH
      //////////////////////////////////////////////////////////////*/
      bytes memory bytecode = type(Escrow).creationCode;
      bytes memory args     = abi.encode(
          owner,
          signer,
          initialWhitelistedTokens,
          feeBps,
          batchLimit
      );

      bytes   memory initCode     = bytes.concat(bytecode, args);
      bytes32        initCodeHash = keccak256(initCode);

      console.log("Init code hash:");
      console.logBytes32(initCodeHash);

      vm.startBroadcast();

      escrow = new Escrow{salt: Params.SALT}(
          owner,
          signer,
          initialWhitelistedTokens,
          feeBps,
          batchLimit
      );

      vm.stopBroadcast();
    }
}