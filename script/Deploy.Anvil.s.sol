// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {console} from "forge-std/console.sol";

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
        vm.startBroadcast(OWNER_PRIVATE_KEY);
        
        // Deploy mock ERC20 tokens for testing
        token1 = new MockERC20("Test Token 1", "TKN1", 18);
        token2 = new MockERC20("Test Token 2", "TKN2", 6);
        
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

        console.log("--------------------------------");
        console.log("Escrow deployed at", address(escrow));
        console.log("--------------------------------");
        
        vm.stopBroadcast();
        
        // Now test all event-emitting functions
        testAllEventEmittingFunctions();

        // Test additional scenarios for more events
        testAdditionalEventScenarios();
    }
    
    function testAllEventEmittingFunctions() internal {
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
        vm.startBroadcast(OWNER_PRIVATE_KEY);
        
        // Test WhitelistedToken event
        MockERC20 token3 = new MockERC20("Test Token 3", "TKN3", 18);
        escrow.whitelistToken(address(token3));
        
        // Test FeeOnClaimSet event
        escrow.setFeeOnClaim(300); // 3%
        
        // Test FeeOnFundSet event
        escrow.setFeeOnFund(100); // 1%
        
        // Test FeeRecipientSet event
        escrow.setFeeRecipient(USER1);
        
        // Test SignerSet event
        escrow.setSigner(USER2);
        
        // Test BatchLimitSet event
        escrow.setBatchLimit(20);
        
        // Reset signer for later use
        escrow.setSigner(SIGNER);
        
        vm.stopBroadcast();
    }
    
    function testRepoInitialization() internal {
        uint repoId = 1;
        uint accountId = 1;
        address[] memory admins = new address[](2);
        admins[0] = USER1;
        admins[1] = USER2;
        
        // Create signature for initRepo
        uint setAdminNonce = escrow.repoSetAdminNonce(repoId, accountId);
        uint signatureDeadline = block.timestamp + 7200; // Increased buffer to prevent expiration
        
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    repoId,
                    accountId,
                    keccak256(abi.encode(admins)),
                    setAdminNonce,
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PRIVATE_KEY, digest);
        
        vm.broadcast(admins[0]);
        escrow.initRepo(repoId, accountId, admins, signatureDeadline, v, r, s);
        // Add the first admin as distributor for this repo
        address[] memory distributors = new address[](1);
        distributors[0] = admins[0];
        vm.broadcast(admins[0]);
        escrow.addDistributors(repoId, accountId, distributors);
    }
    
    function testFundingAndDistributions() internal {
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
        
        vm.stopBroadcast();
    }
    
    function testAdminManagement() internal {
        uint repoId = 1;
        uint accountId = 1;
        
        vm.startBroadcast(USER1); // USER1 is an admin
        
        // Test AddedAdmin event
        address[] memory newAdmins = new address[](1);
        newAdmins[0] = OWNER;
        escrow.addAdmins(repoId, accountId, newAdmins);
        
        // Test RemovedAdmin event (remove USER2, keep USER1 and OWNER)
        address[] memory removeAdmins = new address[](1);
        removeAdmins[0] = USER2;
        escrow.removeAdmins(repoId, accountId, removeAdmins);
        
        vm.stopBroadcast();
    }
    
    function testDistributorManagement() internal {
        uint repoId = 1;
        uint accountId = 1;
        
        vm.startBroadcast(USER1); // USER1 is an admin
        
        // Test AddedDistributor event
        address[] memory distributors = new address[](1);
        distributors[0] = USER2;
        escrow.addDistributors(repoId, accountId, distributors);
        
        // Test RemovedDistributor event
        address[] memory removeDistributors = new address[](1);
        removeDistributors[0] = USER2;
        escrow.removeDistributors(repoId, accountId, removeDistributors);
        
        vm.stopBroadcast();
    }
    
    function testClaiming() internal {
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
        uint recipientClaimNonce = escrow.recipientClaimNonce(RECIPIENT);
        uint signatureDeadline = block.timestamp + 3600;
        
        bytes32 claimDigest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.CLAIM_TYPEHASH(),
                    keccak256(abi.encode(distributionIds)),
                    RECIPIENT,
                    recipientClaimNonce,
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PRIVATE_KEY, claimDigest);
        
        // Test Claimed events
        vm.broadcast(RECIPIENT);
        escrow.claim(distributionIds, signatureDeadline, v, r, s, "claim data");
    }
    
    function testReclaiming() internal {
        uint repoId = 2; // Use new repo to avoid conflicts
        uint accountId = 1;
        
        // Initialize new repo
        address[] memory admins = new address[](1);
        admins[0] = USER1;
        
        uint setAdminNonce = escrow.repoSetAdminNonce(repoId, accountId);
        uint signatureDeadline = block.timestamp + 7200; // Increased buffer to 2 hours
        
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    repoId,
                    accountId,
                    keccak256(abi.encode(admins)),
                    setAdminNonce,
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PRIVATE_KEY, digest);
        
        vm.broadcast(USER1);
        escrow.initRepo(repoId, accountId, admins, signatureDeadline, v, r, s);
        // Add USER1 as distributor for repo 2
        address[] memory distributors = new address[](1);
        distributors[0] = USER1;
        vm.broadcast(USER1);
        escrow.addDistributors(repoId, accountId, distributors);
        
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
        
        // Test ReclaimedSenderDistribution events
        vm.broadcast(OWNER);
        escrow.reclaimSenderDistributions(expiredSenderIds, "reclaim sender data");
    }
    
    function testAdditionalEventScenarios() internal {
        // Test multiple token whitelisting
        testMultipleTokenWhitelisting();
        
        // Test multiple repo scenarios
        testMultipleRepoScenarios();
        
        // Test edge case distributions
        testEdgeCaseDistributions();
        
        // Test batch operations
        testBatchOperations();
        
        // Test admin management edge cases
        testAdminManagementEdgeCases();
        
        // Test fee scenarios
        testFeeScenarios();
        
        // Test timing scenarios
        testTimingScenarios();
        
        // Test stress scenarios
        testStressScenarios();
        
        // Test multi-token scenarios  
        testMultiTokenScenarios();
        
        // Test configuration changes
        testConfigurationChanges();
        
        // Test comprehensive claim scenarios
        testComprehensiveClaimScenarios();
        
        // Test comprehensive reclaim scenarios  
        testComprehensiveReclaimScenarios();
    }
    
    function testComprehensiveClaimScenarios() internal {
        // Test various claim scenarios with different tokens, batch sizes, and timings
        uint repoId = 50;
        uint accountId = 1;
        
        // Initialize repo 50
        address[] memory admins = new address[](1);
        admins[0] = USER1;
        
        uint setAdminNonce = escrow.repoSetAdminNonce(repoId, accountId);
        uint signatureDeadline = block.timestamp + 7200; // Increased buffer to prevent expiration
        
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    repoId,
                    accountId,
                    keccak256(abi.encode(admins)),
                    setAdminNonce,
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PRIVATE_KEY, digest);
        
        vm.broadcast(USER1);
        escrow.initRepo(repoId, accountId, admins, signatureDeadline, v, r, s);
        
        // Add USER1 as distributor
        address[] memory distributors = new address[](1);
        distributors[0] = USER1;
        vm.broadcast(USER1);
        escrow.addDistributors(repoId, accountId, distributors);
        
        // Fund repo with both tokens
        vm.startBroadcast(OWNER_PRIVATE_KEY);
        token1.mint(OWNER, 10000e18);
        token2.mint(OWNER, 10000e6);
        token1.approve(address(escrow), 10000e18);
        token2.approve(address(escrow), 10000e6);
        vm.stopBroadcast();
        
        vm.broadcast(OWNER);
        escrow.fundRepo(repoId, accountId, token1, 5000e18, "funding for comprehensive claims");
        vm.broadcast(OWNER);
        escrow.fundRepo(repoId, accountId, token2, 5000e6, "funding for comprehensive claims");
        
        // Test 1: Single token single distribution claim
        vm.startBroadcast(USER1);
        Escrow.DistributionParams[] memory singleDist = new Escrow.DistributionParams[](1);
        singleDist[0] = Escrow.DistributionParams({
            amount: 100e18,
            recipient: RECIPIENT, 
            claimPeriod: 3600,
            token: token1
        });
        uint[] memory singleDistIds = escrow.distributeFromRepo(repoId, accountId, singleDist, "single claim test");
        vm.stopBroadcast();
        
        // Create claim signature for single distribution
        uint recipientNonce1 = escrow.recipientClaimNonce(RECIPIENT);
        uint claimDeadline1 = block.timestamp + 3600;
        bytes32 claimDigest1 = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.CLAIM_TYPEHASH(),
                    keccak256(abi.encode(singleDistIds)),
                    RECIPIENT,
                    recipientNonce1,
                    claimDeadline1
                ))
            )
        );
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(SIGNER_PRIVATE_KEY, claimDigest1);
        
        vm.broadcast(RECIPIENT);
        escrow.claim(singleDistIds, claimDeadline1, v1, r1, s1, "single distribution claim");
        
        // Test 2: Multi-token batch claim
        vm.startBroadcast(USER1);
        Escrow.DistributionParams[] memory multiTokenDist = new Escrow.DistributionParams[](6);
        for (uint i = 0; i < 3; i++) {
            multiTokenDist[i * 2] = Escrow.DistributionParams({
                amount: 200e18,
                recipient: USER2,
                claimPeriod: 3600,
                token: token1
            });
            multiTokenDist[i * 2 + 1] = Escrow.DistributionParams({
                amount: 200e6,
                recipient: USER2,
                claimPeriod: 3600,
                token: token2
            });
        }
        uint[] memory multiTokenIds = escrow.distributeFromRepo(repoId, accountId, multiTokenDist, "multi-token batch");
        vm.stopBroadcast();
        
        // Claim multi-token batch
        uint recipientNonce2 = escrow.recipientClaimNonce(USER2);
        uint claimDeadline2 = block.timestamp + 3600;
        bytes32 claimDigest2 = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.CLAIM_TYPEHASH(),
                    keccak256(abi.encode(multiTokenIds)),
                    USER2,
                    recipientNonce2,
                    claimDeadline2
                ))
            )
        );
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(SIGNER_PRIVATE_KEY, claimDigest2);
        
        vm.broadcast(USER2);
        escrow.claim(multiTokenIds, claimDeadline2, v2, r2, s2, "multi-token batch claim");
        
        // Test 3: Mixed repo + sender distribution claims
        // Create sender distributions
        vm.startBroadcast(OWNER_PRIVATE_KEY);
        token1.mint(OWNER, 1000e18);
        token2.mint(OWNER, 1000e6);
        token1.approve(address(escrow), 1000e18);
        token2.approve(address(escrow), 1000e6);
        
        Escrow.DistributionParams[] memory senderDist = new Escrow.DistributionParams[](4);
        senderDist[0] = Escrow.DistributionParams({
            amount: 150e18,
            recipient: OWNER,
            claimPeriod: 3600,
            token: token1
        });
        senderDist[1] = Escrow.DistributionParams({
            amount: 150e6,
            recipient: OWNER,
            claimPeriod: 3600,
            token: token2
        });
        senderDist[2] = Escrow.DistributionParams({
            amount: 250e18,
            recipient: OWNER,
            claimPeriod: 7200,
            token: token1
        });
        senderDist[3] = Escrow.DistributionParams({
            amount: 250e6,
            recipient: OWNER,
            claimPeriod: 7200,
            token: token2
        });
        
        uint[] memory senderDistIds = escrow.distributeFromSender(senderDist, "sender distributions for claiming");
        vm.stopBroadcast();
        
        // Claim sender distributions
        uint recipientNonce3 = escrow.recipientClaimNonce(OWNER);
        uint claimDeadline3 = block.timestamp + 3600;
        bytes32 claimDigest3 = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.CLAIM_TYPEHASH(),
                    keccak256(abi.encode(senderDistIds)),
                    OWNER,
                    recipientNonce3,
                    claimDeadline3
                ))
            )
        );
        (uint8 v3, bytes32 r3, bytes32 s3) = vm.sign(SIGNER_PRIVATE_KEY, claimDigest3);
        
        vm.broadcast(OWNER);
        escrow.claim(senderDistIds, claimDeadline3, v3, r3, s3, "sender distributions claim");
        
        // Test 4: Sequential individual claims
        vm.startBroadcast(USER1);
        Escrow.DistributionParams[] memory sequentialDist = new Escrow.DistributionParams[](5);
        for (uint i = 0; i < 5; i++) {
            sequentialDist[i] = Escrow.DistributionParams({
                amount: 80e18,
                recipient: address(uint160(0xF001 + i)),
                claimPeriod: 3600,
                token: token1
            });
        }
        uint[] memory sequentialIds = escrow.distributeFromRepo(repoId, accountId, sequentialDist, "sequential claims test");
        vm.stopBroadcast();
        
        // Claim each distribution individually  
        for (uint i = 0; i < sequentialIds.length; i++) {
            address recipient = address(uint160(0xF001 + i));
            uint[] memory singleId = new uint[](1);
            singleId[0] = sequentialIds[i];
            
            uint recipientNonce = escrow.recipientClaimNonce(recipient);
            uint claimDeadline = block.timestamp + 3600;
            bytes32 claimDigest = keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    escrow.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(
                        escrow.CLAIM_TYPEHASH(),
                        keccak256(abi.encode(singleId)),
                        recipient,
                        recipientNonce,
                        claimDeadline
                    ))
                )
            );
            (uint8 v4, bytes32 r4, bytes32 s4) = vm.sign(SIGNER_PRIVATE_KEY, claimDigest);
            
            vm.broadcast(recipient);
            escrow.claim(singleId, claimDeadline, v4, r4, s4, bytes(abi.encodePacked("sequential claim ", i)));
        }
    }
    
    function testComprehensiveReclaimScenarios() internal {
        // Test various reclaim scenarios
        uint repoId = 60;
        uint accountId = 1;
        
        // Initialize repo 60
        address[] memory admins = new address[](1);
        admins[0] = USER2;
        
        uint setAdminNonce = escrow.repoSetAdminNonce(repoId, accountId);
        uint signatureDeadline = block.timestamp + 7200; // Increased buffer to prevent expiration
        
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    repoId,
                    accountId,
                    keccak256(abi.encode(admins)),
                    setAdminNonce,
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PRIVATE_KEY, digest);
        
        vm.broadcast(USER2);
        escrow.initRepo(repoId, accountId, admins, signatureDeadline, v, r, s);
        
        // Add USER2 as distributor
        address[] memory distributors = new address[](1);
        distributors[0] = USER2;
        vm.broadcast(USER2);
        escrow.addDistributors(repoId, accountId, distributors);
        
        // Test 1: Reclaim unused repo funds (before any distributions)
        vm.startBroadcast(OWNER_PRIVATE_KEY);
        token1.mint(OWNER, 2000e18);
        token2.mint(OWNER, 2000e6);
        token1.approve(address(escrow), 2000e18);
        token2.approve(address(escrow), 2000e6);
        vm.stopBroadcast();
        
        vm.broadcast(OWNER);
        escrow.fundRepo(repoId, accountId, token1, 1000e18, "funding for reclaim tests");
        vm.broadcast(OWNER);
        escrow.fundRepo(repoId, accountId, token2, 1000e6, "funding for reclaim tests");
        
        // Reclaim partial funds before distributions
        vm.broadcast(USER2);
        escrow.reclaimRepoFunds(repoId, accountId, address(token1), 200e18);
        vm.broadcast(USER2);
        escrow.reclaimRepoFunds(repoId, accountId, address(token2), 200e6);
        
        // Test 2: Create distributions with immediate expiry for reclaim testing
        vm.startBroadcast(USER2);
        
        Escrow.DistributionParams[] memory immediateExpiry = new Escrow.DistributionParams[](8);
        for (uint i = 0; i < 4; i++) {
            immediateExpiry[i * 2] = Escrow.DistributionParams({
                amount: 50e18,
                recipient: address(uint160(0xF100 + i)),
                claimPeriod: 0, // Immediate expiry
                token: token1
            });
            immediateExpiry[i * 2 + 1] = Escrow.DistributionParams({
                amount: 50e6,
                recipient: address(uint160(0xF100 + i)),
                claimPeriod: 0, // Immediate expiry
                token: token2
            });
        }
        
        uint[] memory immediateExpiryIds = escrow.distributeFromRepo(repoId, accountId, immediateExpiry, "immediate expiry for reclaim");
        vm.stopBroadcast();
        
        // Reclaim immediately expired distributions
        vm.broadcast(USER2);
        escrow.reclaimRepoDistributions(repoId, accountId, immediateExpiryIds, "reclaiming immediate expiry batch");
        
        // Test 3: Mixed timing reclaim scenarios
        vm.startBroadcast(USER2);
        
        Escrow.DistributionParams[] memory mixedTiming = new Escrow.DistributionParams[](6);
        mixedTiming[0] = Escrow.DistributionParams({
            amount: 75e18,
            recipient: address(0xF200),
            claimPeriod: 0, // Immediate
            token: token1
        });
        mixedTiming[1] = Escrow.DistributionParams({
            amount: 75e6,
            recipient: address(0xF201),
            claimPeriod: 0, // Immediate
            token: token2
        });
        mixedTiming[2] = Escrow.DistributionParams({
            amount: 100e18,
            recipient: address(0xF202),
            claimPeriod: 0, // Immediate
            token: token1
        });
        mixedTiming[3] = Escrow.DistributionParams({
            amount: 100e6,
            recipient: address(0xF203),
            claimPeriod: 0, // Immediate
            token: token2
        });
        mixedTiming[4] = Escrow.DistributionParams({
            amount: 125e18,
            recipient: address(0xF204),
            claimPeriod: 0, // Immediate
            token: token1
        });
        mixedTiming[5] = Escrow.DistributionParams({
            amount: 125e6,
            recipient: address(0xF205),
            claimPeriod: 0, // Immediate
            token: token2
        });
        
        uint[] memory mixedTimingIds = escrow.distributeFromRepo(repoId, accountId, mixedTiming, "mixed timing distributions");
        vm.stopBroadcast();
        
        // Reclaim subset of expired distributions
        uint[] memory subsetIds = new uint[](3);
        subsetIds[0] = mixedTimingIds[0];
        subsetIds[1] = mixedTimingIds[2];
        subsetIds[2] = mixedTimingIds[4];
        
        vm.broadcast(USER2);
        escrow.reclaimRepoDistributions(repoId, accountId, subsetIds, "reclaiming subset");
        
        // Reclaim remaining expired distributions
        uint[] memory remainingIds = new uint[](3);
        remainingIds[0] = mixedTimingIds[1];
        remainingIds[1] = mixedTimingIds[3];
        remainingIds[2] = mixedTimingIds[5];
        
        vm.broadcast(USER2);
        escrow.reclaimRepoDistributions(repoId, accountId, remainingIds, "reclaiming remaining");
        
        // Test 4: Sender distribution reclaim scenarios
        vm.startBroadcast(OWNER_PRIVATE_KEY);
        token1.mint(OWNER, 2000e18);
        token2.mint(OWNER, 2000e6);
        token1.approve(address(escrow), 2000e18);
        token2.approve(address(escrow), 2000e6);
        
        // Create sender distributions with immediate expiry
        Escrow.DistributionParams[] memory senderReclaim = new Escrow.DistributionParams[](10);
        for (uint i = 0; i < 5; i++) {
            senderReclaim[i * 2] = Escrow.DistributionParams({
                amount: 80e18,
                recipient: address(uint160(0xF300 + i)),
                claimPeriod: 0, // Immediate expiry
                token: token1
            });
            senderReclaim[i * 2 + 1] = Escrow.DistributionParams({
                amount: 80e6,
                recipient: address(uint160(0xF300 + i)),
                claimPeriod: 0, // Immediate expiry
                token: token2
            });
        }
        
        uint[] memory senderReclaimIds = escrow.distributeFromSender(senderReclaim, "sender distributions for reclaim");
        vm.stopBroadcast();
        
        // Reclaim sender distributions in batches
        uint[] memory senderBatch1 = new uint[](4);
        for (uint i = 0; i < 4; i++) {
            senderBatch1[i] = senderReclaimIds[i];
        }
        
        vm.broadcast(OWNER);
        escrow.reclaimSenderDistributions(senderBatch1, "sender reclaim batch 1");
        
        uint[] memory senderBatch2 = new uint[](6);
        for (uint i = 0; i < 6; i++) {
            senderBatch2[i] = senderReclaimIds[i + 4];
        }
        
        vm.broadcast(OWNER);
        escrow.reclaimSenderDistributions(senderBatch2, "sender reclaim batch 2");
        
        // Test 5: Individual sender distribution reclaims
        vm.startBroadcast(OWNER_PRIVATE_KEY);
        
        Escrow.DistributionParams[] memory individualReclaim = new Escrow.DistributionParams[](5);
        for (uint i = 0; i < 5; i++) {
            individualReclaim[i] = Escrow.DistributionParams({
                amount: 60e18,
                recipient: address(uint160(0xF400 + i)),
                claimPeriod: 0, // Immediate expiry
                token: token1
            });
        }
        
        uint[] memory individualReclaimIds = escrow.distributeFromSender(individualReclaim, "individual reclaim test");
        vm.stopBroadcast();
        
        // Reclaim each distribution individually
        for (uint i = 0; i < individualReclaimIds.length; i++) {
            uint[] memory singleReclaimId = new uint[](1);
            singleReclaimId[0] = individualReclaimIds[i];
            
            vm.broadcast(OWNER);
            escrow.reclaimSenderDistributions(singleReclaimId, bytes(abi.encodePacked("individual reclaim ", i)));
        }
    }
    
    function testMultipleTokenWhitelisting() internal {
        vm.startBroadcast(OWNER_PRIVATE_KEY);
        
        // Create and whitelist multiple tokens
        for (uint i = 3; i <= 7; i++) {
            MockERC20 newToken = new MockERC20(
                string(abi.encodePacked("Test Token ", i)), 
                string(abi.encodePacked("TKN", i)),
                18
            );
            escrow.whitelistToken(address(newToken));
        }
        
        vm.stopBroadcast();
    }
    
    function testMultipleRepoScenarios() internal {
        // Initialize repos 10-15 with different admin configurations
        for (uint repoId = 10; repoId <= 15; repoId++) {
            uint accountId = 1;
            
            // Different admin configurations for each repo
            address[] memory admins = new address[](repoId % 3 + 1);
            if (repoId % 3 == 0) {
                admins[0] = USER1;
            } else if (repoId % 3 == 1) {
                admins[0] = USER2;
                if (admins.length > 1) admins[1] = RECIPIENT;
            } else {
                admins[0] = USER1;
                if (admins.length > 1) admins[1] = USER2;
                if (admins.length > 2) admins[2] = RECIPIENT;
            }
            
            uint setAdminNonce = escrow.repoSetAdminNonce(repoId, accountId);
            uint signatureDeadline = block.timestamp + 7200; // Increased buffer to prevent expiration
            
            bytes32 digest = keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    escrow.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(
                        escrow.SET_ADMIN_TYPEHASH(),
                        repoId,
                        accountId,
                        keccak256(abi.encode(admins)),
                        setAdminNonce,
                        signatureDeadline
                    ))
                )
            );
            
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PRIVATE_KEY, digest);
            
            vm.broadcast(admins[0]);
            escrow.initRepo(repoId, accountId, admins, signatureDeadline, v, r, s);
            // Add the first admin as distributor for this repo
            address[] memory distributors = new address[](1);
            distributors[0] = admins[0];
            vm.broadcast(admins[0]);
            escrow.addDistributors(repoId, accountId, distributors);
        }
    }
    
    function testEdgeCaseDistributions() internal {
        uint repoId = 10;
        uint accountId = 1;
        uint amount = 1000e18;
        
        // Fund repo for edge case testing
        vm.startBroadcast(OWNER_PRIVATE_KEY);
        token1.mint(OWNER, amount * 10);
        token1.approve(address(escrow), amount * 10);
        vm.stopBroadcast();
        
        vm.broadcast(OWNER);
        escrow.fundRepo(repoId, accountId, token1, amount * 5, "bulk funding for edge cases");
        // Add USER2 as distributor for repo 10 (USER2 is an admin for repo 10)
        address[] memory distributors = new address[](1);
        distributors[0] = USER2;
        vm.broadcast(USER2);
        escrow.addDistributors(repoId, accountId, distributors);
        
        // Test small amount distributions
        vm.startBroadcast(USER2); // USER2 is now the distributor
        
        Escrow.DistributionParams[] memory smallDistributions = new Escrow.DistributionParams[](3);
        smallDistributions[0] = Escrow.DistributionParams({
            amount: 1e18, // 1 token
            recipient: RECIPIENT,
            claimPeriod: 3600,
            token: token1
        });
        smallDistributions[1] = Escrow.DistributionParams({
            amount: 1e15, // 0.001 token
            recipient: USER2,
            claimPeriod: 7200,
            token: token1
        });
        smallDistributions[2] = Escrow.DistributionParams({
            amount: 5e17, // 0.5 token
            recipient: OWNER,
            claimPeriod: 1800,
            token: token1
        });
        
        uint[] memory smallDistIds = escrow.distributeFromRepo(
            repoId, accountId, smallDistributions, "small amount distributions"
        );
        
        // Test large amount distributions
        Escrow.DistributionParams[] memory largeDistributions = new Escrow.DistributionParams[](2);
        largeDistributions[0] = Escrow.DistributionParams({
            amount: 500e18, // 500 tokens
            recipient: RECIPIENT,
            claimPeriod: 86400, // 1 day
            token: token1
        });
        largeDistributions[1] = Escrow.DistributionParams({
            amount: 300e18, // 300 tokens
            recipient: USER2,
            claimPeriod: 172800, // 2 days
            token: token1
        });
        
        uint[] memory largeDistIds = escrow.distributeFromRepo(
            repoId, accountId, largeDistributions, "large amount distributions"
        );
        
        vm.stopBroadcast();
    }
    
    function testBatchOperations() internal {
        uint repoId = 11;
        uint accountId = 1;
        uint amount = 2000e18;
        
        // Fund repo for batch testing
        vm.startBroadcast(OWNER_PRIVATE_KEY);
        token1.mint(OWNER, amount);
        token1.approve(address(escrow), amount);
        vm.stopBroadcast();
        
        vm.broadcast(OWNER);
        escrow.fundRepo(repoId, accountId, token1, amount, "funding for batch operations");
        // Add USER2 as distributor for repo 11
        address[] memory distributors = new address[](1);
        distributors[0] = USER2;
        vm.broadcast(USER2);
        escrow.addDistributors(repoId, accountId, distributors);
        
        // Test maximum batch size distributions
        vm.startBroadcast(USER2); // USER2 is admin for repo 11
        
        Escrow.DistributionParams[] memory maxBatchDistributions = new Escrow.DistributionParams[](10);
        for (uint i = 0; i < 10; i++) {
            address recipient = address(uint160(0x1000 + i)); // Generate different recipients
            maxBatchDistributions[i] = Escrow.DistributionParams({
                amount: 50e18,
                recipient: recipient,
                claimPeriod: uint32(3600 + (i * 1800)), // Different claim periods
                token: token1
            });
        }
        
        uint[] memory maxBatchIds = escrow.distributeFromRepo(
            repoId, accountId, maxBatchDistributions, "maximum batch size distribution"
        );
        
        vm.stopBroadcast();
        
        // Test sender batch distributions
        vm.startBroadcast(OWNER_PRIVATE_KEY);
        token1.mint(OWNER, 500e18);
        token1.approve(address(escrow), 500e18);
        
        Escrow.DistributionParams[] memory senderBatchDistributions = new Escrow.DistributionParams[](5);
        for (uint i = 0; i < 5; i++) {
            address recipient = address(uint160(0x2000 + i));
            senderBatchDistributions[i] = Escrow.DistributionParams({
                amount: 80e18,
                recipient: recipient,
                claimPeriod: uint32(7200 + (i * 3600)),
                token: token1
            });
        }
        
        uint[] memory senderBatchIds = escrow.distributeFromSender(
            senderBatchDistributions, "sender batch distributions"
        );
        
        vm.stopBroadcast();
    }
    
    function testAdminManagementEdgeCases() internal {
        uint repoId = 12;
        uint accountId = 1;
        
        vm.startBroadcast(USER1); // USER1 is admin for repo 12
        
        // Add multiple admins in one call
        address[] memory newAdmins = new address[](5);
        for (uint i = 0; i < 5; i++) {
            newAdmins[i] = address(uint160(0x3000 + i));
        }
        
        escrow.addAdmins(repoId, accountId, newAdmins);
        
        // Add distributors
        address[] memory distributors = new address[](7);
        for (uint i = 0; i < 7; i++) {
            distributors[i] = address(uint160(0x4000 + i));
        }
        
        escrow.addDistributors(repoId, accountId, distributors);
        
        // Remove some distributors
        address[] memory removeDistributors = new address[](3);
        removeDistributors[0] = distributors[0];
        removeDistributors[1] = distributors[2];
        removeDistributors[2] = distributors[4];
        
        escrow.removeDistributors(repoId, accountId, removeDistributors);
        
        // Remove some admins (keeping enough to maintain admin functionality)
        address[] memory removeAdmins = new address[](2);
        removeAdmins[0] = newAdmins[0];
        removeAdmins[1] = newAdmins[2];
        
        escrow.removeAdmins(repoId, accountId, removeAdmins);
        
        vm.stopBroadcast();
    }
    
    function testFeeScenarios() internal {
        vm.startBroadcast(OWNER_PRIVATE_KEY);
        
        // Test different fee rates
        uint[] memory feeRates = new uint[](5);
        feeRates[0] = 100;  // 1%
        feeRates[1] = 500;  // 5%
        feeRates[2] = 750;  // 7.5%
        feeRates[3] = 1000; // 10%
        feeRates[4] = 250;  // Back to 2.5%
        
        for (uint i = 0; i < feeRates.length; i++) {
            escrow.setFeeOnClaim(feeRates[i]);
        }
        
        // Test different fee recipients
        address[] memory feeRecipients = new address[](4);
        feeRecipients[0] = USER1;
        feeRecipients[1] = USER2;
        feeRecipients[2] = RECIPIENT;
        feeRecipients[3] = OWNER; // Back to original
        
        for (uint i = 0; i < feeRecipients.length; i++) {
            escrow.setFeeRecipient(feeRecipients[i]);
        }
        
        vm.stopBroadcast();
    }
    
    function testTimingScenarios() internal {
        uint repoId = 14;
        uint accountId = 1;
        
        // Fund repo for timing tests
        vm.startBroadcast(OWNER_PRIVATE_KEY);
        token1.mint(OWNER, 1000e18);
        token1.approve(address(escrow), 1000e18);
        vm.stopBroadcast();
        
        vm.broadcast(OWNER);
        escrow.fundRepo(repoId, accountId, token1, 1000e18, "funding for timing tests");
        // Add USER1 as distributor for repo 14 (USER1 is an admin for repo 14)
        address[] memory distributors = new address[](1);
        distributors[0] = USER1;
        vm.broadcast(USER1);
        escrow.addDistributors(repoId, accountId, distributors);
        
        // Create distributions with very short claim periods for immediate reclaim testing
        vm.startBroadcast(USER1); // Assuming USER1 has admin access
        
        Escrow.DistributionParams[] memory shortPeriodDistributions = new Escrow.DistributionParams[](6);
        for (uint i = 0; i < 6; i++) {
            shortPeriodDistributions[i] = Escrow.DistributionParams({
                amount: 50e18,
                recipient: address(uint160(0x6000 + i)),
                claimPeriod: uint32(0), // 0 seconds - immediately reclaimable
                token: token1
            });
        }
        
        uint[] memory shortPeriodIds = escrow.distributeFromRepo(
            repoId, accountId, shortPeriodDistributions, "short period distributions for reclaim testing"
        );
        
        vm.stopBroadcast();
        
        // The distributions with 0 second claim period are now reclaimable
        vm.broadcast(USER1);
        escrow.reclaimRepoDistributions(repoId, accountId, shortPeriodIds, "reclaiming expired short period distributions");
        
        // Test sender distributions with immediate reclaim
        vm.startBroadcast(OWNER_PRIVATE_KEY);
        token1.mint(OWNER, 300e18);
        token1.approve(address(escrow), 300e18);
        
        Escrow.DistributionParams[] memory immediateReclaimDist = new Escrow.DistributionParams[](3);
        for (uint i = 0; i < 3; i++) {
            immediateReclaimDist[i] = Escrow.DistributionParams({
                amount: 80e18,
                recipient: address(uint160(0x7000 + i)),
                claimPeriod: uint32(0), // 0 seconds
                token: token1
            });
        }
        
        uint[] memory immediateReclaimIds = escrow.distributeFromSender(
            immediateReclaimDist, "immediate reclaim sender distributions"
        );
        
        vm.stopBroadcast();
        
        // Reclaim immediately expired sender distributions
        vm.broadcast(OWNER);
        escrow.reclaimSenderDistributions(immediateReclaimIds, "reclaiming expired sender distributions");
    }
    
    function testStressScenarios() internal {
        // Test rapid successive operations to generate many events
        uint repoId = 20;
        uint accountId = 1;
        
        // Initialize repo 20
        address[] memory admins = new address[](1);
        admins[0] = USER1;
        
        uint setAdminNonce = escrow.repoSetAdminNonce(repoId, accountId);
        uint signatureDeadline = block.timestamp + 7200; // Increased buffer to prevent expiration
        
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    repoId,
                    accountId,
                    keccak256(abi.encode(admins)),
                    setAdminNonce,
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PRIVATE_KEY, digest);
        
        vm.broadcast(USER1);
        escrow.initRepo(repoId, accountId, admins, signatureDeadline, v, r, s);
        // Add USER1 as distributor for repo 20
        address[] memory distributors = new address[](1);
        distributors[0] = USER1;
        vm.broadcast(USER1);
        escrow.addDistributors(repoId, accountId, distributors);
        
        // Fund with large amount for stress testing
        vm.startBroadcast(OWNER_PRIVATE_KEY);
        token1.mint(OWNER, 10000e18);
        token1.approve(address(escrow), 10000e18);
        vm.stopBroadcast();
        
        // Multiple funding operations
        for (uint i = 0; i < 5; i++) {
            vm.broadcast(OWNER);
            escrow.fundRepo(repoId, accountId, token1, 500e18, 
                bytes(abi.encodePacked("stress funding round ", i)));
        }
        
        // Rapid admin additions and removals
        vm.startBroadcast(USER1);
        for (uint i = 0; i < 3; i++) {
            address[] memory newAdmins = new address[](5);
            for (uint j = 0; j < 5; j++) {
                newAdmins[j] = address(uint160(0x8000 + (i * 5) + j));
            }
            escrow.addAdmins(repoId, accountId, newAdmins);
            
            // Remove some of them
            address[] memory removeAdmins = new address[](2);
            removeAdmins[0] = newAdmins[0];
            removeAdmins[1] = newAdmins[2];
            escrow.removeAdmins(repoId, accountId, removeAdmins);
        }
        vm.stopBroadcast();
        
        // Rapid distributions
        vm.startBroadcast(USER1);
        for (uint i = 0; i < 4; i++) {
            Escrow.DistributionParams[] memory stressDistributions = new Escrow.DistributionParams[](8);
            for (uint j = 0; j < 8; j++) {
                stressDistributions[j] = Escrow.DistributionParams({
                    amount: 25e18,
                    recipient: address(uint160(0x9000 + (i * 8) + j)),
                    claimPeriod: uint32(3600 + (j * 900)),
                    token: token1
                });
            }
            
            uint[] memory stressDistIds = escrow.distributeFromRepo(
                repoId, accountId, stressDistributions, 
                bytes(abi.encodePacked("stress distribution batch ", i))
            );
        }
        vm.stopBroadcast();
    }
    
    function testMultiTokenScenarios() internal {
        uint repoId = 30;
        uint accountId = 1;
        
        // Initialize repo 30
        address[] memory admins = new address[](1);
        admins[0] = USER1;
        
        uint setAdminNonce = escrow.repoSetAdminNonce(repoId, accountId);
        uint signatureDeadline = block.timestamp + 7200; // Increased buffer to prevent expiration
        
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    repoId,
                    accountId,
                    keccak256(abi.encode(admins)),
                    setAdminNonce,
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PRIVATE_KEY, digest);
        
        vm.broadcast(USER1);
        escrow.initRepo(repoId, accountId, admins, signatureDeadline, v, r, s);
        // Add USER1 as distributor for repo 30
        address[] memory distributors = new address[](1);
        distributors[0] = USER1;
        vm.broadcast(USER1);
        escrow.addDistributors(repoId, accountId, distributors);
        
        // Fund repo with multiple tokens
        vm.startBroadcast(OWNER_PRIVATE_KEY);
        token1.mint(OWNER, 5000e18);
        token2.mint(OWNER, 5000e6); // token2 has 6 decimals
        token1.approve(address(escrow), 5000e18);
        token2.approve(address(escrow), 5000e6);
        vm.stopBroadcast();
        
        // Fund with token1
        vm.broadcast(OWNER);
        escrow.fundRepo(repoId, accountId, token1, 2000e18, "funding with token1");
        
        // Fund with token2
        vm.broadcast(OWNER);
        escrow.fundRepo(repoId, accountId, token2, 2000e6, "funding with token2");
        
        // Mixed token distributions from repo
        vm.startBroadcast(USER1);
        
        Escrow.DistributionParams[] memory mixedDistributions1 = new Escrow.DistributionParams[](6);
        for (uint i = 0; i < 3; i++) {
            mixedDistributions1[i * 2] = Escrow.DistributionParams({
                amount: 100e18,
                recipient: address(uint160(0xA000 + i)),
                claimPeriod: uint32(3600 + (i * 1800)),
                token: token1
            });
            mixedDistributions1[i * 2 + 1] = Escrow.DistributionParams({
                amount: 100e6,
                recipient: address(uint160(0xA000 + i)),
                claimPeriod: uint32(3600 + (i * 1800)),
                token: token2
            });
        }
        
        uint[] memory mixedDistIds1 = escrow.distributeFromRepo(
            repoId, accountId, mixedDistributions1, "mixed token distributions batch 1"
        );
        
        vm.stopBroadcast();
        
        // Mixed token distributions from sender
        vm.startBroadcast(OWNER_PRIVATE_KEY);
        token1.mint(OWNER, 1000e18);
        token2.mint(OWNER, 1000e6);
        token1.approve(address(escrow), 1000e18);
        token2.approve(address(escrow), 1000e6);
        
        Escrow.DistributionParams[] memory senderMixedDistributions = new Escrow.DistributionParams[](8);
        for (uint i = 0; i < 4; i++) {
            senderMixedDistributions[i * 2] = Escrow.DistributionParams({
                amount: 80e18,
                recipient: address(uint160(0xB000 + i)),
                claimPeriod: uint32(7200 + (i * 1800)),
                token: token1
            });
            senderMixedDistributions[i * 2 + 1] = Escrow.DistributionParams({
                amount: 80e6,
                recipient: address(uint160(0xB000 + i)),
                claimPeriod: uint32(7200 + (i * 1800)),
                token: token2
            });
        }
        
        uint[] memory senderMixedIds = escrow.distributeFromSender(
            senderMixedDistributions, "sender mixed token distributions"
        );
        
        vm.stopBroadcast();
        
        // Cross-token reclaim scenarios
        vm.startBroadcast(USER1);
        
        // Create short-lived distributions for immediate reclaim testing
        Escrow.DistributionParams[] memory shortLivedMixed = new Escrow.DistributionParams[](4);
        shortLivedMixed[0] = Escrow.DistributionParams({
            amount: 50e18,
            recipient: address(0xC001),
            claimPeriod: uint32(0), // 0 seconds
            token: token1
        });
        shortLivedMixed[1] = Escrow.DistributionParams({
            amount: 50e6,
            recipient: address(0xC002),
            claimPeriod: uint32(0), // 0 seconds
            token: token2
        });
        shortLivedMixed[2] = Escrow.DistributionParams({
            amount: 75e18,
            recipient: address(0xC003),
            claimPeriod: uint32(0), // 0 seconds
            token: token1
        });
        shortLivedMixed[3] = Escrow.DistributionParams({
            amount: 75e6,
            recipient: address(0xC004),
            claimPeriod: uint32(0), // 0 seconds
            token: token2
        });
        
        uint[] memory shortLivedIds = escrow.distributeFromRepo(
            repoId, accountId, shortLivedMixed, "short-lived mixed token distributions for reclaim"
        );
        
        vm.stopBroadcast();
        
        // Reclaim the expired mixed token distributions
        vm.broadcast(USER1);
        escrow.reclaimRepoDistributions(repoId, accountId, shortLivedIds, "reclaiming mixed token distributions");
    }
    
    function testConfigurationChanges() internal {
        vm.startBroadcast(OWNER_PRIVATE_KEY);
        
        // Test multiple batch limit changes
        uint[] memory batchLimits = new uint[](6);
        batchLimits[0] = 5;
        batchLimits[1] = 15;
        batchLimits[2] = 20;
        batchLimits[3] = 8;
        batchLimits[4] = 12;
        batchLimits[5] = 10; // Back to original
        
        for (uint i = 0; i < batchLimits.length; i++) {
            escrow.setBatchLimit(batchLimits[i]);
        }
        
        // Test multiple signer changes
        address[] memory signers = new address[](4);
        signers[0] = USER1;
        signers[1] = USER2;
        signers[2] = RECIPIENT;
        signers[3] = SIGNER; // Back to original
        
        for (uint i = 0; i < signers.length; i++) {
            escrow.setSigner(signers[i]);
        }
        
        // Test extreme fee changes
        uint[] memory extremeFees = new uint[](8);
        extremeFees[0] = 0;    // 0%
        extremeFees[1] = 50;   // 0.5%
        extremeFees[2] = 1000; // 10% (maximum)
        extremeFees[3] = 999;  // 9.99%
        extremeFees[4] = 1;    // 0.01%
        extremeFees[5] = 500;  // 5%
        extremeFees[6] = 123;  // 1.23%
        extremeFees[7] = 250;  // Back to 2.5%
        
        for (uint i = 0; i < extremeFees.length; i++) {
            escrow.setFeeOnClaim(extremeFees[i]);
        }
        
        // Test rotating fee recipients
        address[] memory feeRecipients = new address[](6);
        feeRecipients[0] = address(0xD001);
        feeRecipients[1] = address(0xD002);
        feeRecipients[2] = address(0xD003);
        feeRecipients[3] = USER1;
        feeRecipients[4] = USER2;
        feeRecipients[5] = OWNER; // Back to original
        
        for (uint i = 0; i < feeRecipients.length; i++) {
            escrow.setFeeRecipient(feeRecipients[i]);
        }
        
        vm.stopBroadcast();
        
        // Test configuration changes impact on operations
        uint repoId = 40;
        uint accountId = 1;
        
        // Initialize repo with current configuration
        address[] memory admins = new address[](1);
        admins[0] = USER1;
        
        uint setAdminNonce = escrow.repoSetAdminNonce(repoId, accountId);
        uint signatureDeadline = block.timestamp + 7200; // Increased buffer to prevent expiration
        
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    repoId,
                    accountId,
                    keccak256(abi.encode(admins)),
                    setAdminNonce,
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PRIVATE_KEY, digest);
        
        vm.broadcast(USER1);
        escrow.initRepo(repoId, accountId, admins, signatureDeadline, v, r, s);
        // Add USER1 as distributor for repo 40
        address[] memory distributors = new address[](1);
        distributors[0] = USER1;
        vm.broadcast(USER1);
        escrow.addDistributors(repoId, accountId, distributors);
        
        // Fund and test distributions with different configurations
        vm.startBroadcast(OWNER_PRIVATE_KEY);
        token1.mint(OWNER, 2000e18);
        token1.approve(address(escrow), 2000e18);
        vm.stopBroadcast();
        
        vm.broadcast(OWNER);
        escrow.fundRepo(repoId, accountId, token1, 2000e18, "funding for configuration test");
        
        // Test distributions with different batch limits by changing configuration
        vm.startBroadcast(OWNER_PRIVATE_KEY);
        
        // Set small batch limit
        escrow.setBatchLimit(3);
        
        vm.stopBroadcast();
        
        // Test small batch distribution
        vm.startBroadcast(USER1);
        
        Escrow.DistributionParams[] memory smallBatchDist = new Escrow.DistributionParams[](3);
        for (uint i = 0; i < 3; i++) {
            smallBatchDist[i] = Escrow.DistributionParams({
                amount: 100e18,
                recipient: address(uint160(0xE000 + i)),
                claimPeriod: uint32(3600),
                token: token1
            });
        }
        
        uint[] memory smallBatchIds = escrow.distributeFromRepo(
            repoId, accountId, smallBatchDist, "small batch distribution test"
        );
        
        vm.stopBroadcast();
        
        // Change to larger batch limit
        vm.startBroadcast(OWNER_PRIVATE_KEY);
        escrow.setBatchLimit(20);
        vm.stopBroadcast();
        
        // Test large batch distribution
        vm.startBroadcast(USER1);
        
        Escrow.DistributionParams[] memory largeBatchDist = new Escrow.DistributionParams[](15);
        for (uint i = 0; i < 15; i++) {
            largeBatchDist[i] = Escrow.DistributionParams({
                amount: 50e18,
                recipient: address(uint160(0xF000 + i)),
                claimPeriod: uint32(7200),
                token: token1
            });
        }
        
        uint[] memory largeBatchIds = escrow.distributeFromRepo(
            repoId, accountId, largeBatchDist, "large batch distribution test"
        );
        
        vm.stopBroadcast();
        
        // Reset to original configuration
        vm.startBroadcast(OWNER_PRIVATE_KEY);
        escrow.setBatchLimit(BATCH_LIMIT);
        vm.stopBroadcast();
    }
} 
