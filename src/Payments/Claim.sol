// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {MerkleProof} from "lib/openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";

contract MerkleClaim {
    // The Merkle root set during deployment
    bytes32 public merkleRoot;

    // Track addresses that have already claimed
    mapping(address => bool) public hasClaimed;

    // Set the Merkle root upon deployment
    constructor(bytes32 _merkleRoot) {
        merkleRoot = _merkleRoot;
    }

    /**
     * @notice Claim function that accepts a Merkle proof.
     * @param _merkleProof An array of hashes that form the Merkle proof.
     */
    function claim(bytes32[] calldata _merkleProof) external {
        require(!hasClaimed[msg.sender], "Already claimed");

        // Compute the leaf node using the claimant's address
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));

        // Verify the provided proof against the stored Merkle root
        require(
            MerkleProof.verify(_merkleProof, merkleRoot, leaf),
            "Invalid Merkle proof"
        );

        // Mark the address as claimed
        hasClaimed[msg.sender] = true;

        // Execute further logic here:
        // e.g., transfer tokens, mint an NFT, etc.
    }
}
