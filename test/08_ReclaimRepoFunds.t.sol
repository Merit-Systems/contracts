// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "./00_Escrow.t.sol";

contract ReclaimRepo_Test is Base_Test {
    
    uint256 constant REPO_ID = 1;
    uint256 constant ACCOUNT_ID = 100;
    uint256 constant FUND_AMOUNT = 5000e18;
    uint256 constant DISTRIBUTION_AMOUNT = 1000e18;
    uint32 constant CLAIM_PERIOD = 7 days;

    address repoAdmin;
    address recipient;

    uint256 adminPrivateKey = 0x1111111111111111111111111111111111111111111111111111111111111111;
    
    function setUp() public override {
        super.setUp();
        
        repoAdmin = vm.addr(adminPrivateKey);
        recipient = makeAddr("recipient");
        
        // Initialize repo
        _initializeRepo();
    }

    function _initializeRepo() internal {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    REPO_ID,
                    ACCOUNT_ID,
                    keccak256(abi.encode(_toArray(repoAdmin))),
                    escrow.setAdminNonce(),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        escrow.initRepo(REPO_ID, ACCOUNT_ID, _toArray(repoAdmin), deadline, v, r, s);
    }

    function _initializeSecondRepo(uint256 repoId, uint256 instanceId, address admin) internal {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    repoId,
                    instanceId,
                    keccak256(abi.encode(_toArray(admin))),
                    escrow.setAdminNonce(),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            ownerPrivateKey,
            digest
        );
        escrow.initRepo(repoId, instanceId, _toArray(admin), deadline, v, r, s);
    }

    function _fundRepo(uint256 amount) internal {
        wETH.mint(address(this), amount);
        wETH.approve(address(escrow), amount);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, amount, "");
    }

    function _fundSpecificRepo(uint256 repoId, uint256 instanceId, uint256 amount) internal {
        wETH.mint(address(this), amount);
        wETH.approve(address(escrow), amount);
        escrow.fundRepo(repoId, instanceId, wETH, amount, "");
    }

    function _createRepoDistribution(address _recipient, uint256 amount) internal returns (uint256 distributionId) {
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: amount,
            recipient: _recipient,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        vm.prank(repoAdmin);
        uint[] memory distributionIds = escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");
        return distributionIds[0];
    }

    function _createSpecificRepoDistribution(uint256 repoId, uint256 instanceId, address admin, address _recipient, uint256 amount) internal returns (uint256 distributionId) {
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: amount,
            recipient: _recipient,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        vm.prank(admin);
        uint[] memory distributionIds = escrow.distributeFromRepo(repoId, instanceId, distributions, "");
        return distributionIds[0];
    }

    function _createSoloDistribution(address _recipient, uint256 amount) internal returns (uint256 distributionId) {
        address soloPayer = makeAddr("soloPayer");
        wETH.mint(soloPayer, amount);
        vm.prank(soloPayer);
        wETH.approve(address(escrow), amount);

        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: amount,
            recipient: _recipient,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        vm.prank(soloPayer);
        uint[] memory distributionIds = escrow.distributeFromSender(distributions, "");
        return distributionIds[0];
    }

    function _toArray(address addr) internal pure returns (address[] memory) {
        address[] memory arr = new address[](1);
        arr[0] = addr;
        return arr;
    }

    /* -------------------------------------------------------------------------- */
    /*                              RECLAIM REPO TESTS                            */
    /* -------------------------------------------------------------------------- */

    function test_reclaimToRepo_success() public {
        _fundRepo(FUND_AMOUNT);
        uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);

        // Move past claim deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        uint256 initialRepoBalance = escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH));

        // Expect the updated event with distributionBatchId
        vm.expectEmit(true, true, true, true);
        emit ReclaimedRepoDistribution(escrow.batchCount(), distributionId, address(this), DISTRIBUTION_AMOUNT);

        vm.expectEmit(true, true, true, true);
        emit ReclaimedRepoDistributionsBatch(escrow.batchCount(), REPO_ID, ACCOUNT_ID, distributionIds, "");

        escrow.reclaimRepoDistributions(REPO_ID, ACCOUNT_ID, distributionIds, "");

        // Check repo balance increased
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), initialRepoBalance + DISTRIBUTION_AMOUNT);

        // Check distribution status
        Escrow.Distribution memory distribution = escrow.getDistribution(distributionId);
        assertTrue(uint8(distribution.status) == 2); // Reclaimed
    }

    function test_reclaimToRepo_multipleDistributions() public {
        _fundRepo(FUND_AMOUNT);
        
        uint256 amount1 = 500e18;
        uint256 amount2 = 750e18;
        uint256 distributionId1 = _createRepoDistribution(recipient, amount1);
        uint256 distributionId2 = _createRepoDistribution(recipient, amount2);

        // Move past claim deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        uint[] memory distributionIds = new uint[](2);
        distributionIds[0] = distributionId1;
        distributionIds[1] = distributionId2;

        uint256 initialRepoBalance = escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH));

        escrow.reclaimRepoDistributions(REPO_ID, ACCOUNT_ID, distributionIds, "");

        // Check repo balance increased by total amount
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), initialRepoBalance + amount1 + amount2);

        // Check both distributions are reclaimed
        Escrow.Distribution memory distribution1 = escrow.getDistribution(distributionId1);
        Escrow.Distribution memory distribution2 = escrow.getDistribution(distributionId2);
        assertTrue(uint8(distribution1.status) == 2); // Reclaimed
        assertTrue(uint8(distribution2.status) == 2); // Reclaimed
    }

    function test_reclaimToRepo_anyoneCanReclaim() public {
        _fundRepo(FUND_AMOUNT);
        uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);

        // Move past claim deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        address randomUser = makeAddr("randomUser");

        // Random user should be able to reclaim expired repo distributions
        vm.prank(randomUser);
        escrow.reclaimRepoDistributions(REPO_ID, ACCOUNT_ID, distributionIds, "");

        // Check distribution was reclaimed
        Escrow.Distribution memory distribution = escrow.getDistribution(distributionId);
        assertTrue(uint8(distribution.status) == 2); // Reclaimed
    }

    function test_reclaimToRepo_revert_wrongRepoId() public {
        _fundRepo(FUND_AMOUNT);
        uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);

        // Move past claim deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        // Try to reclaim with wrong repo ID
        expectRevert(Errors.DISTRIBUTION_NOT_FROM_REPO);
        escrow.reclaimRepoDistributions(999, ACCOUNT_ID, distributionIds, "");
    }

    function test_reclaimToRepo_revert_wrongInstanceId() public {
        _fundRepo(FUND_AMOUNT);
        uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);

        // Move past claim deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        // Try to reclaim with wrong instance ID
        expectRevert(Errors.DISTRIBUTION_NOT_FROM_REPO);
        escrow.reclaimRepoDistributions(REPO_ID, 999, distributionIds, "");
    }

    function test_reclaimToRepo_revert_wrongRepoAndInstanceId() public {
        _fundRepo(FUND_AMOUNT);
        uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);

        // Move past claim deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        // Try to reclaim with wrong repo and instance ID
        expectRevert(Errors.DISTRIBUTION_NOT_FROM_REPO);
        escrow.reclaimRepoDistributions(999, 888, distributionIds, "");
    }

    function test_reclaimToRepo_crossRepoValidation() public {
        // Setup second repo
        uint256 repo2Id = 2;
        uint256 instance2Id = 200;
        address admin2 = makeAddr("admin2");
        _initializeSecondRepo(repo2Id, instance2Id, admin2);

        // Fund both repos
        _fundRepo(FUND_AMOUNT);
        _fundSpecificRepo(repo2Id, instance2Id, FUND_AMOUNT);

        // Create distributions from both repos
        uint256 distributionId1 = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        uint256 distributionId2 = _createSpecificRepoDistribution(repo2Id, instance2Id, admin2, recipient, DISTRIBUTION_AMOUNT);

        // Move past claim deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        uint[] memory distributionIds1 = new uint[](1);
        distributionIds1[0] = distributionId1;

        uint[] memory distributionIds2 = new uint[](1);
        distributionIds2[0] = distributionId2;

        // Try to reclaim repo1 distribution with repo2 parameters - should fail
        expectRevert(Errors.DISTRIBUTION_NOT_FROM_REPO);
        escrow.reclaimRepoDistributions(repo2Id, instance2Id, distributionIds1, "");

        // Try to reclaim repo2 distribution with repo1 parameters - should fail
        expectRevert(Errors.DISTRIBUTION_NOT_FROM_REPO);
        escrow.reclaimRepoDistributions(REPO_ID, ACCOUNT_ID, distributionIds2, "");

        // Reclaim with correct parameters should work
        uint256 initialBalance1 = escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH));
        uint256 initialBalance2 = escrow.getAccountBalance(repo2Id, instance2Id, address(wETH));

        escrow.reclaimRepoDistributions(REPO_ID, ACCOUNT_ID, distributionIds1, "");
        escrow.reclaimRepoDistributions(repo2Id, instance2Id, distributionIds2, "");

        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), initialBalance1 + DISTRIBUTION_AMOUNT);
        assertEq(escrow.getAccountBalance(repo2Id, instance2Id, address(wETH)), initialBalance2 + DISTRIBUTION_AMOUNT);
    }

    function test_reclaimToRepo_mixedDistributionsFromDifferentRepos() public {
        // Setup second repo
        uint256 repo2Id = 2;
        uint256 instance2Id = 200;
        address admin2 = makeAddr("admin2");
        _initializeSecondRepo(repo2Id, instance2Id, admin2);

        // Fund both repos
        _fundRepo(FUND_AMOUNT);
        _fundSpecificRepo(repo2Id, instance2Id, FUND_AMOUNT);

        // Create distributions from both repos
        uint256 distributionId1 = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        uint256 distributionId2 = _createSpecificRepoDistribution(repo2Id, instance2Id, admin2, recipient, DISTRIBUTION_AMOUNT);

        // Move past claim deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        // Try to reclaim mixed distributions - should fail
        uint[] memory mixedDistributionIds = new uint[](2);
        mixedDistributionIds[0] = distributionId1;
        mixedDistributionIds[1] = distributionId2;

        expectRevert(Errors.DISTRIBUTION_NOT_FROM_REPO);
        escrow.reclaimRepoDistributions(REPO_ID, ACCOUNT_ID, mixedDistributionIds, "");
    }

    function test_reclaimToRepo_batchIdIncrement() public {
        _fundRepo(FUND_AMOUNT);
        uint256 distributionId1 = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        uint256 distributionId2 = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);

        // Move past claim deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        uint[] memory distributionIds1 = new uint[](1);
        distributionIds1[0] = distributionId1;

        uint[] memory distributionIds2 = new uint[](1);
        distributionIds2[0] = distributionId2;

        uint256 initialBatchCount = escrow.batchCount();

        // First reclaim
        escrow.reclaimRepoDistributions(REPO_ID, ACCOUNT_ID, distributionIds1, "");
        assertEq(escrow.batchCount(), initialBatchCount + 1);

        // Second reclaim
        escrow.reclaimRepoDistributions(REPO_ID, ACCOUNT_ID, distributionIds2, "");
        assertEq(escrow.batchCount(), initialBatchCount + 2);
    }

    function test_reclaimToRepo_revert_batchLimitExceeded() public {
        uint256 batchLimit = escrow.batchLimit();
        uint[] memory distributionIds = new uint[](batchLimit + 1);

        expectRevert(Errors.BATCH_LIMIT_EXCEEDED);
        escrow.reclaimRepoDistributions(REPO_ID, ACCOUNT_ID, distributionIds, "");
    }

    function test_reclaimToRepo_revert_emptyArray() public {
        // Test that empty distributionIds array reverts with EMPTY_ARRAY error
        uint[] memory distributionIds = new uint[](0);

        uint256 initialBatchCount = escrow.batchCount();
        uint256 initialRepoBalance = escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH));

        // Should revert with EMPTY_ARRAY error
        expectRevert(Errors.EMPTY_ARRAY);
        escrow.reclaimRepoDistributions(REPO_ID, ACCOUNT_ID, distributionIds, "");

        // Verify no state changes occurred
        assertEq(escrow.batchCount(), initialBatchCount, "Batch count should not increment");
        assertEq(
            escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), 
            initialRepoBalance, 
            "Repo balance should not change"
        );
    }

    function test_reclaimToRepo_revert_emptyArray_anyUser() public {
        // Test that empty array fails for any user (not just admins)
        uint[] memory distributionIds = new uint[](0);
        address randomUser = makeAddr("randomUser");

        expectRevert(Errors.EMPTY_ARRAY);
        vm.prank(randomUser);
        escrow.reclaimRepoDistributions(REPO_ID, ACCOUNT_ID, distributionIds, "");
    }

    function test_reclaimToRepo_revert_invalidDistributionId() public {
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = 999; // Non-existent

        expectRevert(Errors.INVALID_DISTRIBUTION_ID);
        escrow.reclaimRepoDistributions(REPO_ID, ACCOUNT_ID, distributionIds, "");
    }

    function test_reclaimToRepo_revert_notRepoDistribution() public {
        uint256 distributionId = _createSoloDistribution(recipient, DISTRIBUTION_AMOUNT);
        
        // Move past claim deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        expectRevert(Errors.NOT_REPO_DISTRIBUTION);
        escrow.reclaimRepoDistributions(REPO_ID, ACCOUNT_ID, distributionIds, "");
    }

    function test_reclaimToRepo_revert_alreadyClaimed() public {
        _fundRepo(FUND_AMOUNT);
        uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);

        // First claim the distribution
        uint[] memory claimIds = new uint[](1);
        claimIds[0] = distributionId;
        
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.CLAIM_TYPEHASH(),
                    keccak256(abi.encode(claimIds)),
                    recipient,
                    escrow.recipientClaimNonce(recipient),
                    block.timestamp + 1 hours
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest); // owner is signer

        vm.prank(recipient);
        escrow.claim(claimIds, block.timestamp + 1 hours, v, r, s, "");

        // Now try to reclaim the already claimed distribution
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        expectRevert(Errors.ALREADY_CLAIMED);
        escrow.reclaimRepoDistributions(REPO_ID, ACCOUNT_ID, distributionIds, "");
    }

    function test_reclaimToRepo_revert_stillClaimable() public {
        _fundRepo(FUND_AMOUNT);
        uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);

        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        // Still within claim period
        expectRevert(Errors.STILL_CLAIMABLE);
        escrow.reclaimRepoDistributions(REPO_ID, ACCOUNT_ID, distributionIds, "");
    }

    function test_reclaimToRepo_fuzz_amounts(uint256 amount1, uint256 amount2) public {
        vm.assume(amount1 >= 100 && amount1 <= 1000e18); // Ensure minimum size for fees
        vm.assume(amount2 >= 100 && amount2 <= 1000e18);

        _fundRepo(amount1 + amount2 + 1000e18); // Extra buffer

        uint256 distributionId1 = _createRepoDistribution(recipient, amount1);
        uint256 distributionId2 = _createRepoDistribution(recipient, amount2);

        // Move past deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        uint[] memory distributionIds = new uint[](2);
        distributionIds[0] = distributionId1;
        distributionIds[1] = distributionId2;

        uint256 initialRepoBalance = escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH));
        escrow.reclaimRepoDistributions(REPO_ID, ACCOUNT_ID, distributionIds, "");
        
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), initialRepoBalance + amount1 + amount2);
    }

    function test_reclaimToRepo_fuzz_batchSizes(uint8 numDistributions) public {
        vm.assume(numDistributions > 0 && numDistributions <= 20); // Reasonable limit
        uint256 batchLimit = escrow.batchLimit();
        
        uint256 distributionAmount = 100e18;
        _fundRepo(distributionAmount * numDistributions + 1000e18); // Extra buffer
        
        uint[] memory distributionIds = new uint[](numDistributions);
        
        // Create distributions
        for (uint i = 0; i < numDistributions; i++) {
            distributionIds[i] = _createRepoDistribution(
                makeAddr(string(abi.encodePacked("recipient", i))), 
                distributionAmount
            );
        }
        
        // Move past deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);
        
        uint256 initialRepoBalance = escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH));
        
        if (numDistributions <= batchLimit) {
            // Should succeed
            escrow.reclaimRepoDistributions(REPO_ID, ACCOUNT_ID, distributionIds, "");
            
            // Verify all distributions were reclaimed
            for (uint i = 0; i < numDistributions; i++) {
                Escrow.Distribution memory distribution = escrow.getDistribution(distributionIds[i]);
                assertTrue(uint8(distribution.status) == 2); // Reclaimed
            }
            
            // Check balance increase
            assertEq(
                escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), 
                initialRepoBalance + (distributionAmount * numDistributions)
            );
        } else {
            // Should fail if exceeds batch limit
            expectRevert(Errors.BATCH_LIMIT_EXCEEDED);
            escrow.reclaimRepoDistributions(REPO_ID, ACCOUNT_ID, distributionIds, "");
        }
    }

    function test_reclaimToRepo_fuzz_timeDelays(uint32 extraTime) public {
        vm.assume(extraTime >= 1 && extraTime <= 365 days);
        
        _fundRepo(FUND_AMOUNT);
        uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        
        // Move past deadline by the fuzzed amount
        vm.warp(block.timestamp + CLAIM_PERIOD + extraTime);
        
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;
        
        uint256 initialRepoBalance = escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH));
        escrow.reclaimRepoDistributions(REPO_ID, ACCOUNT_ID, distributionIds, "");
        
        // Should work regardless of how much time has passed after deadline
        assertEq(
            escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), 
            initialRepoBalance + DISTRIBUTION_AMOUNT
        );
        
        Escrow.Distribution memory distribution = escrow.getDistribution(distributionId);
        assertTrue(uint8(distribution.status) == 2); // Reclaimed
    }

    function test_reclaimToRepo_fuzz_callers(address caller) public {
        vm.assume(caller != address(0));
        
        _fundRepo(FUND_AMOUNT);
        uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        
        // Move past deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);
        
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;
        
        uint256 initialRepoBalance = escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH));
        
        // Anyone should be able to reclaim expired repo distributions
        vm.prank(caller);
        escrow.reclaimRepoDistributions(REPO_ID, ACCOUNT_ID, distributionIds, "");
        
        assertEq(
            escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), 
            initialRepoBalance + DISTRIBUTION_AMOUNT
        );
    }

    function test_reclaimToRepo_fuzz_mixedDistributionTypes(uint8 numRepo, uint8 numSolo) public {
        vm.assume(numRepo > 0 && numRepo <= 10);
        vm.assume(numSolo > 0 && numSolo <= 10);
        
        uint256 distributionAmount = 100e18;
        _fundRepo(distributionAmount * numRepo + 1000e18);
        
        uint[] memory repoDistributionIds = new uint[](numRepo);
        uint[] memory mixedIds = new uint[](numRepo + numSolo);
        
        // Create repo distributions
        for (uint i = 0; i < numRepo; i++) {
            repoDistributionIds[i] = _createRepoDistribution(
                makeAddr(string(abi.encodePacked("repoRecipient", i))), 
                distributionAmount
            );
            mixedIds[i] = repoDistributionIds[i];
        }
        
        // Create solo distributions
        for (uint i = 0; i < numSolo; i++) {
            uint256 soloId = _createSoloDistribution(
                makeAddr(string(abi.encodePacked("soloRecipient", i))), 
                distributionAmount
            );
            mixedIds[numRepo + i] = soloId;
        }
        
        // Move past deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);
        
        // Try to reclaim all (should fail because of solo distributions)
        expectRevert(Errors.NOT_REPO_DISTRIBUTION);
        escrow.reclaimRepoDistributions(REPO_ID, ACCOUNT_ID, mixedIds, "");
        
        // Reclaiming only repo distributions should work
        uint256 initialRepoBalance = escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH));
        escrow.reclaimRepoDistributions(REPO_ID, ACCOUNT_ID, repoDistributionIds, "");
        
        assertEq(
            escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), 
            initialRepoBalance + (distributionAmount * numRepo)
        );
    }

    function test_reclaimToRepo_fuzz_repoAndAccountIds(uint256 repoId, uint256 instanceId, uint256 wrongRepoId) public {
        vm.assume(repoId != 0 && repoId <= type(uint128).max);
        vm.assume(instanceId != 0 && instanceId <= type(uint128).max);
        vm.assume(wrongRepoId != repoId && wrongRepoId != 0 && wrongRepoId <= type(uint128).max);
        
        // Setup repo with fuzzed IDs
        address admin = makeAddr("fuzzAdmin");
        _initializeSecondRepo(repoId, instanceId, admin);
        _fundSpecificRepo(repoId, instanceId, FUND_AMOUNT);
        
        uint256 distributionId = _createSpecificRepoDistribution(repoId, instanceId, admin, recipient, DISTRIBUTION_AMOUNT);
        
        // Move past deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);
        
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;
        
        // Should fail with wrong repo ID
        expectRevert(Errors.DISTRIBUTION_NOT_FROM_REPO);
        escrow.reclaimRepoDistributions(wrongRepoId, instanceId, distributionIds, "");
        
        // Should succeed with correct IDs
        uint256 initialBalance = escrow.getAccountBalance(repoId, instanceId, address(wETH));
        escrow.reclaimRepoDistributions(repoId, instanceId, distributionIds, "");
        assertEq(escrow.getAccountBalance(repoId, instanceId, address(wETH)), initialBalance + DISTRIBUTION_AMOUNT);
    }

    /* -------------------------------------------------------------------------- */
    /*                                    EVENTS                                  */
    /* -------------------------------------------------------------------------- */

    event ReclaimedRepoDistribution(uint256 indexed distributionBatchId, uint256 indexed distributionId, address indexed admin, uint256 amount);
    event ReclaimedRepoDistributionsBatch(uint256 indexed distributionBatchId, uint256 indexed repoId, uint256 indexed instanceId, uint256[] distributionIds, bytes data);
} 