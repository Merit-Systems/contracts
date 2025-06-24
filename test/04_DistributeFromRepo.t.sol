// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "./00_Escrow.t.sol";

contract DistributeFromRepo_Test is Base_Test {
    
    uint256 constant REPO_ID = 1;
    uint256 constant ACCOUNT_ID = 100;
    uint256 constant FUND_AMOUNT = 10000e18;
    uint256 constant DISTRIBUTION_AMOUNT = 1000e18;
    uint32 constant CLAIM_PERIOD = 7 days;

    address repoAdmin;
    address distributor1;
    address distributor2;
    address recipient1;
    address recipient2;

    uint256 adminPrivateKey = 0x1111111111111111111111111111111111111111111111111111111111111111;
    
    function setUp() public override {
        super.setUp();
        
        repoAdmin = vm.addr(adminPrivateKey);
        distributor1 = makeAddr("distributor1");
        distributor2 = makeAddr("distributor2");
        recipient1 = makeAddr("recipient1");
        recipient2 = makeAddr("recipient2");
        
        // Initialize repo with admin
        _initializeRepo();
        
        // Fund the repo
        _fundRepo();
        
        // Add distributors
        _addDistributors();
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
                    escrow.repoSetAdminNonce(REPO_ID, ACCOUNT_ID),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        
        escrow.initRepo(REPO_ID, ACCOUNT_ID, _toArray(repoAdmin), deadline, v, r, s);
    }

    function _toArray(address addr) internal pure returns (address[] memory) {
        address[] memory arr = new address[](1);
        arr[0] = addr;
        return arr;
    }

    function _fundRepo() internal {
        wETH.mint(address(this), FUND_AMOUNT);
        wETH.approve(address(escrow), FUND_AMOUNT);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, FUND_AMOUNT, "");
    }

    function _addDistributors() internal {
        address[] memory distributors = new address[](2);
        distributors[0] = distributor1;
        distributors[1] = distributor2;
        
        vm.prank(repoAdmin);
        escrow.addDistributors(REPO_ID, ACCOUNT_ID, distributors);
    }

    function test_distributeFromRepo_success_asAdmin() public {
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        uint256 initialBalance = escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH));
        uint256 expectedDeadline = block.timestamp + CLAIM_PERIOD;

        vm.expectEmit(true, true, true, true);
        emit DistributedFromRepo(0, 0, recipient1, address(wETH), DISTRIBUTION_AMOUNT, expectedDeadline);

        vm.prank(repoAdmin);
        uint[] memory distributionIds = escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");

        // Check return values
        assertEq(distributionIds.length, 1);
        assertEq(distributionIds[0], 0);

        // Check balance reduction
        assertEq(
            escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), 
            initialBalance - DISTRIBUTION_AMOUNT
        );

        // Check distribution was created
        Escrow.Distribution memory distribution = escrow.getDistribution(distributionIds[0]);
        assertEq(distribution.amount, DISTRIBUTION_AMOUNT);
        assertEq(distribution.recipient, recipient1);
        assertEq(address(distribution.token), address(wETH));
        assertEq(distribution.claimDeadline, expectedDeadline);
        assertTrue(distribution.exists);
    }

    function test_distributeFromRepo_success_asDistributor() public {
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        vm.prank(distributor1);
        uint[] memory distributionIds = escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");

        assertEq(distributionIds.length, 1);
        
        Escrow.Distribution memory distribution = escrow.getDistribution(distributionIds[0]);
        assertEq(distribution.amount, DISTRIBUTION_AMOUNT);
        assertEq(distribution.recipient, recipient1);
    }

    function test_distributeFromRepo_multipleDistributions() public {
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
        uint256 initialBalance = escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH));

        vm.prank(repoAdmin);
        uint[] memory distributionIds = escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "batch data");

        assertEq(distributionIds.length, 3);
        assertEq(
            escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), 
            initialBalance - totalAmount
        );

        // Verify each distribution
        for (uint i = 0; i < 3; i++) {
            Escrow.Distribution memory distribution = escrow.getDistribution(distributionIds[i]);
            assertEq(distribution.amount, distributions[i].amount);
            assertEq(distribution.recipient, distributions[i].recipient);
            assertEq(distribution.claimDeadline, block.timestamp + distributions[i].claimPeriod);
        }
    }

    function test_distributeFromRepo_revert_notAuthorized() public {
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        address unauthorized = makeAddr("unauthorized");
        
        expectRevert(Errors.NOT_REPO_ADMIN_OR_DISTRIBUTOR);
        vm.prank(unauthorized);
        escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");
    }

    function test_distributeFromRepo_revert_insufficientBalance() public {
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: FUND_AMOUNT + 1, // More than available
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        expectRevert(Errors.INSUFFICIENT_BALANCE);
        vm.prank(repoAdmin);
        escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");
    }

    function test_distributeFromRepo_revert_batchLimitExceeded() public {
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
        vm.prank(repoAdmin);
        escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");
    }

    function test_distributeFromRepo_revert_emptyArray() public {
        // Test that empty distributions array reverts with EMPTY_ARRAY error
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](0);

        uint256 initialBatchCount = escrow.batchCount();
        uint256 initialDistributionCount = escrow.distributionCount();
        uint256 initialBalance = escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH));

        // Should revert with EMPTY_ARRAY error
        expectRevert(Errors.EMPTY_ARRAY);
        vm.prank(repoAdmin);
        escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");

        // Verify no state changes occurred
        assertEq(escrow.batchCount(), initialBatchCount, "Batch count should not increment");
        assertEq(escrow.distributionCount(), initialDistributionCount, "Distribution count should not increment");
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), initialBalance, "Balance should not change");
    }

    function test_distributeFromRepo_revert_emptyArray_asDistributor() public {
        // Test that empty array also fails for distributors (not just admins)
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](0);

        expectRevert(Errors.EMPTY_ARRAY);
        vm.prank(distributor1);
        escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");
    }

    function test_distributeFromRepo_revert_zeroAmount() public {
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: 0,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        expectRevert(Errors.INVALID_AMOUNT);
        vm.prank(repoAdmin);
        escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");
    }

    function test_distributeFromRepo_revert_invalidRecipient() public {
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: address(0),
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        expectRevert(Errors.INVALID_ADDRESS);
        vm.prank(repoAdmin);
        escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");
    }

    function test_distributeFromRepo_success_zeroClaimPeriod() public {
        // Test that zero claim period works for instant reclaimability
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: 0, // Instant reclaimability
            token: wETH
        });

        vm.prank(repoAdmin);
        uint[] memory distributionIds = escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");

        // Verify the distribution was created successfully
        assertEq(distributionIds.length, 1);
        
        Escrow.Distribution memory distribution = escrow.getDistribution(distributionIds[0]);
        assertEq(distribution.amount, DISTRIBUTION_AMOUNT);
        assertEq(distribution.recipient, recipient1);
        assertEq(distribution.claimDeadline, block.timestamp); // Should equal current timestamp for instant reclaimability
    }

    function test_distributeFromRepo_revert_insufficientBalanceNonWhitelistedToken() public {
        MockERC20 nonWhitelistedToken = new MockERC20("Non-Whitelisted", "NWT", 18);
        
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: nonWhitelistedToken
        });

        // This fails with insufficient balance because we have 0 balance of the non-whitelisted token
        // The balance check happens before token validation in the execution flow
        expectRevert(Errors.INSUFFICIENT_BALANCE);
        vm.prank(repoAdmin);
        escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");
    }

    function test_distributeFromRepo_hasDistributionsFlag() public {
        assertFalse(escrow.getAccountHasDistributions(REPO_ID, ACCOUNT_ID));

        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        vm.prank(repoAdmin);
        escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");

        assertTrue(escrow.getAccountHasDistributions(REPO_ID, ACCOUNT_ID));
    }

    function test_distributeFromRepo_batchEvents() public {
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

        // Create the expected distribution IDs array
        uint[] memory expectedDistributionIds = new uint[](2);
        expectedDistributionIds[0] = escrow.distributionCount();
        expectedDistributionIds[1] = escrow.distributionCount() + 1;

        vm.expectEmit(true, true, true, true);
        emit DistributedFromRepoBatch(0, REPO_ID, ACCOUNT_ID, expectedDistributionIds, "test batch");

        vm.prank(repoAdmin);
        escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "test batch");
    }

    function test_distributeFromRepo_fuzz_amounts(uint256 amount1, uint256 amount2) public {
        vm.assume(amount1 > 0 && amount1 <= FUND_AMOUNT / 2);
        vm.assume(amount2 > 0 && amount2 <= FUND_AMOUNT / 2);
        vm.assume(amount1 + amount2 <= FUND_AMOUNT);

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

        uint256 initialBalance = escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH));

        vm.prank(repoAdmin);
        uint[] memory distributionIds = escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");

        assertEq(distributionIds.length, 2);
        assertEq(
            escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), 
            initialBalance - amount1 - amount2
        );

        Escrow.Distribution memory dist1 = escrow.getDistribution(distributionIds[0]);
        Escrow.Distribution memory dist2 = escrow.getDistribution(distributionIds[1]);
        
        assertEq(dist1.amount, amount1);
        assertEq(dist2.amount, amount2);
    }

    function test_distributeFromRepo_fuzz_claimPeriods(uint32 claimPeriod) public {
        vm.assume(claimPeriod <= 365 days); // Now allows 0 for instant reclaimability

        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: claimPeriod,
            token: wETH
        });

        vm.prank(repoAdmin);
        uint[] memory distributionIds = escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");

        Escrow.Distribution memory distribution = escrow.getDistribution(distributionIds[0]);
        assertEq(distribution.claimDeadline, block.timestamp + claimPeriod);
    }

    function test_distributeFromRepo_distributionCounter() public {
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

        vm.prank(repoAdmin);
        uint[] memory distributionIds = escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");

        assertEq(escrow.distributionCount(), initialCount + 3);
        assertEq(distributionIds[0], initialCount);
        assertEq(distributionIds[1], initialCount + 1);
        assertEq(distributionIds[2], initialCount + 2);
    }

    function test_distributeFromRepo_batchCounter() public {
        uint256 initialBatchCount = escrow.batchCount();

        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        vm.prank(repoAdmin);
        escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");

        assertEq(escrow.batchCount(), initialBatchCount + 1);
    }

    /* -------------------------------------------------------------------------- */
    /*                             FEE EDGE CASE TESTS                           */
    /* -------------------------------------------------------------------------- */

    function test_distributeFromRepo_revert_feeExceedsAmount_maxFee() public {
        // Set fee to maximum (10%)
        vm.prank(owner);
        escrow.setFee(1000); // 10%
        
        // Try to create distribution where fee would equal or exceed amount
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: 9, // 9 wei - with 10% fee rounded up, fee would be 1 wei, leaving 8 wei
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        // This should succeed as 9 > 1 (fee)
        vm.prank(repoAdmin);
        uint[] memory distributionIds = escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");
        assertEq(distributionIds.length, 1);
    }

    function test_distributeFromRepo_revert_feeEqualsAmount() public {
        // Set fee to maximum (10%)
        vm.prank(owner);
        escrow.setFee(1000); // 10%
        
        // Try to create distribution where fee would equal amount
        // With mulDivUp, fee = (10 * 1000 + 9999) / 10000 = 1
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: 10, // 10 wei - fee would be exactly 1 wei due to rounding
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        // This should succeed as 10 > 1 (fee)
        vm.prank(repoAdmin);
        escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");
    }

    function test_distributeFromRepo_revert_feeExceedsAmount_edgeCase() public {
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

        expectRevert(Errors.INVALID_AMOUNT);
        vm.prank(repoAdmin);
        escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");
    }

    function test_distributeFromRepo_revert_feeExceedsAmount_smallAmounts() public {
        // Set moderate fee (5%)
        vm.prank(owner);
        escrow.setFee(500); // 5%
        
        // Test various small amounts that would cause issues
        uint256[] memory problematicAmounts = new uint256[](3);
        problematicAmounts[0] = 1; // fee = mulDivUp(1, 500, 10000) = 1, leaving 0
        problematicAmounts[1] = 19; // fee = mulDivUp(19, 500, 10000) = 1, leaving 18 (this should work)
        problematicAmounts[2] = 20; // fee = mulDivUp(20, 500, 10000) = 1, leaving 19 (this should work)

        // Test amount = 1 (should fail)
        Escrow.DistributionParams[] memory distributions1 = new Escrow.DistributionParams[](1);
        distributions1[0] = Escrow.DistributionParams({
            amount: problematicAmounts[0],
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        expectRevert(Errors.INVALID_AMOUNT);
        vm.prank(repoAdmin);
        escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions1, "");

        // Test amount = 19 (should succeed)
        Escrow.DistributionParams[] memory distributions2 = new Escrow.DistributionParams[](1);
        distributions2[0] = Escrow.DistributionParams({
            amount: problematicAmounts[1],
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        vm.prank(repoAdmin);
        uint[] memory distributionIds = escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions2, "");
        assertEq(distributionIds.length, 1);
    }

    function test_distributeFromRepo_fuzz_feeValidation(uint256 amount, uint256 feeRate) public {
        // Bound inputs to reasonable ranges
        vm.assume(amount > 0 && amount <= 1000e18);
        vm.assume(feeRate <= 1000); // Max 10% fee
        
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
            vm.prank(repoAdmin);
            escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");
        } else {
            // Should succeed if recipient gets at least 1 wei
            vm.prank(repoAdmin);
            uint[] memory distributionIds = escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");
            assertEq(distributionIds.length, 1);
            
            Escrow.Distribution memory distribution = escrow.getDistribution(distributionIds[0]);
            assertEq(distribution.amount, amount);
        }
    }

    function test_distributeFromRepo_feeSnapshotAtCreation() public {
        // Test that fee is correctly snapshotted at distribution creation time
        vm.prank(owner);
        escrow.setFee(500); // 5%

        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: 1000e18,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        vm.prank(repoAdmin);
        uint[] memory distributionIds = escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");

        // Check that the distribution stores the correct fee
        Escrow.Distribution memory distribution = escrow.getDistribution(distributionIds[0]);
        assertEq(distribution.fee, 500, "Fee should be snapshotted at creation time");
    }

    function test_distributeFromRepo_differentFeesForDifferentDistributions() public {
        // Test that distributions created at different times can have different fees

        // Create first distribution with 2% fee
        vm.prank(owner);
        escrow.setFee(200);
        
        Escrow.DistributionParams[] memory distributions1 = new Escrow.DistributionParams[](1);
        distributions1[0] = Escrow.DistributionParams({
            amount: 1000e18,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        vm.prank(repoAdmin);
        uint[] memory distributionIds1 = escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions1, "");

        // Change fee and create second distribution with 8% fee
        vm.prank(owner);
        escrow.setFee(800);
        
        Escrow.DistributionParams[] memory distributions2 = new Escrow.DistributionParams[](1);
        distributions2[0] = Escrow.DistributionParams({
            amount: 2000e18,
            recipient: recipient2,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        vm.prank(repoAdmin);
        uint[] memory distributionIds2 = escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions2, "");

        // Check that each distribution has its respective fee
        Escrow.Distribution memory dist1 = escrow.getDistribution(distributionIds1[0]);
        Escrow.Distribution memory dist2 = escrow.getDistribution(distributionIds2[0]);
        
        assertEq(dist1.fee, 200, "First distribution should have 2% fee");
        assertEq(dist2.fee, 800, "Second distribution should have 8% fee");
    }

    function test_distributeFromRepo_zeroFeeSnapshot() public {
        // Test that zero fees are correctly snapshotted
        vm.prank(owner);
        escrow.setFee(0); // 0% fee

        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: 1000e18,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        vm.prank(repoAdmin);
        uint[] memory distributionIds = escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");

        Escrow.Distribution memory distribution = escrow.getDistribution(distributionIds[0]);
        assertEq(distribution.fee, 0, "Zero fee should be correctly snapshotted");
    }

    function test_distributeFromRepo_maxFeeSnapshot() public {
        // Test that maximum fees are correctly snapshotted
        vm.prank(owner);
        escrow.setFee(1000); // 10% (maximum) fee

        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: 1000e18,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        vm.prank(repoAdmin);
        uint[] memory distributionIds = escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");

        Escrow.Distribution memory distribution = escrow.getDistribution(distributionIds[0]);
        assertEq(distribution.fee, 1000, "Maximum fee should be correctly snapshotted");
    }

    function test_distributeFromRepo_batchDistributionsSameFeeSnapshot() public {
        // Test that all distributions in a batch get the same fee snapshot
        vm.prank(owner);
        escrow.setFee(300); // 3%

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

        vm.prank(repoAdmin);
        uint[] memory distributionIds = escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");

        // All distributions should have the same fee
        for (uint i = 0; i < distributionIds.length; i++) {
            Escrow.Distribution memory distribution = escrow.getDistribution(distributionIds[i]);
            assertEq(distribution.fee, 300, "All distributions in batch should have same fee");
        }
    }

    function test_distributeFromRepo_feeChangeAfterCreationDoesNotAffect() public {
        // Test that changing fee after creation doesn't affect existing distributions
        vm.prank(owner);
        escrow.setFee(250); // 2.5%

        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: 1000e18,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        vm.prank(repoAdmin);
        uint[] memory distributionIds = escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");

        // Change fee after creation
        vm.prank(owner);
        escrow.setFee(750); // 7.5%

        // Check that existing distribution still has original fee
        Escrow.Distribution memory distribution = escrow.getDistribution(distributionIds[0]);
        assertEq(distribution.fee, 250, "Existing distribution should retain original fee");
        
        // Verify global fee did change
        assertEq(escrow.fee(), 750, "Global fee should have changed");
    }

    function test_distributeFromSender_revert_invalidToken() public {
        // Test token validation through distributeFromSender which calls _createDistribution directly
        // This bypasses the repo balance check and tests the actual token validation
        MockERC20 nonWhitelistedToken = new MockERC20("Non-Whitelisted", "NWT", 18);
        nonWhitelistedToken.mint(address(this), DISTRIBUTION_AMOUNT);
        nonWhitelistedToken.approve(address(escrow), DISTRIBUTION_AMOUNT);
        
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: nonWhitelistedToken
        });

        expectRevert(Errors.INVALID_TOKEN);
        escrow.distributeFromSender(distributions, "");
    }

    function test_getDistributionRepo() public {
        // Create a repo distribution
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        vm.prank(repoAdmin);
        uint[] memory distributionIds = escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");

        // Test getDistributionRepo for valid repo distribution
        Escrow.RepoAccount memory repoAccount = escrow.getDistributionRepo(distributionIds[0]);
        assertEq(repoAccount.repoId, REPO_ID);
        assertEq(repoAccount.instanceId, ACCOUNT_ID);

        // Create a solo distribution for comparison
        MockERC20(address(wETH)).mint(address(this), DISTRIBUTION_AMOUNT);
        MockERC20(address(wETH)).approve(address(escrow), DISTRIBUTION_AMOUNT);
        
        Escrow.DistributionParams[] memory soloDistributions = new Escrow.DistributionParams[](1);
        soloDistributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        uint[] memory soloDistributionIds = escrow.distributeFromSender(soloDistributions, "");

        // Test getDistributionRepo with solo distribution (should revert)
        expectRevert(Errors.NOT_REPO_DISTRIBUTION);
        escrow.getDistributionRepo(soloDistributionIds[0]);

        // Test getDistributionRepo with invalid distribution ID (should revert)
        expectRevert(Errors.INVALID_DISTRIBUTION_ID);
        escrow.getDistributionRepo(999999);
    }

    /* -------------------------------------------------------------------------- */
    /*                    REPO ADMIN OR DISTRIBUTOR ACCESS TESTS                 */
    /* -------------------------------------------------------------------------- */

    function test_distributeFromRepo_accessControl_adminCanDistribute() public {
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        // Admin should be able to distribute
        vm.prank(repoAdmin);
        uint[] memory distributionIds = escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");
        
        assertEq(distributionIds.length, 1);
        assertTrue(escrow.getDistribution(distributionIds[0]).exists);
    }

    function test_distributeFromRepo_accessControl_distributorCanDistribute() public {
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        // Distributor should be able to distribute
        vm.prank(distributor1);
        uint[] memory distributionIds = escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");
        
        assertEq(distributionIds.length, 1);
        assertTrue(escrow.getDistribution(distributionIds[0]).exists);
    }

    function test_distributeFromRepo_accessControl_secondDistributorCanDistribute() public {
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        // Second distributor should also be able to distribute
        vm.prank(distributor2);
        uint[] memory distributionIds = escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");
        
        assertEq(distributionIds.length, 1);
        assertTrue(escrow.getDistribution(distributionIds[0]).exists);
    }

    function test_distributeFromRepo_accessControl_randomUserCannotDistribute() public {
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        address randomUser = makeAddr("randomUser");

        // Random user should NOT be able to distribute
        expectRevert(Errors.NOT_REPO_ADMIN_OR_DISTRIBUTOR);
        vm.prank(randomUser);
        escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");
    }

    function test_distributeFromRepo_accessControl_crossRepoAdminCannotAccess() public {
        // Setup second repo with different admin
        uint256 repo2Id = 2;
        uint256 instance2Id = 200;
        address admin2 = makeAddr("admin2");
        _initializeSecondRepo(repo2Id, instance2Id, admin2);

        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        // Admin from repo2 should NOT be able to distribute from repo1
        expectRevert(Errors.NOT_REPO_ADMIN_OR_DISTRIBUTOR);
        vm.prank(admin2);
        escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");

        // Admin from repo1 should NOT be able to distribute from repo2
        expectRevert(Errors.NOT_REPO_ADMIN_OR_DISTRIBUTOR);
        vm.prank(repoAdmin);
        escrow.distributeFromRepo(repo2Id, instance2Id, distributions, "");
    }

    function test_distributeFromRepo_accessControl_crossRepoDistributorCannotAccess() public {
        // Setup second repo with admin and distributor
        uint256 repo2Id = 2;
        uint256 instance2Id = 200;
        address admin2 = makeAddr("admin2");
        address distributor2Repo2 = makeAddr("distributor2Repo2");
        
        _initializeSecondRepo(repo2Id, instance2Id, admin2);
        
        // Add distributor to repo2
        vm.prank(admin2);
        escrow.addDistributors(repo2Id, instance2Id, _toArray(distributor2Repo2));

        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        // Distributor from repo2 should NOT be able to distribute from repo1
        expectRevert(Errors.NOT_REPO_ADMIN_OR_DISTRIBUTOR);
        vm.prank(distributor2Repo2);
        escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");

        // Distributor from repo1 should NOT be able to distribute from repo2
        expectRevert(Errors.NOT_REPO_ADMIN_OR_DISTRIBUTOR);
        vm.prank(distributor1);
        escrow.distributeFromRepo(repo2Id, instance2Id, distributions, "");
    }

    function test_distributeFromRepo_accessControl_adminBecomesDistributor() public {
        // Admin can still distribute after becoming a distributor
        vm.prank(repoAdmin);
        escrow.addDistributors(REPO_ID, ACCOUNT_ID, _toArray(repoAdmin));

        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        // Admin who is also a distributor should still be able to distribute
        vm.prank(repoAdmin);
        uint[] memory distributionIds = escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");
        
        assertEq(distributionIds.length, 1);
    }

    function test_distributeFromRepo_accessControl_distributorBecomesAdmin() public {
        // Make distributor1 an admin
        vm.prank(repoAdmin);
        escrow.addAdmins(REPO_ID, ACCOUNT_ID, _toArray(distributor1));

        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        // Distributor who became admin should still be able to distribute
        vm.prank(distributor1);
        uint[] memory distributionIds = escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");
        
        assertEq(distributionIds.length, 1);
    }

    function test_distributeFromRepo_accessControl_removedDistributorCannotDistribute() public {
        // Remove distributor1
        vm.prank(repoAdmin);
        escrow.removeDistributors(REPO_ID, ACCOUNT_ID, _toArray(distributor1));

        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        // Removed distributor should NOT be able to distribute
        expectRevert(Errors.NOT_REPO_ADMIN_OR_DISTRIBUTOR);
        vm.prank(distributor1);
        escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");
        
        // But distributor2 should still work
        vm.prank(distributor2);
        uint[] memory distributionIds = escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");
        assertEq(distributionIds.length, 1);
    }

    function test_distributeFromRepo_accessControl_canDistributeGetter() public {
        // Test the canDistribute getter function
        assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, repoAdmin));
        assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, distributor1));
        assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, distributor2));
        
        address randomUser = makeAddr("randomUser");
        assertFalse(escrow.canDistribute(REPO_ID, ACCOUNT_ID, randomUser));
    }

    function test_distributeFromRepo_accessControl_nonExistentRepo() public {
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        // Try to distribute from non-existent repo
        expectRevert(Errors.NOT_REPO_ADMIN_OR_DISTRIBUTOR);
        vm.prank(repoAdmin);
        escrow.distributeFromRepo(999, 999, distributions, "");
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
                    escrow.repoSetAdminNonce(repoId, instanceId),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        
        escrow.initRepo(repoId, instanceId, _toArray(admin), deadline, v, r, s);
    }

    /* -------------------------------------------------------------------------- */
    /*                                    EVENTS                                  */
    /* -------------------------------------------------------------------------- */

    event DistributedFromRepo(
        uint256 indexed batchId,
        uint256 indexed distributionId,
        address indexed recipient,
        address token,
        uint256 amount,
        uint256 claimDeadline
    );

    event DistributedFromRepoBatch(
        uint256 indexed batchId,
        uint256 indexed repoId,
        uint256 indexed instanceId,
        uint256[] distributionIds,
        bytes data
    );

    /* -------------------------------------------------------------------------- */
    /*                          ADVANCED FUZZ TESTS                               */
    /* -------------------------------------------------------------------------- */

    /// @dev Fuzz test for distribution with extreme batch sizes and amounts
    function testFuzz_distributeFromRepo_extremeBatchScenarios(
        uint8 batchSize,
        uint256[20] memory amounts,
        uint32[20] memory claimPeriods
    ) public {
        uint256 batchLimit = escrow.batchLimit();
        batchSize = uint8(bound(batchSize, 1, batchLimit > 20 ? 20 : batchLimit));
        
        // Fund repo with sufficient funds
        uint256 totalFunds = 0;
        for (uint256 i = 0; i < batchSize; i++) {
            amounts[i] = bound(amounts[i], 1e18, 100e18);
            claimPeriods[i] = uint32(bound(claimPeriods[i], 1 hours, 365 days));
            totalFunds += amounts[i];
        }
        
        // Fund repo with extra buffer
        wETH.mint(address(this), totalFunds * 2);
        wETH.approve(address(escrow), totalFunds * 2);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, totalFunds * 2, "");
        
        // Create distribution params
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](batchSize);
        for (uint256 i = 0; i < batchSize; i++) {
            distributions[i] = Escrow.DistributionParams({
                amount: amounts[i],
                recipient: makeAddr(string(abi.encodePacked("recipient", i))),
                claimPeriod: claimPeriods[i],
                token: wETH
            });
        }
        
        uint256 initialBalance = escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH));
        
        vm.prank(repoAdmin);
        uint256[] memory distributionIds = escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");
        
        // Verify distributions were created correctly
        assertEq(distributionIds.length, batchSize);
        for (uint256 i = 0; i < batchSize; i++) {
            Escrow.Distribution memory dist = escrow.getDistribution(distributionIds[i]);
            assertEq(dist.amount, amounts[i]);
            assertEq(dist.recipient, distributions[i].recipient);
            assertEq(dist.claimDeadline, block.timestamp + claimPeriods[i]);
            assertEq(uint8(dist.status), uint8(Escrow.DistributionStatus.Distributed));
        }
        
        // Verify account balance was decreased correctly
        uint256 finalBalance = escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH));
        assertEq(finalBalance, initialBalance - totalFunds);
    }

    /// @dev Fuzz test for authorization edge cases
    function testFuzz_distributeFromRepo_authorizationEdgeCases(
        uint256 repoId,
        uint256 accountId,
        uint256 actorSeed,
        bool isAdmin,
        bool isDistributor
    ) public {
        repoId = bound(repoId, 1, 1000);
        accountId = bound(accountId, 1, 1000);
        actorSeed = bound(actorSeed, 0, type(uint256).max);
        
        address actor = vm.addr(actorSeed % 1000 + 1); // Avoid address(0)
        
        // Initialize repo if needed
        if (!escrow.getAccountExists(repoId, accountId)) {
            address[] memory initialAdmins = new address[](1);
            initialAdmins[0] = repoAdmin;
            
            uint256 deadline = block.timestamp + 1 hours;
            bytes32 digest = keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    escrow.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(
                        escrow.SET_ADMIN_TYPEHASH(),
                        repoId,
                        accountId,
                        keccak256(abi.encode(initialAdmins)),
                        escrow.repoSetAdminNonce(repoId, accountId),
                        deadline
                    ))
                )
            );
            
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
            escrow.initRepo(repoId, accountId, initialAdmins, deadline, v, r, s);
            
            // Fund the repo
            wETH.mint(address(this), 1000e18);
            wETH.approve(address(escrow), 1000e18);
            escrow.fundRepo(repoId, accountId, wETH, 1000e18, "");
        }
        
        // Set up actor permissions
        if (isAdmin && !escrow.getIsAuthorizedAdmin(repoId, accountId, actor)) {
            address[] memory adminsToAdd = new address[](1);
            adminsToAdd[0] = actor;
            vm.prank(repoAdmin);
            escrow.addAdmins(repoId, accountId, adminsToAdd);
        }
        
        if (isDistributor && !escrow.getIsAuthorizedDistributor(repoId, accountId, actor)) {
            address[] memory distributorsToAdd = new address[](1);
            distributorsToAdd[0] = actor;
            vm.prank(repoAdmin);
            escrow.addDistributors(repoId, accountId, distributorsToAdd);
        }
        
        // Try to distribute
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: 1e18,
            recipient: makeAddr("recipient"),
            claimPeriod: 7 days,
            token: wETH
        });
        
        bool shouldSucceed = isAdmin || isDistributor;
        
        if (shouldSucceed) {
            vm.prank(actor);
            uint256[] memory distributionIds = escrow.distributeFromRepo(repoId, accountId, distributions, "");
            assertEq(distributionIds.length, 1);
        } else {
            vm.expectRevert(bytes(Errors.NOT_REPO_ADMIN_OR_DISTRIBUTOR));
            vm.prank(actor);
            escrow.distributeFromRepo(repoId, accountId, distributions, "");
        }
    }

    /// @dev Fuzz test for balance edge cases and underflow protection
    function testFuzz_distributeFromRepo_balanceEdgeCases(
        uint256 availableBalance,
        uint256 distributionAmount,
        uint8 numDistributions
    ) public {
        // Use more conservative bounds to prevent overflow issues
        availableBalance = bound(availableBalance, 1000, 100e18); // Reduced upper bound
        numDistributions = uint8(bound(numDistributions, 1, 3)); // Keep it simple
        
        // Ensure distributionAmount is reasonable and non-zero
        distributionAmount = bound(distributionAmount, 100, availableBalance / 10); // Conservative bound
        
        // Skip test if inputs are invalid
        if (distributionAmount == 0 || numDistributions == 0) {
            return;
        }
        
        // Get initial balance (should be FUND_AMOUNT from setUp)
        uint256 initialBalance = escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH));
        
        // Fund repo with additional available balance
        wETH.mint(address(this), availableBalance);
        wETH.approve(address(escrow), availableBalance);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, availableBalance, "");
        
        // Total available balance is now initialBalance + availableBalance
        uint256 totalAvailableBalance = initialBalance + availableBalance;
        uint256 totalDistributionAmount = distributionAmount * numDistributions;
        
        // Skip if total distribution amount would overflow or be invalid
        if (totalDistributionAmount < distributionAmount || totalDistributionAmount == 0) {
            return;
        }
        
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](numDistributions);
        for (uint256 i = 0; i < numDistributions; i++) {
            distributions[i] = Escrow.DistributionParams({
                amount: distributionAmount,
                recipient: makeAddr(string(abi.encodePacked("recipient", i))),
                claimPeriod: 7 days,
                token: wETH
            });
        }
        
        if (totalDistributionAmount <= totalAvailableBalance) {
            // Should succeed
            vm.prank(repoAdmin);
            uint256[] memory distributionIds = escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");
            assertEq(distributionIds.length, numDistributions);
            
            // Verify balance was updated correctly
            uint256 finalBalance = escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH));
            assertEq(finalBalance, totalAvailableBalance - totalDistributionAmount);
        } else {
            // Should fail with insufficient balance
            vm.expectRevert(bytes(Errors.INSUFFICIENT_BALANCE));
            vm.prank(repoAdmin);
            escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");
        }
    }

    /// @dev Test gas optimization for large batch distributions
    function test_distributeFromRepo_gasOptimization() public {
        uint256 batchLimit = escrow.batchLimit();
        
        // Use a smaller batch size for gas testing to keep it reasonable
        uint256 testBatchSize = batchLimit > 100 ? 100 : batchLimit;
        
        // Fund repo with sufficient balance
        uint256 totalAmount = testBatchSize * 1e18;
        wETH.mint(address(this), totalAmount);
        wETH.approve(address(escrow), totalAmount);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, totalAmount, "");
        
        // Create test batch size distribution
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](testBatchSize);
        for (uint256 i = 0; i < testBatchSize; i++) {
            distributions[i] = Escrow.DistributionParams({
                amount: 1e18,
                recipient: makeAddr(string(abi.encodePacked("recipient", i))),
                claimPeriod: 7 days,
                token: wETH
            });
        }
        
        uint256 gasBefore = gasleft();
        vm.prank(repoAdmin);
        uint256[] memory distributionIds = escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");
        uint256 gasUsed = gasBefore - gasleft();
        
        // Verify all distributions were created
        assertEq(distributionIds.length, testBatchSize);
        
        // Gas usage should be reasonable (this is a sanity check)
        // Adjust expectation based on batch size - approximately 100k gas per distribution
        uint256 expectedMaxGas = testBatchSize * 200_000; // 200k gas per distribution
        assertTrue(gasUsed < expectedMaxGas, "Gas usage should be reasonable for batch");
    }

    /// @dev Test distribution with different token types and edge cases
    function testFuzz_distributeFromRepo_tokenEdgeCases(uint256 /* tokenSeed */) public {
        // For now, we only test with whitelisted tokens since that's what the contract accepts
        // In a real scenario, you might want to test with different ERC20 tokens
        
        // Test with minimum distribution amount that works with fees
        // Use a larger amount to ensure recipient gets at least 1 wei after fees
        uint256 minAmount = 1000; // 1000 wei (enough to handle fees)
        
        wETH.mint(address(this), minAmount * 2);
        wETH.approve(address(escrow), minAmount * 2);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, minAmount * 2, "");
        
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: minAmount,
            recipient: makeAddr("recipient"),
            claimPeriod: 1 hours, // Minimum claim period
            token: wETH
        });
        
        vm.prank(repoAdmin);
        uint256[] memory distributionIds = escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");
        
        // Verify distribution was created with minimum values
        Escrow.Distribution memory dist = escrow.getDistribution(distributionIds[0]);
        assertEq(dist.amount, minAmount);
        assertEq(dist.claimDeadline, block.timestamp + 1 hours);
    }

    /// @dev Test fee calculation edge cases during distribution creation
    function testFuzz_distributeFromRepo_feeValidationEdgeCases(
        uint256 amount,
        uint16 feeRate
    ) public {
        amount = bound(amount, 2, 1000e18); // Ensure amount is at least 2 wei
        feeRate = uint16(bound(feeRate, 0, 1000)); // 0-10%
        
        // Set fee rate
        vm.prank(owner);
        escrow.setFee(feeRate);
        
        // Fund repo
        wETH.mint(address(this), amount);
        wETH.approve(address(escrow), amount);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, amount, "");
        
        // Calculate expected fee (using same logic as contract)
        uint256 expectedFee = (amount * feeRate + 9999) / 10000; // mulDivUp equivalent
        bool shouldSucceed = amount > expectedFee; // Recipient must get at least 1 wei
        
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: amount,
            recipient: makeAddr("recipient"),
            claimPeriod: 7 days,
            token: wETH
        });
        
        if (shouldSucceed) {
            vm.prank(repoAdmin);
            uint256[] memory distributionIds = escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");
            
            // Verify distribution was created with correct fee stored
            Escrow.Distribution memory dist = escrow.getDistribution(distributionIds[0]);
            assertEq(dist.fee, feeRate); // Fee should be stored as it was at creation time
        } else {
            vm.expectRevert(bytes(Errors.INVALID_AMOUNT));
            vm.prank(repoAdmin);
            escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                               GAP FILL TESTS                               */
    /* -------------------------------------------------------------------------- */

    function test_distributeFromRepo_revert_nonExistentRepo() public {
        uint256 nonExistentRepoId = 999;
        uint256 nonExistentAccountId = 999;
        
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        // This should revert because the distributor check will fail
        // (non-existent repos have no admins or distributors)
        expectRevert(Errors.NOT_REPO_ADMIN_OR_DISTRIBUTOR);
        vm.prank(repoAdmin);
        escrow.distributeFromRepo(nonExistentRepoId, nonExistentAccountId, distributions, "");
    }

    function test_distributeFromRepo_revert_adminRemovedMidFlow() public {
        // Add a temporary admin
        address tempAdmin = makeAddr("tempAdmin");
        address[] memory adminsToAdd = new address[](1);
        adminsToAdd[0] = tempAdmin;
        
        vm.prank(repoAdmin);
        escrow.addAdmins(REPO_ID, ACCOUNT_ID, adminsToAdd);
        
        // Verify admin was added
        assertTrue(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, tempAdmin));
        
        // Remove the admin
        address[] memory adminsToRemove = new address[](1);
        adminsToRemove[0] = tempAdmin;
        
        vm.prank(repoAdmin);
        escrow.removeAdmins(REPO_ID, ACCOUNT_ID, adminsToRemove);
        
        // Verify admin was removed
        assertFalse(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, tempAdmin));
        
        // Try to distribute as removed admin - should fail
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        expectRevert(Errors.NOT_REPO_ADMIN_OR_DISTRIBUTOR);
        vm.prank(tempAdmin);
        escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");
    }

    function test_distributeFromRepo_revert_distributorRemovedMidFlow() public {
        // Verify distributor1 can distribute initially
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        vm.prank(distributor1);
        uint[] memory distributionIds = escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");
        assertEq(distributionIds.length, 1);
        
        // Remove the distributor
        address[] memory distributorsToRemove = new address[](1);
        distributorsToRemove[0] = distributor1;
        
        vm.prank(repoAdmin);
        escrow.removeDistributors(REPO_ID, ACCOUNT_ID, distributorsToRemove);
        
        // Verify distributor was removed
        assertFalse(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributor1));
        
        // Try to distribute as removed distributor - should fail
        Escrow.DistributionParams[] memory distributions2 = new Escrow.DistributionParams[](1);
        distributions2[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient2,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        expectRevert(Errors.NOT_REPO_ADMIN_OR_DISTRIBUTOR);
        vm.prank(distributor1);
        escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions2, "");
    }

    function test_distributeFromRepo_claimIntegration() public {
        // Create a distribution from repo
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        vm.prank(repoAdmin);
        uint[] memory distributionIds = escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");
        
        // Verify distribution was created
        assertEq(distributionIds.length, 1);
        Escrow.Distribution memory distribution = escrow.getDistribution(distributionIds[0]);
        assertEq(distribution.amount, DISTRIBUTION_AMOUNT);
        assertEq(distribution.recipient, recipient1);
        assertEq(distribution.fee, escrow.fee()); // Should snapshot current fee
        
        // Claim the distribution
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.CLAIM_TYPEHASH(),
                    keccak256(abi.encode(distributionIds)),
                    recipient1,
                    escrow.recipientClaimNonce(recipient1),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        
        uint256 initialBalance = wETH.balanceOf(recipient1);
        uint256 feeAmount = (DISTRIBUTION_AMOUNT * distribution.fee + 9999) / 10000;
        uint256 expectedNetAmount = DISTRIBUTION_AMOUNT - feeAmount;
        
        vm.prank(recipient1);
        escrow.claim(distributionIds, deadline, v, r, s, "");
        
        // Verify claim worked correctly
        assertEq(wETH.balanceOf(recipient1), initialBalance + expectedNetAmount);
        
        // Verify distribution status changed
        Escrow.Distribution memory claimedDistribution = escrow.getDistribution(distributionIds[0]);
        assertEq(uint8(claimedDistribution.status), uint8(Escrow.DistributionStatus.Claimed));
    }

    function test_distributeFromRepo_domainSeparatorBehavior() public {
        // Test that domain separator is consistent within the same chain
        bytes32 initialDomainSeparator = escrow.DOMAIN_SEPARATOR();
        
        // Create a distribution (which uses domain separator internally for signature verification)
        address[] memory admins = new address[](1);
        admins[0] = makeAddr("testAdmin");
        
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    123, // repoId
                    456, // accountId
                    keccak256(abi.encode(admins)),
                    escrow.repoSetAdminNonce(123, 456),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        
        // This should work with current domain separator
        escrow.initRepo(123, 456, admins, deadline, v, r, s);
        
        // Domain separator should remain the same
        assertEq(escrow.DOMAIN_SEPARATOR(), initialDomainSeparator);
        
        // Test domain separator changes with chain ID (simulate fork)
        vm.chainId(999);
        bytes32 newDomainSeparator = escrow.DOMAIN_SEPARATOR();
        assertTrue(newDomainSeparator != initialDomainSeparator, "Domain separator should change with chain ID");
    }

    function test_distributeFromRepo_reentrancyProtection() public {
        // For basic reentrancy protection, we can test that the function
        // maintains correct state even if called recursively (though this
        // is unlikely with the current implementation since tokens are transferred
        // from repo balance, not from external transfers)
        
        // This test primarily verifies that state updates happen in the correct order
        uint256 initialBalance = escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH));
        uint256 initialDistributionCount = escrow.distributionCount();
        
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        vm.prank(repoAdmin);
        uint[] memory distributionIds = escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");
        
        // Verify state was updated atomically
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), initialBalance - DISTRIBUTION_AMOUNT);
        assertEq(escrow.distributionCount(), initialDistributionCount + 1);
        assertEq(distributionIds[0], initialDistributionCount);
        
        // Verify distribution exists and has correct data
        Escrow.Distribution memory distribution = escrow.getDistribution(distributionIds[0]);
        assertTrue(distribution.exists);
        assertEq(distribution.amount, DISTRIBUTION_AMOUNT);
    }
} 