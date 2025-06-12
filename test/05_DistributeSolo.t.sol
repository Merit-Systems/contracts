// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "./00_Escrow.t.sol";

contract DistributeSolo_Test is Base_Test {
    
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

    function test_distributeSolo_success() public {
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
        emit DistributedSolo(0, distributor, recipient1, address(wETH), DISTRIBUTION_AMOUNT, expectedDeadline);

        vm.prank(distributor);
        uint[] memory distributionIds = escrow.distributeSolo(distributions);

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

    function test_distributeSolo_multipleDistributions() public {
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
        uint[] memory distributionIds = escrow.distributeSolo(distributions);

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

    function test_distributeSolo_multipleUsers() public {
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
        uint[] memory distributionIds1 = escrow.distributeSolo(distributions1);

        // Second distributor
        vm.prank(distributor2);
        uint[] memory distributionIds2 = escrow.distributeSolo(distributions2);

        // Verify distributions have different payers
        Escrow.Distribution memory dist1 = escrow.getDistribution(distributionIds1[0]);
        Escrow.Distribution memory dist2 = escrow.getDistribution(distributionIds2[0]);

        assertEq(dist1.payer, distributor);
        assertEq(dist2.payer, distributor2);
        assertEq(dist1.amount, DISTRIBUTION_AMOUNT);
        assertEq(dist2.amount, DISTRIBUTION_AMOUNT / 2);
    }

    function test_distributeSolo_revert_batchLimitExceeded() public {
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
        escrow.distributeSolo(distributions);
    }

    function test_distributeSolo_revert_invalidToken() public {
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
        escrow.distributeSolo(distributions);
    }

    function test_distributeSolo_revert_zeroAmount() public {
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: 0,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        expectRevert(Errors.INVALID_AMOUNT);
        vm.prank(distributor);
        escrow.distributeSolo(distributions);
    }

    function test_distributeSolo_revert_invalidRecipient() public {
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: address(0),
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        expectRevert(Errors.INVALID_ADDRESS);
        vm.prank(distributor);
        escrow.distributeSolo(distributions);
    }

    function test_distributeSolo_revert_zeroClaimPeriod() public {
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: 0,
            token: wETH
        });

        expectRevert(Errors.INVALID_CLAIM_PERIOD);
        vm.prank(distributor);
        escrow.distributeSolo(distributions);
    }

    function test_distributeSolo_revert_insufficientBalance() public {
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
        escrow.distributeSolo(distributions);
    }

    function test_distributeSolo_revert_insufficientAllowance() public {
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
        escrow.distributeSolo(distributions);
    }

    function test_distributeSolo_batchEvents() public {
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
        emit DistributedSoloBatch(0, expectedDistributionIds);

        vm.prank(distributor);
        escrow.distributeSolo(distributions);
    }

    function test_distributeSolo_distributionCounter() public {
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
        uint[] memory distributionIds = escrow.distributeSolo(distributions);

        assertEq(escrow.distributionCount(), initialCount + 3);
        assertEq(distributionIds[0], initialCount);
        assertEq(distributionIds[1], initialCount + 1);
        assertEq(distributionIds[2], initialCount + 2);
    }

    function test_distributeSolo_batchCounter() public {
        uint256 initialBatchCount = escrow.distributionBatchCount();

        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        vm.prank(distributor);
        escrow.distributeSolo(distributions);

        assertEq(escrow.distributionBatchCount(), initialBatchCount + 1);
    }

    function test_distributeSolo_fuzz_amounts(uint256 amount1, uint256 amount2) public {
        uint256 maxAmount = wETH.balanceOf(distributor) / 2;
        vm.assume(amount1 > 0 && amount1 <= maxAmount);
        vm.assume(amount2 > 0 && amount2 <= maxAmount);

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
        uint[] memory distributionIds = escrow.distributeSolo(distributions);

        assertEq(distributionIds.length, 2);
        assertEq(wETH.balanceOf(distributor), initialBalance - amount1 - amount2);

        Escrow.Distribution memory dist1 = escrow.getDistribution(distributionIds[0]);
        Escrow.Distribution memory dist2 = escrow.getDistribution(distributionIds[1]);
        
        assertEq(dist1.amount, amount1);
        assertEq(dist2.amount, amount2);
        assertEq(dist1.payer, distributor);
        assertEq(dist2.payer, distributor);
    }

    function test_distributeSolo_fuzz_claimPeriods(uint32 claimPeriod) public {
        vm.assume(claimPeriod > 0 && claimPeriod <= 365 days);

        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: claimPeriod,
            token: wETH
        });

        vm.prank(distributor);
        uint[] memory distributionIds = escrow.distributeSolo(distributions);

        Escrow.Distribution memory distribution = escrow.getDistribution(distributionIds[0]);
        assertEq(distribution.claimDeadline, block.timestamp + claimPeriod);
    }

    function test_distributeSolo_emptyDistributions() public {
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](0);

        vm.prank(distributor);
        uint[] memory distributionIds = escrow.distributeSolo(distributions);

        assertEq(distributionIds.length, 0);
    }

    function test_distributeSolo_maxBatchLimit() public {
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
        uint[] memory distributionIds = escrow.distributeSolo(distributions);

        assertEq(distributionIds.length, batchLimit);
    }

    /* -------------------------------------------------------------------------- */
    /*                                    EVENTS                                  */
    /* -------------------------------------------------------------------------- */
    
    event DistributedSolo(
        uint256 indexed distributionId,
        address indexed payer,
        address indexed recipient,
        address token,
        uint256 amount,
        uint256 claimDeadline
    );

    event DistributedSoloBatch(
        uint256 indexed distributionBatchId,
        uint256[] distributionIds
    );
} 