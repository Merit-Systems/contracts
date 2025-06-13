// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "./00_Escrow.t.sol";

contract ReclaimSolo_Test is Base_Test {
    
    uint256 constant REPO_ID = 1;
    uint256 constant ACCOUNT_ID = 100;
    uint256 constant DISTRIBUTION_AMOUNT = 1000e18;
    uint32 constant CLAIM_PERIOD = 7 days;

    address repoAdmin;
    address recipient;
    address soloPayer;
    address soloPayer2;

    uint256 adminPrivateKey = 0x1111111111111111111111111111111111111111111111111111111111111111;
    
    function setUp() public override {
        super.setUp();
        
        repoAdmin = vm.addr(adminPrivateKey);
        recipient = makeAddr("recipient");
        soloPayer = makeAddr("soloPayer");
        soloPayer2 = makeAddr("soloPayer2");
        
        // Initialize repo for comparison tests
        _initializeRepo();
        
        // Setup solo payers
        wETH.mint(soloPayer, DISTRIBUTION_AMOUNT * 10);
        vm.prank(soloPayer);
        wETH.approve(address(escrow), type(uint256).max);
        
        wETH.mint(soloPayer2, DISTRIBUTION_AMOUNT * 10);
        vm.prank(soloPayer2);
        wETH.approve(address(escrow), type(uint256).max);
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
                    escrow.ownerNonce(),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        escrow.initRepo(REPO_ID, ACCOUNT_ID, _toArray(repoAdmin), deadline, v, r, s);
    }

    function _fundRepo(uint256 amount) internal {
        wETH.mint(address(this), amount);
        wETH.approve(address(escrow), amount);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, amount, "");
    }

    function _createSoloDistribution(address payer, address _recipient, uint256 amount) internal returns (uint256 distributionId) {
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: amount,
            recipient: _recipient,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        vm.prank(payer);
        uint[] memory distributionIds = escrow.distributeFromSender(distributions, "");
        return distributionIds[0];
    }

    function _createRepoDistribution(address _recipient, uint256 amount) internal returns (uint256 distributionId) {
        _fundRepo(amount * 2); // Fund enough for the distribution
        
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

    function _toArray(address addr) internal pure returns (address[] memory) {
        address[] memory arr = new address[](1);
        arr[0] = addr;
        return arr;
    }

    /* -------------------------------------------------------------------------- */
    /*                              RECLAIM SOLO TESTS                            */
    /* -------------------------------------------------------------------------- */

    function test_reclaimSenderDistributions_success() public {
        uint256 distributionId = _createSoloDistribution(soloPayer, recipient, DISTRIBUTION_AMOUNT);

        // Move past claim deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        uint256 initialPayerBalance = wETH.balanceOf(soloPayer);

        vm.expectEmit(true, true, true, true);
        emit ReclaimedSenderDistribution(distributionId, soloPayer, DISTRIBUTION_AMOUNT);

        escrow.reclaimSenderDistributions(distributionIds, "");

        // Check payer received funds back
        assertEq(wETH.balanceOf(soloPayer), initialPayerBalance + DISTRIBUTION_AMOUNT);

        // Check distribution status
        Escrow.Distribution memory distribution = escrow.getDistribution(distributionId);
        assertTrue(uint8(distribution.status) == 2); // Reclaimed
    }

    function test_reclaimSenderDistributions_multipleDistributions() public {
        uint256 amount1 = 400e18;
        uint256 amount2 = 600e18;
        uint256 distributionId1 = _createSoloDistribution(soloPayer, recipient, amount1);
        uint256 distributionId2 = _createSoloDistribution(soloPayer, recipient, amount2);

        // Move past claim deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        uint[] memory distributionIds = new uint[](2);
        distributionIds[0] = distributionId1;
        distributionIds[1] = distributionId2;

        uint256 initialPayerBalance = wETH.balanceOf(soloPayer);

        escrow.reclaimSenderDistributions(distributionIds, "");

        // Check payer received all funds back
        assertEq(wETH.balanceOf(soloPayer), initialPayerBalance + amount1 + amount2);

        // Check both distributions are reclaimed
        Escrow.Distribution memory distribution1 = escrow.getDistribution(distributionId1);
        Escrow.Distribution memory distribution2 = escrow.getDistribution(distributionId2);
        assertTrue(uint8(distribution1.status) == 2); // Reclaimed
        assertTrue(uint8(distribution2.status) == 2); // Reclaimed
    }

    function test_reclaimSenderDistributions_multiplePayers() public {
        uint256 distributionId1 = _createSoloDistribution(soloPayer, recipient, DISTRIBUTION_AMOUNT);
        uint256 distributionId2 = _createSoloDistribution(soloPayer2, recipient, DISTRIBUTION_AMOUNT);

        // Move past claim deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        uint[] memory distributionIds = new uint[](2);
        distributionIds[0] = distributionId1;
        distributionIds[1] = distributionId2;

        uint256 initialPayer1Balance = wETH.balanceOf(soloPayer);
        uint256 initialPayer2Balance = wETH.balanceOf(soloPayer2);

        escrow.reclaimSenderDistributions(distributionIds, "");

        // Each payer should get their own distribution back
        assertEq(wETH.balanceOf(soloPayer), initialPayer1Balance + DISTRIBUTION_AMOUNT);
        assertEq(wETH.balanceOf(soloPayer2), initialPayer2Balance + DISTRIBUTION_AMOUNT);
    }

    function test_reclaimSenderDistributions_differentRecipients() public {
        address recipient2 = makeAddr("recipient2");
        uint256 distributionId1 = _createSoloDistribution(soloPayer, recipient, DISTRIBUTION_AMOUNT);
        uint256 distributionId2 = _createSoloDistribution(soloPayer, recipient2, DISTRIBUTION_AMOUNT);

        // Move past claim deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        uint[] memory distributionIds = new uint[](2);
        distributionIds[0] = distributionId1;
        distributionIds[1] = distributionId2;

        uint256 initialPayerBalance = wETH.balanceOf(soloPayer);

        escrow.reclaimSenderDistributions(distributionIds, "");

        // Payer should get back both distributions regardless of recipients
        assertEq(wETH.balanceOf(soloPayer), initialPayerBalance + (DISTRIBUTION_AMOUNT * 2));
    }

    function test_reclaimSenderDistributions_maxBatchLimit() public {
        uint256 batchLimit = escrow.batchLimit();
        uint256 distributionAmount = 1e18; // Smaller amount to fit within limits
        uint[] memory distributionIds = new uint[](batchLimit);
        
        // Create batch limit number of distributions
        for (uint i = 0; i < batchLimit; i++) {
            distributionIds[i] = _createSoloDistribution(soloPayer, recipient, distributionAmount);
        }

        // Move past claim deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        uint256 initialPayerBalance = wETH.balanceOf(soloPayer);

        escrow.reclaimSenderDistributions(distributionIds, "");

        // Check all were reclaimed
        assertEq(wETH.balanceOf(soloPayer), initialPayerBalance + (distributionAmount * batchLimit));
    }

    function test_reclaimSenderDistributions_anyoneCanReclaim() public {
        uint256 distributionId = _createSoloDistribution(soloPayer, recipient, DISTRIBUTION_AMOUNT);

        // Move past claim deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        address randomUser = makeAddr("randomUser");
        uint256 initialPayerBalance = wETH.balanceOf(soloPayer);

        // Random user should be able to reclaim expired solo distributions
        vm.prank(randomUser);
        escrow.reclaimSenderDistributions(distributionIds, "");

        // Original payer should still receive the funds
        assertEq(wETH.balanceOf(soloPayer), initialPayerBalance + DISTRIBUTION_AMOUNT);

        // Check distribution was reclaimed
        Escrow.Distribution memory distribution = escrow.getDistribution(distributionId);
        assertTrue(uint8(distribution.status) == 2); // Reclaimed
    }

    function test_reclaimSenderDistributions_afterPartialClaim() public {
        uint256 distributionId1 = _createSoloDistribution(soloPayer, recipient, DISTRIBUTION_AMOUNT);
        uint256 distributionId2 = _createSoloDistribution(soloPayer, recipient, DISTRIBUTION_AMOUNT);

        // Claim one distribution
        uint[] memory claimIds = new uint[](1);
        claimIds[0] = distributionId1;
        
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.CLAIM_TYPEHASH(),
                    keccak256(abi.encode(claimIds)),
                    recipient,
                    escrow.recipientNonce(recipient),
                    block.timestamp + 1 hours
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest); // owner is signer

        vm.prank(recipient);
        escrow.claim(claimIds, block.timestamp + 1 hours, v, r, s, "");

        // Move past deadline and reclaim the other
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        uint[] memory reclaimIds = new uint[](1);
        reclaimIds[0] = distributionId2;

        uint256 initialPayerBalance = wETH.balanceOf(soloPayer);
        escrow.reclaimSenderDistributions(reclaimIds, "");

        // Should reclaim successfully
        assertEq(wETH.balanceOf(soloPayer), initialPayerBalance + DISTRIBUTION_AMOUNT);
    }

    function test_reclaimSenderDistributions_revert_batchLimitExceeded() public {
        uint256 batchLimit = escrow.batchLimit();
        uint[] memory distributionIds = new uint[](batchLimit + 1);

        expectRevert(Errors.BATCH_LIMIT_EXCEEDED);
        escrow.reclaimSenderDistributions(distributionIds, "");
    }

    function test_reclaimSenderDistributions_revert_invalidDistributionId() public {
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = 999; // Non-existent

        expectRevert(Errors.INVALID_DISTRIBUTION_ID);
        escrow.reclaimSenderDistributions(distributionIds, "");
    }

    function test_reclaimSenderDistributions_revert_notSoloDistribution() public {
        uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        
        // Move past claim deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        expectRevert(Errors.NOT_DIRECT_DISTRIBUTION);
        escrow.reclaimSenderDistributions(distributionIds, "");
    }

    function test_reclaimSenderDistributions_revert_alreadyClaimed() public {
        uint256 distributionId = _createSoloDistribution(soloPayer, recipient, DISTRIBUTION_AMOUNT);

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
                    escrow.recipientNonce(recipient),
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
        escrow.reclaimSenderDistributions(distributionIds, "");
    }

    function test_reclaimSenderDistributions_revert_stillClaimable() public {
        uint256 distributionId = _createSoloDistribution(soloPayer, recipient, DISTRIBUTION_AMOUNT);

        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        // Still within claim period
        expectRevert(Errors.STILL_CLAIMABLE);
        escrow.reclaimSenderDistributions(distributionIds, "");
    }

    function test_reclaimSenderDistributions_revert_alreadyReclaimed() public {
        uint256 distributionId = _createSoloDistribution(soloPayer, recipient, DISTRIBUTION_AMOUNT);

        // Move past claim deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        // First reclaim should succeed
        escrow.reclaimSenderDistributions(distributionIds, "");

        // Second reclaim should fail
        expectRevert(Errors.ALREADY_CLAIMED);
        escrow.reclaimSenderDistributions(distributionIds, "");
    }

    function test_reclaimSenderDistributions_mixedValidInvalid() public {
        uint256 validDistributionId = _createSoloDistribution(soloPayer, recipient, DISTRIBUTION_AMOUNT);
        uint256 repoDistributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);

        // Move past claim deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        uint[] memory distributionIds = new uint[](2);
        distributionIds[0] = validDistributionId;
        distributionIds[1] = repoDistributionId; // This is a repo distribution, should fail

        expectRevert(Errors.NOT_DIRECT_DISTRIBUTION);
        escrow.reclaimSenderDistributions(distributionIds, "");
    }

    function test_reclaimSenderDistributions_distributionDataIntegrity() public {
        uint256 distributionId = _createSoloDistribution(soloPayer, recipient, DISTRIBUTION_AMOUNT);

        // Verify distribution data before reclaim
        Escrow.Distribution memory distributionBefore = escrow.getDistribution(distributionId);
        assertEq(distributionBefore.amount, DISTRIBUTION_AMOUNT);
        assertEq(distributionBefore.recipient, recipient);
        assertEq(distributionBefore.payer, soloPayer);
        assertTrue(uint8(distributionBefore.status) == 0); // Distributed
        assertTrue(uint8(distributionBefore._type) == 1); // Solo

        // Move past claim deadline and reclaim
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        escrow.reclaimSenderDistributions(distributionIds, "");

        // Verify distribution data after reclaim (everything same except status)
        Escrow.Distribution memory distributionAfter = escrow.getDistribution(distributionId);
        assertEq(distributionAfter.amount, DISTRIBUTION_AMOUNT);
        assertEq(distributionAfter.recipient, recipient);
        assertEq(distributionAfter.payer, soloPayer);
        assertTrue(uint8(distributionAfter.status) == 2); // Reclaimed
        assertTrue(uint8(distributionAfter._type) == 1); // Solo
    }

    function test_reclaimSenderDistributions_fuzz_amounts(uint256 amount1, uint256 amount2) public {
        vm.assume(amount1 >= 100 && amount1 <= 1000e18); // Ensure minimum size for fees
        vm.assume(amount2 >= 100 && amount2 <= 1000e18);

        uint256 distributionId1 = _createSoloDistribution(soloPayer, recipient, amount1);
        uint256 distributionId2 = _createSoloDistribution(soloPayer, recipient, amount2);

        // Move past deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        uint[] memory distributionIds = new uint[](2);
        distributionIds[0] = distributionId1;
        distributionIds[1] = distributionId2;

        uint256 initialPayerBalance = wETH.balanceOf(soloPayer);
        escrow.reclaimSenderDistributions(distributionIds, "");
        
        assertEq(wETH.balanceOf(soloPayer), initialPayerBalance + amount1 + amount2);
    }

    function test_reclaimSenderDistributions_fuzz_timeDelays(uint32 timeDelay) public {
        vm.assume(timeDelay > CLAIM_PERIOD && timeDelay <= 365 days);
        
        uint256 distributionId = _createSoloDistribution(soloPayer, recipient, DISTRIBUTION_AMOUNT);

        // Move past claim deadline by the fuzzed amount
        vm.warp(block.timestamp + timeDelay);

        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        uint256 initialPayerBalance = wETH.balanceOf(soloPayer);
        escrow.reclaimSenderDistributions(distributionIds, "");
        
        assertEq(wETH.balanceOf(soloPayer), initialPayerBalance + DISTRIBUTION_AMOUNT);
    }

    function test_reclaimSenderDistributions_fuzz_multiplePayers(uint8 payerCount) public {
        vm.assume(payerCount > 0 && payerCount <= 10); // Reasonable limit
        
        address[] memory payers = new address[](payerCount);
        uint[] memory distributionIds = new uint[](payerCount);
        uint256[] memory initialBalances = new uint256[](payerCount);
        
        // Create distributions from different payers
        for (uint i = 0; i < payerCount; i++) {
            payers[i] = makeAddr(string(abi.encodePacked("payer", i)));
            wETH.mint(payers[i], DISTRIBUTION_AMOUNT);
            vm.prank(payers[i]);
            wETH.approve(address(escrow), DISTRIBUTION_AMOUNT);
            
            distributionIds[i] = _createSoloDistribution(payers[i], recipient, DISTRIBUTION_AMOUNT);
            initialBalances[i] = wETH.balanceOf(payers[i]);
        }

        // Move past deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        escrow.reclaimSenderDistributions(distributionIds, "");
        
        // Verify each payer got their funds back
        for (uint i = 0; i < payerCount; i++) {
            assertEq(wETH.balanceOf(payers[i]), initialBalances[i] + DISTRIBUTION_AMOUNT);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                                    EVENTS                                  */
    /* -------------------------------------------------------------------------- */

    event ReclaimedSenderDistribution(uint256 indexed distributionId, address indexed payer, uint256 amount);
} 