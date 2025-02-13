// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "forge-std/Test.sol";

import {Errors}      from "libraries/Errors.sol";
import {Params}      from "libraries/Params.sol";
import {Base_Test}   from "./Base.t.sol";

contract Claim_Test is Base_Test {
    function test_claim() 
        public 
        _init
    {
        uint repoId = 0;
        usdc.mint(address(ledger), 100e18);
        (bytes32 merkleRoot, bytes32[] memory proof) = getSingleLeafRootAndProof(0, alice, 100e18);

        vm.startPrank(alice);
        vm.warp(block.timestamp + 365 days);

        ledger.setMerkleRoot(repoId, merkleRoot, true);
        ledger.claim(repoId, 0, alice, 100e18, proof, merkleRoot);
    }

    function test_claim_fail_notAccountOwner() 
        public 
        _init
    {
        uint repoId = 0;
        (bytes32 merkleRoot, bytes32[] memory proof) = getSingleLeafRootAndProof(0, alice, 100e18);

        vm.startPrank(alice);

        ledger.setMerkleRoot(repoId, merkleRoot, true);

        expectRevert(Errors.NOT_ACCOUNT_OWNER);
        ledger.claim(repoId, 0, bob, 100e18, proof, merkleRoot);
    }

    function test_claim_fail_invalidRoot() 
        public 
        _init
    {
        uint repoId = 0;
        (bytes32 merkleRoot, bytes32[] memory proof) = getSingleLeafRootAndProof(0, alice, 100e18);

        vm.startPrank(alice);

        expectRevert(Errors.INVALID_ROOT);
        ledger.claim(repoId, 0, alice, 100e18, proof, merkleRoot);
    }

    function test_claim_fail_alreadyClaimed() 
        public 
        _init
    {
        uint repoId = 0;
        usdc.mint(address(ledger), 100e18);
        (bytes32 merkleRoot, bytes32[] memory proof) = getSingleLeafRootAndProof(0, alice, 100e18);

        vm.startPrank(alice);

        ledger.setMerkleRoot(repoId, merkleRoot, true);
        ledger.claim(repoId, 0, alice, 100e18, proof, merkleRoot);

        expectRevert(Errors.ALREADY_CLAIMED);
        ledger.claim(repoId, 0, alice, 100e18, proof, merkleRoot);
    }
}