// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Escrow} from "../src/Escrow.sol";

contract VerifySignature is Script {
    // Base Sepolia Escrow contract address
    address constant ESCROW_ADDRESS = 0x7F9675935585EbAAc9072FCd6589A4F7EED25A4b;
    
    function run() public {
        Escrow escrow = Escrow(ESCROW_ADDRESS);
        
        // Parameters from your script
        uint256 repoId = 1;
        uint256 instanceId = 1;
        address[] memory admins = new address[](1);
        admins[0] = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
        uint256 nonce = 0;
        uint256 signatureDeadline = 1750177809;
        
        // Get the values from contract
        bytes32 domainSeparator = escrow.DOMAIN_SEPARATOR();
        bytes32 setAdminTypehash = escrow.SET_ADMIN_TYPEHASH();
        
        console.log("=== Contract Values ===");
        console.log("DOMAIN_SEPARATOR:", vm.toString(domainSeparator));
        console.log("SET_ADMIN_TYPEHASH:", vm.toString(setAdminTypehash));
        
        // Calculate the hash that should be signed
        bytes32 adminsHash = keccak256(abi.encode(admins));
        console.log("admins hash:", vm.toString(adminsHash));
        
        bytes32 structHash = keccak256(abi.encode(
            setAdminTypehash,
            repoId,
            instanceId,
            adminsHash,
            nonce,
            signatureDeadline
        ));
        console.log("struct hash:", vm.toString(structHash));
        
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );
        
        console.log("=== Final Digest to Sign ===");
        console.log("digest:", vm.toString(digest));
        
        // Test with your signature
        uint8 v = 27;
        bytes32 r = 0x0d855e4a0b9786c4738b727cf23d9c0cc46e6537839a6117e914a8feeb30ad6c;
        bytes32 s = 0x49d8ae09a34fa47a25da618472bd2f55efe744a478e8a681e40be86683aebde3;
        
        address recovered = ecrecover(digest, v, r, s);
        address signer = escrow.signer();
        
        console.log("=== Signature Verification ===");
        console.log("Expected signer:", signer);
        console.log("Recovered address:", recovered);
        console.log("Signature valid:", recovered == signer);
        
        // Print breakdown for Rust debugging
        console.log("=== For Rust Implementation ===");
        console.log("Chain ID: 84532");
        console.log("Verifying Contract: 0x7F9675935585EbAAc9072FCd6589A4F7EED25A4b");
        console.log("Domain name: Escrow");
        console.log("Domain version: 1");
        console.log("repo_id:", repoId);
        console.log("instance_id:", instanceId);
        console.log("admin address:", admins[0]);
        console.log("nonce:", nonce);
        console.log("signature_deadline:", signatureDeadline);
    }
} 