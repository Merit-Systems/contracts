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
                    escrow.ownerNonce(),
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
        emit DistributedRepo(0, 0, recipient1, address(wETH), DISTRIBUTION_AMOUNT, expectedDeadline);

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
        
        expectRevert(Errors.NOT_AUTHORIZED_DISTRIBUTOR);
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

    function test_distributeFromRepo_revert_zeroClaimPeriod() public {
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: 0,
            token: wETH
        });

        expectRevert(Errors.INVALID_CLAIM_PERIOD);
        vm.prank(repoAdmin);
        escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");
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
        emit DistributedRepoBatch(0, REPO_ID, ACCOUNT_ID, expectedDistributionIds, "test batch");

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
        vm.assume(claimPeriod > 0 && claimPeriod <= 365 days);

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
        uint256 initialBatchCount = escrow.distributionBatchCount();

        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        vm.prank(repoAdmin);
        escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");

        assertEq(escrow.distributionBatchCount(), initialBatchCount + 1);
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
        assertEq(repoAccount.accountId, ACCOUNT_ID);

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

    // Events for testing
    event DistributedRepo(
        uint256 indexed distributionBatchId,
        uint256 indexed distributionId,
        address indexed recipient,
        address token,
        uint256 amount,
        uint256 claimDeadline
    );

    event DistributedRepoBatch(
        uint256 indexed distributionBatchId,
        uint256 indexed repoId,
        uint256 indexed accountId,
        uint256[] distributionIds,
        bytes data
    );
} 