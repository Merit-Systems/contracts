// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "./00_Escrow.t.sol";

contract DistributeFromSender_Test is Base_Test {
    
    uint256 constant DISTRIBUTION_AMOUNT = 1000e18;
    uint32 constant CLAIM_PERIOD = 7 days;

    address recipient1;
    address recipient2;
    address distributor;
    
    function setUp() public override {
        super.setUp();
        
        recipient1 = makeAddr("recipient1");
        recipient2 = makeAddr("recipient2");
        distributor = makeAddr("distributor");
        
        // Give distributor some tokens for solo distributions
        wETH.mint(distributor, DISTRIBUTION_AMOUNT * 10);
        vm.prank(distributor);
        wETH.approve(address(escrow), type(uint256).max);
    }

    /* -------------------------------------------------------------------------- */
    /*                           DISTRIBUTE SOLO TESTS                           */
    /* -------------------------------------------------------------------------- */

    function test_distributeFromSender_success() public {
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        uint256 initialDistributorBalance = wETH.balanceOf(distributor);
        uint256 initialEscrowBalance = wETH.balanceOf(address(escrow));
        uint256 expectedDeadline = block.timestamp + CLAIM_PERIOD;

        vm.expectEmit(true, true, true, true);
        emit DistributedFromSender(0, distributor, recipient1, address(wETH), DISTRIBUTION_AMOUNT, expectedDeadline);

        vm.prank(distributor);
        uint[] memory distributionIds = escrow.distributeFromSender(distributions, "");

        // Check return values
        assertEq(distributionIds.length, 1);
        assertEq(distributionIds[0], 0);

        // Check balances
        assertEq(wETH.balanceOf(distributor), initialDistributorBalance - DISTRIBUTION_AMOUNT);
        assertEq(wETH.balanceOf(address(escrow)), initialEscrowBalance + DISTRIBUTION_AMOUNT);

        // Check distribution was created
        Escrow.Distribution memory distribution = escrow.getDistribution(distributionIds[0]);
        assertEq(distribution.amount, DISTRIBUTION_AMOUNT);
        assertEq(distribution.recipient, recipient1);
        assertEq(address(distribution.token), address(wETH));
        assertEq(distribution.claimDeadline, expectedDeadline);
        assertEq(distribution.payer, distributor);
        assertTrue(distribution.exists);
        assertTrue(escrow.isSoloDistribution(distributionIds[0]));
    }

    function test_distributeFromSender_multipleDistributions() public {
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](3);
        distributions[0] = Escrow.DistributionParams({
            amount: 500e18,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });
        distributions[1] = Escrow.DistributionParams({
            amount: 750e18,
            recipient: recipient2,
            claimPeriod: CLAIM_PERIOD * 2,
            token: wETH
        });
        distributions[2] = Escrow.DistributionParams({
            amount: 250e18,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD / 2,
            token: wETH
        });

        uint256 totalAmount = 500e18 + 750e18 + 250e18;
        uint256 initialDistributorBalance = wETH.balanceOf(distributor);

        vm.prank(distributor);
        uint[] memory distributionIds = escrow.distributeFromSender(distributions, "");

        assertEq(distributionIds.length, 3);
        assertEq(wETH.balanceOf(distributor), initialDistributorBalance - totalAmount);

        // Verify each distribution
        for (uint i = 0; i < 3; i++) {
            Escrow.Distribution memory distribution = escrow.getDistribution(distributionIds[i]);
            assertEq(distribution.amount, distributions[i].amount);
            assertEq(distribution.recipient, distributions[i].recipient);
            assertEq(distribution.claimDeadline, block.timestamp + distributions[i].claimPeriod);
            assertEq(distribution.payer, distributor);
            assertTrue(escrow.isSoloDistribution(distributionIds[i]));
        }
    }

    function test_distributeFromSender_multipleUsers() public {
        address distributor2 = makeAddr("distributor2");
        wETH.mint(distributor2, DISTRIBUTION_AMOUNT * 2);
        vm.prank(distributor2);
        wETH.approve(address(escrow), type(uint256).max);

        Escrow.DistributionParams[] memory distributions1 = new Escrow.DistributionParams[](1);
        distributions1[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        Escrow.DistributionParams[] memory distributions2 = new Escrow.DistributionParams[](1);
        distributions2[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT / 2,
            recipient: recipient2,
            claimPeriod: CLAIM_PERIOD * 2,
            token: wETH
        });

        // First distributor
        vm.prank(distributor);
        uint[] memory distributionIds1 = escrow.distributeFromSender(distributions1, "");

        // Second distributor
        vm.prank(distributor2);
        uint[] memory distributionIds2 = escrow.distributeFromSender(distributions2, "");

        // Verify distributions have different payers
        Escrow.Distribution memory dist1 = escrow.getDistribution(distributionIds1[0]);
        Escrow.Distribution memory dist2 = escrow.getDistribution(distributionIds2[0]);

        assertEq(dist1.payer, distributor);
        assertEq(dist2.payer, distributor2);
        assertEq(dist1.amount, DISTRIBUTION_AMOUNT);
        assertEq(dist2.amount, DISTRIBUTION_AMOUNT / 2);
    }

    function test_distributeFromSender_revert_batchLimitExceeded() public {
        uint256 batchLimit = escrow.batchLimit();
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](batchLimit + 1);
        
        for (uint i = 0; i < batchLimit + 1; i++) {
            distributions[i] = Escrow.DistributionParams({
                amount: 1e18,
                recipient: recipient1,
                claimPeriod: CLAIM_PERIOD,
                token: wETH
            });
        }

        expectRevert(Errors.BATCH_LIMIT_EXCEEDED);
        vm.prank(distributor);
        escrow.distributeFromSender(distributions, "");
    }

    function test_distributeFromSender_revert_invalidToken() public {
        MockERC20 nonWhitelistedToken = new MockERC20("Non-Whitelisted", "NWT", 18);
        nonWhitelistedToken.mint(distributor, DISTRIBUTION_AMOUNT);
        
        vm.prank(distributor);
        nonWhitelistedToken.approve(address(escrow), DISTRIBUTION_AMOUNT);
        
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: nonWhitelistedToken
        });

        expectRevert(Errors.INVALID_TOKEN);
        vm.prank(distributor);
        escrow.distributeFromSender(distributions, "");
    }

    function test_distributeFromSender_revert_zeroAmount() public {
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: 0,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        expectRevert(Errors.INVALID_AMOUNT);
        vm.prank(distributor);
        escrow.distributeFromSender(distributions, "");
    }

    function test_distributeFromSender_revert_invalidRecipient() public {
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: address(0),
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        expectRevert(Errors.INVALID_ADDRESS);
        vm.prank(distributor);
        escrow.distributeFromSender(distributions, "");
    }

    function test_distributeFromSender_revert_zeroClaimPeriod() public {
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: 0,
            token: wETH
        });

        expectRevert(Errors.INVALID_CLAIM_PERIOD);
        vm.prank(distributor);
        escrow.distributeFromSender(distributions, "");
    }

    function test_distributeFromSender_revert_insufficientBalance() public {
        address poorDistributor = makeAddr("poorDistributor");
        
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        expectRevert("TRANSFER_FROM_FAILED");
        vm.prank(poorDistributor);
        escrow.distributeFromSender(distributions, "");
    }

    function test_distributeFromSender_revert_insufficientAllowance() public {
        address nonApprovedDistributor = makeAddr("nonApprovedDistributor");
        wETH.mint(nonApprovedDistributor, DISTRIBUTION_AMOUNT);
        // Don't approve the escrow
        
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        expectRevert("TRANSFER_FROM_FAILED");
        vm.prank(nonApprovedDistributor);
        escrow.distributeFromSender(distributions, "");
    }

    function test_distributeFromSender_batchEvents() public {
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](2);
        distributions[0] = Escrow.DistributionParams({
            amount: 500e18,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });
        distributions[1] = Escrow.DistributionParams({
            amount: 300e18,
            recipient: recipient2,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        uint[] memory expectedDistributionIds = new uint[](2);
        expectedDistributionIds[0] = escrow.distributionCount();
        expectedDistributionIds[1] = escrow.distributionCount() + 1;

        vm.expectEmit(true, true, true, true);
        emit DistributedFromSenderBatch(0, expectedDistributionIds, "");

        vm.prank(distributor);
        escrow.distributeFromSender(distributions, "");
    }

    function test_distributeFromSender_distributionCounter() public {
        uint256 initialCount = escrow.distributionCount();

        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](3);
        for (uint i = 0; i < 3; i++) {
            distributions[i] = Escrow.DistributionParams({
                amount: 100e18,
                recipient: recipient1,
                claimPeriod: CLAIM_PERIOD,
                token: wETH
            });
        }

        vm.prank(distributor);
        uint[] memory distributionIds = escrow.distributeFromSender(distributions, "");

        assertEq(escrow.distributionCount(), initialCount + 3);
        assertEq(distributionIds[0], initialCount);
        assertEq(distributionIds[1], initialCount + 1);
        assertEq(distributionIds[2], initialCount + 2);
    }

    function test_distributeFromSender_batchCounter() public {
        uint256 initialBatchCount = escrow.distributionBatchCount();

        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        vm.prank(distributor);
        escrow.distributeFromSender(distributions, "");

        assertEq(escrow.distributionBatchCount(), initialBatchCount + 1);
    }

    function test_distributeFromSender_fuzz_amounts(uint256 amount1, uint256 amount2) public {
        uint256 maxAmount = wETH.balanceOf(distributor) / 2;
        vm.assume(amount1 > 0 && amount1 <= maxAmount);
        vm.assume(amount2 > 0 && amount2 <= maxAmount);

        // Add validation for fee edge case - ensure amounts are large enough
        uint256 currentFee = escrow.fee();
        if (currentFee > 0) {
            // Ensure amounts are large enough to handle fees
            // For 10% max fee, amounts should be at least 100 to avoid fee >= amount
            vm.assume(amount1 >= 100);
            vm.assume(amount2 >= 100);
        }

        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](2);
        distributions[0] = Escrow.DistributionParams({
            amount: amount1,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });
        distributions[1] = Escrow.DistributionParams({
            amount: amount2,
            recipient: recipient2,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        uint256 initialBalance = wETH.balanceOf(distributor);

        vm.prank(distributor);
        uint[] memory distributionIds = escrow.distributeFromSender(distributions, "");

        assertEq(distributionIds.length, 2);
        assertEq(wETH.balanceOf(distributor), initialBalance - amount1 - amount2);

        Escrow.Distribution memory dist1 = escrow.getDistribution(distributionIds[0]);
        Escrow.Distribution memory dist2 = escrow.getDistribution(distributionIds[1]);
        
        assertEq(dist1.amount, amount1);
        assertEq(dist2.amount, amount2);
        assertEq(dist1.payer, distributor);
        assertEq(dist2.payer, distributor);
    }

    function test_distributeFromSender_fuzz_claimPeriods(uint32 claimPeriod) public {
        vm.assume(claimPeriod > 0 && claimPeriod <= 365 days);

        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: claimPeriod,
            token: wETH
        });

        vm.prank(distributor);
        uint[] memory distributionIds = escrow.distributeFromSender(distributions, "");

        Escrow.Distribution memory distribution = escrow.getDistribution(distributionIds[0]);
        assertEq(distribution.claimDeadline, block.timestamp + claimPeriod);
    }

    function test_distributeFromSender_emptyDistributions() public {
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](0);

        vm.prank(distributor);
        uint[] memory distributionIds = escrow.distributeFromSender(distributions, "");

        assertEq(distributionIds.length, 0);
    }

    function test_distributeFromSender_maxBatchLimit() public {
        uint256 batchLimit = escrow.batchLimit();
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](batchLimit);
        
        for (uint i = 0; i < batchLimit; i++) {
            distributions[i] = Escrow.DistributionParams({
                amount: 1e18,
                recipient: recipient1,
                claimPeriod: CLAIM_PERIOD,
                token: wETH
            });
        }

        vm.prank(distributor);
        uint[] memory distributionIds = escrow.distributeFromSender(distributions, "");

        assertEq(distributionIds.length, batchLimit);
    }

    /* -------------------------------------------------------------------------- */
    /*                             FEE EDGE CASE TESTS                           */
    /* -------------------------------------------------------------------------- */

    function test_distributeFromSender_revert_feeExceedsAmount_maxFee() public {
        // Set fee to maximum (10%)
        vm.prank(owner);
        escrow.setFee(1000); // 10%
        
        // Create distribution where fee would equal or exceed amount
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: 9, // 9 wei - with 10% fee rounded up, fee would be 1 wei, leaving 8 wei
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        // Give distributor minimal tokens for this test
        wETH.mint(distributor, 100);

        // This should succeed as 9 > 1 (fee)
        vm.prank(distributor);
        uint[] memory distributionIds = escrow.distributeFromSender(distributions, "");
        assertEq(distributionIds.length, 1);
    }

    function test_distributeFromSender_revert_feeExceedsAmount_edgeCase() public {
        // Set fee to maximum (10%)
        vm.prank(owner);
        escrow.setFee(1000); // 10%
        
        // Create distribution where mulDivUp would make fee >= amount
        // For amount = 1: fee = mulDivUp(1, 1000, 10000) = (1 * 1000 + 9999) / 10000 = 1
        // This would leave netAmount = 1 - 1 = 0, which should be prevented
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: 1, // 1 wei - fee would be 1 wei, leaving 0 for recipient
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        // Give distributor minimal tokens for this test
        wETH.mint(distributor, 100);

        expectRevert(Errors.INVALID_AMOUNT);
        vm.prank(distributor);
        escrow.distributeFromSender(distributions, "");
    }

    function test_distributeFromSender_revert_feeExceedsAmount_smallAmounts() public {
        // Set moderate fee (2.5%)
        vm.prank(owner);
        escrow.setFee(250); // 2.5%
        
        // Give distributor minimal tokens for this test
        wETH.mint(distributor, 1000);

        // Test amount = 1 (should fail because fee = mulDivUp(1, 250, 10000) = 1, leaving 0)
        Escrow.DistributionParams[] memory distributions1 = new Escrow.DistributionParams[](1);
        distributions1[0] = Escrow.DistributionParams({
            amount: 1,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        expectRevert(Errors.INVALID_AMOUNT);
        vm.prank(distributor);
        escrow.distributeFromSender(distributions1, "");

        // Test amount = 40 (should succeed: fee = mulDivUp(40, 250, 10000) = 1, leaving 39)
        Escrow.DistributionParams[] memory distributions2 = new Escrow.DistributionParams[](1);
        distributions2[0] = Escrow.DistributionParams({
            amount: 40,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        vm.prank(distributor);
        uint[] memory distributionIds = escrow.distributeFromSender(distributions2, "");
        assertEq(distributionIds.length, 1);
    }

    function test_distributeFromSender_fuzz_feeValidation(uint256 amount, uint256 feeRate) public {
        // Bound inputs to reasonable ranges
        vm.assume(amount > 0 && amount <= 1000e18);
        vm.assume(feeRate <= 1000); // Max 10% fee
        
        // Give distributor enough tokens
        wETH.mint(distributor, amount + 1000e18);
        
        // Set the fee rate
        vm.prank(owner);
        escrow.setFee(feeRate);
        
        // Calculate expected fee using same logic as contract
        uint256 expectedFee = (amount * feeRate + 9999) / 10000; // mulDivUp equivalent
        
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: amount,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        if (expectedFee >= amount) {
            // Should revert if fee would consume entire amount
            expectRevert(Errors.INVALID_AMOUNT);
            vm.prank(distributor);
            escrow.distributeFromSender(distributions, "");
        } else {
            // Should succeed if recipient gets at least 1 wei
            vm.prank(distributor);
            uint[] memory distributionIds = escrow.distributeFromSender(distributions, "");
            assertEq(distributionIds.length, 1);
            
            Escrow.Distribution memory distribution = escrow.getDistribution(distributionIds[0]);
            assertEq(distribution.amount, amount);
            assertEq(distribution.payer, distributor);
        }
    }

    function test_distributeFromSender_minimumAmountForFee() public {
        // Test minimum amounts needed for various fee rates
        uint256[] memory feeRates = new uint256[](4);
        feeRates[0] = 100; // 1%
        feeRates[1] = 250; // 2.5%
        feeRates[2] = 500; // 5%
        feeRates[3] = 1000; // 10%
        
        // Calculate minimum amounts that would leave at least 1 wei for recipient
        uint256[] memory minAmounts = new uint256[](4);
        minAmounts[0] = 100; // For 1%: fee = mulDivUp(100, 100, 10000) = 1, leaving 99
        minAmounts[1] = 40;  // For 2.5%: fee = mulDivUp(40, 250, 10000) = 1, leaving 39
        minAmounts[2] = 20;  // For 5%: fee = mulDivUp(20, 500, 10000) = 1, leaving 19
        minAmounts[3] = 10;  // For 10%: fee = mulDivUp(10, 1000, 10000) = 1, leaving 9
        
        // Give distributor enough tokens
        wETH.mint(distributor, 10000);
        
        for (uint i = 0; i < feeRates.length; i++) {
            vm.prank(owner);
            escrow.setFee(feeRates[i]);
            
            Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
            distributions[0] = Escrow.DistributionParams({
                amount: minAmounts[i],
                recipient: recipient1,
                claimPeriod: CLAIM_PERIOD,
                token: wETH
            });
            
            vm.prank(distributor);
            uint[] memory distributionIds = escrow.distributeFromSender(distributions, "");
            assertEq(distributionIds.length, 1);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                          FEE SNAPSHOT MECHANISM TESTS                     */
    /* -------------------------------------------------------------------------- */

    function test_distributeFromSender_feeSnapshotAtCreation() public {
        // Test that fee is correctly snapshotted at distribution creation time
        vm.prank(owner);
        escrow.setFee(600); // 6%

        wETH.mint(distributor, 1000e18);

        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: 1000e18,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        vm.prank(distributor);
        uint[] memory distributionIds = escrow.distributeFromSender(distributions, "");

        // Check that the distribution stores the correct fee
        Escrow.Distribution memory distribution = escrow.getDistribution(distributionIds[0]);
        assertEq(distribution.fee, 600, "Fee should be snapshotted at creation time");
    }

    function test_distributeFromSender_differentFeesForDifferentDistributions() public {
        // Test that distributions created at different times can have different fees
        wETH.mint(distributor, 5000e18);

        // Create first distribution with 3% fee
        vm.prank(owner);
        escrow.setFee(300);
        
        Escrow.DistributionParams[] memory distributions1 = new Escrow.DistributionParams[](1);
        distributions1[0] = Escrow.DistributionParams({
            amount: 1000e18,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        vm.prank(distributor);
        uint[] memory distributionIds1 = escrow.distributeFromSender(distributions1, "");

        // Change fee and create second distribution with 7% fee
        vm.prank(owner);
        escrow.setFee(700);
        
        Escrow.DistributionParams[] memory distributions2 = new Escrow.DistributionParams[](1);
        distributions2[0] = Escrow.DistributionParams({
            amount: 2000e18,
            recipient: recipient2,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        vm.prank(distributor);
        uint[] memory distributionIds2 = escrow.distributeFromSender(distributions2, "");

        // Check that each distribution has its respective fee
        Escrow.Distribution memory dist1 = escrow.getDistribution(distributionIds1[0]);
        Escrow.Distribution memory dist2 = escrow.getDistribution(distributionIds2[0]);
        
        assertEq(dist1.fee, 300, "First distribution should have 3% fee");
        assertEq(dist2.fee, 700, "Second distribution should have 7% fee");
    }

    function test_distributeFromSender_zeroFeeSnapshot() public {
        // Test that zero fees are correctly snapshotted
        vm.prank(owner);
        escrow.setFee(0); // 0% fee

        wETH.mint(distributor, 1000e18);

        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: 1000e18,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        vm.prank(distributor);
        uint[] memory distributionIds = escrow.distributeFromSender(distributions, "");

        Escrow.Distribution memory distribution = escrow.getDistribution(distributionIds[0]);
        assertEq(distribution.fee, 0, "Zero fee should be correctly snapshotted");
    }

    function test_distributeFromSender_maxFeeSnapshot() public {
        // Test that maximum fees are correctly snapshotted
        vm.prank(owner);
        escrow.setFee(1000); // 10% (maximum) fee

        wETH.mint(distributor, 1000e18);

        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: 1000e18,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        vm.prank(distributor);
        uint[] memory distributionIds = escrow.distributeFromSender(distributions, "");

        Escrow.Distribution memory distribution = escrow.getDistribution(distributionIds[0]);
        assertEq(distribution.fee, 1000, "Maximum fee should be correctly snapshotted");
    }

    function test_distributeFromSender_batchDistributionsSameFeeSnapshot() public {
        // Test that all distributions in a batch get the same fee snapshot
        vm.prank(owner);
        escrow.setFee(400); // 4%

        wETH.mint(distributor, 5000e18);

        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](3);
        distributions[0] = Escrow.DistributionParams({
            amount: 1000e18,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });
        distributions[1] = Escrow.DistributionParams({
            amount: 1500e18,
            recipient: recipient2,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });
        distributions[2] = Escrow.DistributionParams({
            amount: 2000e18,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        vm.prank(distributor);
        uint[] memory distributionIds = escrow.distributeFromSender(distributions, "");

        // All distributions should have the same fee
        for (uint i = 0; i < distributionIds.length; i++) {
            Escrow.Distribution memory distribution = escrow.getDistribution(distributionIds[i]);
            assertEq(distribution.fee, 400, "All distributions in batch should have same fee");
        }
    }

    function test_distributeFromSender_feeChangeAfterCreationDoesNotAffect() public {
        // Test that changing fee after creation doesn't affect existing distributions
        vm.prank(owner);
        escrow.setFee(150); // 1.5%

        wETH.mint(distributor, 1000e18);

        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: 1000e18,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        vm.prank(distributor);
        uint[] memory distributionIds = escrow.distributeFromSender(distributions, "");

        // Change fee after creation
        vm.prank(owner);
        escrow.setFee(850); // 8.5%

        // Check that existing distribution still has original fee
        Escrow.Distribution memory distribution = escrow.getDistribution(distributionIds[0]);
        assertEq(distribution.fee, 150, "Existing distribution should retain original fee");
        
        // Verify global fee did change
        assertEq(escrow.fee(), 850, "Global fee should have changed");
    }

    function test_distributeFromSender_multiplePayers_differentFees() public {
        // Test that different payers can create distributions with different fees
        address payer1 = makeAddr("payer1");
        address payer2 = makeAddr("payer2");
        
        wETH.mint(payer1, 1000e18);
        wETH.mint(payer2, 1000e18);
        
        vm.prank(payer1);
        wETH.approve(address(escrow), 1000e18);
        vm.prank(payer2);
        wETH.approve(address(escrow), 1000e18);

        // Payer1 creates distribution with 2% fee
        vm.prank(owner);
        escrow.setFee(200);
        
        Escrow.DistributionParams[] memory distributions1 = new Escrow.DistributionParams[](1);
        distributions1[0] = Escrow.DistributionParams({
            amount: 500e18,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        vm.prank(payer1);
        uint[] memory distributionIds1 = escrow.distributeFromSender(distributions1, "");

        // Change fee, then payer2 creates distribution with 9% fee
        vm.prank(owner);
        escrow.setFee(900);
        
        Escrow.DistributionParams[] memory distributions2 = new Escrow.DistributionParams[](1);
        distributions2[0] = Escrow.DistributionParams({
            amount: 500e18,
            recipient: recipient2,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        vm.prank(payer2);
        uint[] memory distributionIds2 = escrow.distributeFromSender(distributions2, "");

        // Check that each payer's distribution has the fee that was active when they created it
        Escrow.Distribution memory dist1 = escrow.getDistribution(distributionIds1[0]);
        Escrow.Distribution memory dist2 = escrow.getDistribution(distributionIds2[0]);
        
        assertEq(dist1.fee, 200, "Payer1's distribution should have 2% fee");
        assertEq(dist2.fee, 900, "Payer2's distribution should have 9% fee");
        assertEq(dist1.payer, payer1, "First distribution should track correct payer");
        assertEq(dist2.payer, payer2, "Second distribution should track correct payer");
    }

    /* -------------------------------------------------------------------------- */
    /*                                    EVENTS                                  */
    /* -------------------------------------------------------------------------- */
    
    event DistributedFromSender(
        uint256 indexed distributionId,
        address indexed payer,
        address indexed recipient,
        address token,
        uint256 amount,
        uint256 claimDeadline
    );

    event DistributedFromSenderBatch(
        uint256 indexed distributionBatchId,
        uint256[] distributionIds,
        bytes data
    );
} 