// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Escrow} from "../src/Escrow.sol";

contract GenerateSignature is Script {
    // Base Sepolia Escrow contract address
    address constant ESCROW_ADDRESS = 0x7F9675935585EbAAc9072FCd6589A4F7EED25A4b;
    
    function run() public {
        Escrow escrow = Escrow(ESCROW_ADDRESS);
        
        // Private key from user
        uint256 signerPrivateKey = 0x4646464646464646464646464646464646464646464646464646464646464646;
        
        // Parameters
        uint256 repoId = 1;
        uint256 instanceId = 1;
        address[] memory admins = new address[](1);
        admins[0] = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
        uint256 nonce = 0;
        uint256 signatureDeadline = 1750177809;
        
        // Generate the digest
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    repoId,
                    instanceId,
                    keccak256(abi.encode(admins)),
                    nonce,
                    signatureDeadline
                ))
            )
        );
        
        console.log("Digest to sign:", vm.toString(digest));
        
        // Sign the digest
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        
        console.log("=== CORRECT SIGNATURE ===");
        console.log("signatureDeadline:", signatureDeadline);
        console.log("v:", v);
        console.log("r:", vm.toString(r));
        console.log("s:", vm.toString(s));
        
        // Verify the signature works
        address recovered = ecrecover(digest, v, r, s);
        address expectedSigner = escrow.signer();
        
        console.log("=== VERIFICATION ===");
        console.log("Expected signer:", expectedSigner);
        console.log("Recovered signer:", recovered);
        console.log("Signature valid:", recovered == expectedSigner);
    }
} 