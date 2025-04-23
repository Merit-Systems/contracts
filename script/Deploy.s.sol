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
        uint256          feeBps,
        uint256          batchDepositLimit
    )
        public
        returns (Escrow escrow)
    {
        /*--------------------------------------------------------------------*/
        /* 1. Build init-code                                                 */
        /*--------------------------------------------------------------------*/
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

        /*--------------------------------------------------------------------*/
        /* 2. Pick a salt (can be any deterministic value you like)           */
        /*--------------------------------------------------------------------*/
        bytes32 salt = keccak256(abi.encodePacked(Params.SALT));

        /*--------------------------------------------------------------------*/
        /* 3. (Optional) Pre-compute address so you can publish it up-front   */
        /*--------------------------------------------------------------------*/
        bytes32 initCodeHash = keccak256(bytecode);
        address predicted = Create2.computeAddress(salt, initCodeHash, address(this));
        console.log("Predicted Escrow address:", predicted);

        /*--------------------------------------------------------------------*/
        /* 4. Deploy via CREATE2                                              */
        /*--------------------------------------------------------------------*/
        vm.startBroadcast();
        address deployed = Create2.deploy(0, salt, bytecode);
        vm.stopBroadcast();

        /*--------------------------------------------------------------------*/
        /* 5. Cast to the Escrow type & return                                */
        /*--------------------------------------------------------------------*/
        escrow = Escrow(payable(deployed));
    }
}
