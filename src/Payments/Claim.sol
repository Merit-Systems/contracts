// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {MerkleProof} from "lib/openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract MerkleClaim is Ownable(msg.sender) {
    bytes32 public merkleRoot;
    IERC20 public usdcToken;
    uint256 public perClaimAmount;
    mapping(address => bool) public hasClaimed;

    event MerkleRootUpdated(bytes32 newMerkleRoot, uint256 fundsDeposited, uint256 perClaimAmount);

    constructor(bytes32 _merkleRoot, address _usdcToken) {
        merkleRoot = _merkleRoot;
        usdcToken = IERC20(_usdcToken);
    }

    function claim(bytes32[] calldata _merkleProof) external {
        require(!hasClaimed[msg.sender], "Already claimed");

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));

        require(MerkleProof.verify(_merkleProof, merkleRoot, leaf), "Invalid Merkle proof");

        hasClaimed[msg.sender] = true;

        require(usdcToken.balanceOf(address(this)) >= perClaimAmount, "Insufficient USDC in contract");

        require(usdcToken.transfer(msg.sender, perClaimAmount), "USDC transfer failed");
    }

    function setMerkleRoot(bytes32 _newMerkleRoot, uint256 _perClaimAmount, uint256 _amount) external onlyOwner {
        require(usdcToken.transferFrom(msg.sender, address(this), _amount), "USDC transfer failed");

        merkleRoot = _newMerkleRoot;
        perClaimAmount = _perClaimAmount;

        emit MerkleRootUpdated(_newMerkleRoot, _amount, _perClaimAmount);
    }
}