// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Escrow} from "../src/Escrow.sol";

contract InitRepoBaseSepolia is Script {
    // Base Sepolia Escrow contract address
    address constant ESCROW_ADDRESS = 0x7F9675935585EbAAc9072FCd6589A4F7EED25A4b;

    function run() public {
        // Start broadcasting transactions
        vm.startBroadcast();

        // Get the Escrow contract instance
        Escrow escrow = Escrow(ESCROW_ADDRESS);

        // Parameters for initRepo
        uint256 repoId = 1;
        uint256 instanceId = 1;
        uint256 currentNonce = escrow.repoSetAdminNonce(repoId, instanceId);
        console.log("Current setAdminNonce:", currentNonce);
        address[] memory admins = new address[](1);
        admins[0] = 0x99ecA80b4Ebf8fDACe6627BEcb75EF1e620E6956;

        console.log("Parameters:");
        console.log("  repoId:", repoId);
        console.log("  instanceId:", instanceId);
        console.log("  admin:", admins[0]);
        console.log("  nonce:", currentNonce);

        // Domain info
        console.log("Domain info:");
        console.log("  DOMAIN_SEPARATOR:", vm.toString(escrow.DOMAIN_SEPARATOR()));
        console.log("  SET_ADMIN_TYPEHASH:", vm.toString(escrow.SET_ADMIN_TYPEHASH()));

        // Generate the digest that should be signed
        bytes32 adminHash = keccak256(abi.encode(admins));
        console.log("  admins hash:", vm.toString(adminHash));

        // Correct signature generated with the right private key
        uint    signatureDeadline = 1750183415;
        uint8   v = 28;
        bytes32 r = 0x3f31d04a29760b52e002b9b3acf139c2698b15d668ca22fa1a93d7123a290efe;
        bytes32 s = 0x14e2e6da4733d02fe6a628e3d73ac27702750d2413e99e1e17e420aa68895035;

        // Call initRepo
        escrow.initRepo(
            repoId,
            instanceId,
            admins,
            signatureDeadline,
            v,
            r,
            s
        );

        vm.stopBroadcast();
        
        console.log("initRepo called successfully on Base Sepolia");
    }
} 