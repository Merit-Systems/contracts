// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {Escrow} from "../src/Escrow.sol";
import {IEscrow} from "../interface/IEscrow.sol";

contract DeployAnvil is Script {
    
    // Test addresses for anvil
    address constant OWNER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; // anvil default account 0
    address constant SIGNER = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // anvil default account 1
    address constant USER1 = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC; // anvil default account 2
    address constant USER2 = 0x90F79bf6EB2c4f870365E785982E1f101E93b906; // anvil default account 3
    address constant RECIPIENT = 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65; // anvil default account 4
    
    uint constant FEE_BPS = 250; // 2.5%
    uint constant BATCH_LIMIT = 10;
    
    uint256 constant OWNER_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 constant SIGNER_PRIVATE_KEY = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    
    Escrow public escrow;
    MockERC20 public token1;
    MockERC20 public token2;
    
    function run() external {
        console.log("=== DEPLOYING ESCROW CONTRACT FOR ANVIL TESTING ===");
        
        vm.startBroadcast(OWNER_PRIVATE_KEY);
        
        // Deploy mock ERC20 tokens for testing
        token1 = new MockERC20("Test Token 1", "TKN1", 18);
        token2 = new MockERC20("Test Token 2", "TKN2", 6);
        
        console.log("Token1 deployed at:", address(token1));
        console.log("Token2 deployed at:", address(token2));
        
        // Prepare initial whitelisted tokens
        address[] memory initialTokens = new address[](2);
        initialTokens[0] = address(token1);
        initialTokens[1] = address(token2);
        
        // Deploy Escrow contract
        escrow = new Escrow(
            OWNER,
            SIGNER,
            initialTokens,
            FEE_BPS,
            BATCH_LIMIT
        );
        
        console.log("Escrow deployed at:", address(escrow));
        
        vm.stopBroadcast();
        
        // Now test all event-emitting functions
        testAllEventEmittingFunctions();
        
        console.log("=== DEPLOYMENT AND EVENT TESTING COMPLETE ===");
    }
    
    function testAllEventEmittingFunctions() internal {
        console.log("\n=== TESTING ALL EVENT-EMITTING FUNCTIONS ===");
        
        // Test owner functions first
        testOwnerFunctions();
        
        // Test repo initialization
        testRepoInitialization();
        
        // Test funding and distributions
        testFundingAndDistributions();
        
        // Test admin management
        testAdminManagement();
        
        // Test distributor management  
        testDistributorManagement();
        
        // Test claiming
        testClaiming();
        
        // Test reclaiming
        testReclaiming();
    }
    
    function testOwnerFunctions() internal {
        console.log("\n--- Testing Owner Functions ---");
        
        vm.startBroadcast(OWNER_PRIVATE_KEY);
        
        // Test WhitelistedToken event
        MockERC20 token3 = new MockERC20("Test Token 3", "TKN3", 18);
        escrow.whitelistToken(address(token3));
        console.log("WhitelistedToken event emitted for:", address(token3));
        
        // Test FeeSet event
        escrow.setFee(300); // 3%
        console.log("FeeSet event emitted: 250 -> 300");
        
        // Test FeeRecipientSet event
        escrow.setFeeRecipient(USER1);
        console.log("FeeRecipientSet event emitted:", OWNER, "->", USER1);
        
        // Test SignerSet event
        escrow.setSigner(USER2);
        console.log("SignerSet event emitted:", SIGNER, "->", USER2);
        
        // Test BatchLimitSet event
        escrow.setBatchLimit(20);
        console.log("BatchLimitSet event emitted: 20");
        
        // Reset signer for later use
        escrow.setSigner(SIGNER);
        
        vm.stopBroadcast();
    }
    
    function testRepoInitialization() internal {
        console.log("\n--- Testing Repo Initialization ---");
        
        uint repoId = 1;
        uint accountId = 1;
        address[] memory admins = new address[](2);
        admins[0] = USER1;
        admins[1] = USER2;
        
        // Create signature for initRepo
        uint ownerNonce = escrow.ownerNonce();
        uint signatureDeadline = block.timestamp + 3600;
        
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    repoId,
                    accountId,
                    keccak256(abi.encode(admins)),
                    ownerNonce,
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNER_PRIVATE_KEY, digest);
        
        vm.broadcast(USER1);
        escrow.initRepo(repoId, accountId, admins, signatureDeadline, v, r, s);
        console.log("InitializedRepo event emitted for repo:", repoId, "account:", accountId);
    }
    
    function testFundingAndDistributions() internal {
        console.log("\n--- Testing Funding and Distributions ---");
        
        uint repoId = 1;
        uint accountId = 1;
        uint amount = 1000e18;
        
        // Mint tokens and approve
        vm.startBroadcast(OWNER_PRIVATE_KEY);
        token1.mint(OWNER, amount * 2);
        token1.approve(address(escrow), amount * 2);
        vm.stopBroadcast();
        
        // Test FundedRepo event
        vm.broadcast(OWNER);
        escrow.fundRepo(repoId, accountId, token1, amount, "funding data");
        console.log("FundedRepo event emitted for amount:", amount);
        
        // Test DistributedFromRepo events
        vm.startBroadcast(USER1); // USER1 is an admin
        
        Escrow.DistributionParams[] memory repoDistributions = new Escrow.DistributionParams[](2);
        repoDistributions[0] = Escrow.DistributionParams({
            amount: 100e18,
            recipient: RECIPIENT,
            claimPeriod: 3600,
            token: token1
        });
        repoDistributions[1] = Escrow.DistributionParams({
            amount: 200e18,
            recipient: USER2,
            claimPeriod: 7200,
            token: token1
        });
        
        uint[] memory repoDistributionIds = escrow.distributeFromRepo(
            repoId, accountId, repoDistributions, "repo distribution data"
        );
        console.log("DistributedFromRepo events emitted for", repoDistributionIds.length, "distributions");
        
        vm.stopBroadcast();
        
        // Test DistributedFromSender events
        vm.startBroadcast(OWNER_PRIVATE_KEY);
        
        Escrow.DistributionParams[] memory senderDistributions = new Escrow.DistributionParams[](1);
        senderDistributions[0] = Escrow.DistributionParams({
            amount: 50e18,
            recipient: RECIPIENT,
            claimPeriod: 3600,
            token: token1
        });
        
        uint[] memory senderDistributionIds = escrow.distributeFromSender(
            senderDistributions, "sender distribution data"
        );
        console.log("DistributedFromSender events emitted for", senderDistributionIds.length, "distributions");
        
        vm.stopBroadcast();
    }
    
    function testAdminManagement() internal {
        console.log("\n--- Testing Admin Management ---");
        
        uint repoId = 1;
        uint accountId = 1;
        
        vm.startBroadcast(USER1); // USER1 is an admin
        
        // Test AddedAdmin event
        address[] memory newAdmins = new address[](1);
        newAdmins[0] = OWNER;
        escrow.addAdmins(repoId, accountId, newAdmins);
        console.log("AddedAdmin event emitted for:", OWNER);
        
        // Test RemovedAdmin event (remove USER2, keep USER1 and OWNER)
        address[] memory removeAdmins = new address[](1);
        removeAdmins[0] = USER2;
        escrow.removeAdmins(repoId, accountId, removeAdmins);
        console.log("RemovedAdmin event emitted for:", USER2);
        
        vm.stopBroadcast();
    }
    
    function testDistributorManagement() internal {
        console.log("\n--- Testing Distributor Management ---");
        
        uint repoId = 1;
        uint accountId = 1;
        
        vm.startBroadcast(USER1); // USER1 is an admin
        
        // Test AddedDistributor event
        address[] memory distributors = new address[](1);
        distributors[0] = USER2;
        escrow.addDistributors(repoId, accountId, distributors);
        console.log("AddedDistributor event emitted for:", USER2);
        
        // Test RemovedDistributor event
        address[] memory removeDistributors = new address[](1);
        removeDistributors[0] = USER2;
        escrow.removeDistributors(repoId, accountId, removeDistributors);
        console.log("RemovedDistributor event emitted for:", USER2);
        
        vm.stopBroadcast();
    }
    
    function testClaiming() internal {
        console.log("\n--- Testing Claiming ---");
        
        // Create a distribution that RECIPIENT can claim
        uint repoId = 1;
        uint accountId = 1;
        
        vm.startBroadcast(USER1); // USER1 is an admin
        
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: 100e18,
            recipient: RECIPIENT,
            claimPeriod: 3600,
            token: token1
        });
        
        uint[] memory distributionIds = escrow.distributeFromRepo(
            repoId, accountId, distributions, "claim test distribution"
        );
        
        vm.stopBroadcast();
        
        // Create claim signature
        uint recipientNonce = escrow.recipientNonce(RECIPIENT);
        uint signatureDeadline = block.timestamp + 3600;
        
        bytes32 claimDigest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.CLAIM_TYPEHASH(),
                    keccak256(abi.encode(distributionIds)),
                    RECIPIENT,
                    recipientNonce,
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PRIVATE_KEY, claimDigest);
        
        // Test Claimed events
        vm.broadcast(RECIPIENT);
        escrow.claim(distributionIds, signatureDeadline, v, r, s, "claim data");
        console.log("Claimed events emitted for", distributionIds.length, "distributions");
    }
    
    function testReclaiming() internal {
        console.log("\n--- Testing Reclaiming ---");
        
        uint repoId = 2; // Use new repo to avoid conflicts
        uint accountId = 1;
        
        // Initialize new repo
        address[] memory admins = new address[](1);
        admins[0] = USER1;
        
        uint ownerNonce = escrow.ownerNonce();
        uint signatureDeadline = block.timestamp + 3600;
        
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    repoId,
                    accountId,
                    keccak256(abi.encode(admins)),
                    ownerNonce,
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNER_PRIVATE_KEY, digest);
        
        vm.broadcast(USER1);
        escrow.initRepo(repoId, accountId, admins, signatureDeadline, v, r, s);
        
        // Fund the repo for reclaim testing
        vm.startBroadcast(OWNER_PRIVATE_KEY);
        token1.mint(OWNER, 1000e18);
        token1.approve(address(escrow), 1000e18);
        vm.stopBroadcast();
        
        vm.broadcast(OWNER);
        escrow.fundRepo(repoId, accountId, token1, 500e18, "reclaim test funding");
        
        // Test ReclaimedRepoFunds event (only works if no distributions made)
        vm.broadcast(USER1);
        escrow.reclaimRepoFunds(repoId, accountId, address(token1), 100e18);
        console.log("ReclaimedRepoFunds event emitted");
        
        // Create distributions that will expire for reclaim testing
        vm.startBroadcast(USER1);
        
        Escrow.DistributionParams[] memory expiredDistributions = new Escrow.DistributionParams[](1);
        expiredDistributions[0] = Escrow.DistributionParams({
            amount: 100e18,
            recipient: RECIPIENT,
            claimPeriod: 0, // Instant reclaimability
            token: token1
        });
        
        uint[] memory expiredRepoIds = escrow.distributeFromRepo(
            repoId, accountId, expiredDistributions, "expired distribution"
        );
        
        vm.stopBroadcast();
        
        // Create sender distribution that will expire
        vm.startBroadcast(OWNER_PRIVATE_KEY);
        
        Escrow.DistributionParams[] memory expiredSenderDist = new Escrow.DistributionParams[](1);
        expiredSenderDist[0] = Escrow.DistributionParams({
            amount: 50e18,
            recipient: RECIPIENT,
            claimPeriod: 0, // Instant reclaimability
            token: token1
        });
        
        uint[] memory expiredSenderIds = escrow.distributeFromSender(expiredSenderDist, "expired sender dist");
        
        vm.stopBroadcast();
        
        // Since claimPeriod is 0, distributions are immediately reclaimable in the next block
        
        // Test ReclaimedRepoDistribution events
        vm.broadcast(USER1);
        escrow.reclaimRepoDistributions(repoId, accountId, expiredRepoIds, "reclaim repo data");
        console.log("ReclaimedRepoDistribution events emitted");
        
        // Test ReclaimedSenderDistribution events
        vm.broadcast(OWNER);
        escrow.reclaimSenderDistributions(expiredSenderIds, "reclaim sender data");
        console.log("ReclaimedSenderDistribution events emitted");
    }
} 