// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "./Escrow.t.sol";

contract DistributeRepo_Test is Base_Test {
    
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
                    repoAdmin,
                    escrow.ownerNonce(),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        
        escrow.initRepo(REPO_ID, ACCOUNT_ID, repoAdmin, deadline, v, r, s);
    }

    function _fundRepo() internal {
        wETH.mint(address(this), FUND_AMOUNT);
        wETH.approve(address(escrow), FUND_AMOUNT);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, FUND_AMOUNT);
    }

    function _addDistributors() internal {
        address[] memory distributors = new address[](2);
        distributors[0] = distributor1;
        distributors[1] = distributor2;
        
        vm.prank(repoAdmin);
        escrow.addDistributor(REPO_ID, ACCOUNT_ID, distributors);
    }



    function test_distributeRepo_success_asAdmin() public {
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
        uint[] memory distributionIds = escrow.distributeRepo(REPO_ID, ACCOUNT_ID, distributions, "");

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

    function test_distributeRepo_success_asDistributor() public {
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        vm.prank(distributor1);
        uint[] memory distributionIds = escrow.distributeRepo(REPO_ID, ACCOUNT_ID, distributions, "");

        assertEq(distributionIds.length, 1);
        
        Escrow.Distribution memory distribution = escrow.getDistribution(distributionIds[0]);
        assertEq(distribution.amount, DISTRIBUTION_AMOUNT);
        assertEq(distribution.recipient, recipient1);
    }

    function test_distributeRepo_multipleDistributions() public {
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
        uint[] memory distributionIds = escrow.distributeRepo(REPO_ID, ACCOUNT_ID, distributions, "batch data");

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

    function test_distributeRepo_revert_notAuthorized() public {
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
        escrow.distributeRepo(REPO_ID, ACCOUNT_ID, distributions, "");
    }

    function test_distributeRepo_revert_insufficientBalance() public {
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: FUND_AMOUNT + 1, // More than available
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        expectRevert(Errors.INSUFFICIENT_BALANCE);
        vm.prank(repoAdmin);
        escrow.distributeRepo(REPO_ID, ACCOUNT_ID, distributions, "");
    }

    function test_distributeRepo_revert_batchLimitExceeded() public {
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
        escrow.distributeRepo(REPO_ID, ACCOUNT_ID, distributions, "");
    }

    function test_distributeRepo_revert_zeroAmount() public {
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: 0,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        expectRevert(Errors.INVALID_AMOUNT);
        vm.prank(repoAdmin);
        escrow.distributeRepo(REPO_ID, ACCOUNT_ID, distributions, "");
    }

    function test_distributeRepo_revert_invalidRecipient() public {
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: address(0),
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        expectRevert(Errors.INVALID_ADDRESS);
        vm.prank(repoAdmin);
        escrow.distributeRepo(REPO_ID, ACCOUNT_ID, distributions, "");
    }

    function test_distributeRepo_revert_zeroClaimPeriod() public {
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: 0,
            token: wETH
        });

        expectRevert(Errors.INVALID_CLAIM_PERIOD);
        vm.prank(repoAdmin);
        escrow.distributeRepo(REPO_ID, ACCOUNT_ID, distributions, "");
    }

    function test_distributeRepo_revert_insufficientBalanceNonWhitelistedToken() public {
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
        escrow.distributeRepo(REPO_ID, ACCOUNT_ID, distributions, "");
    }

    function test_distributeRepo_hasDistributionsFlag() public {
        assertFalse(escrow.getAccountHasDistributions(REPO_ID, ACCOUNT_ID));

        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        vm.prank(repoAdmin);
        escrow.distributeRepo(REPO_ID, ACCOUNT_ID, distributions, "");

        assertTrue(escrow.getAccountHasDistributions(REPO_ID, ACCOUNT_ID));
    }

    function test_distributeRepo_batchEvents() public {
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
        escrow.distributeRepo(REPO_ID, ACCOUNT_ID, distributions, "test batch");
    }

    function test_distributeRepo_fuzz_amounts(uint256 amount1, uint256 amount2) public {
        vm.assume(amount1 > 0 && amount1 <= FUND_AMOUNT / 2);
        vm.assume(amount2 > 0 && amount2 <= FUND_AMOUNT / 2);
        vm.assume(amount1 + amount2 <= FUND_AMOUNT);

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
        uint[] memory distributionIds = escrow.distributeRepo(REPO_ID, ACCOUNT_ID, distributions, "");

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

    function test_distributeRepo_fuzz_claimPeriods(uint32 claimPeriod) public {
        vm.assume(claimPeriod > 0 && claimPeriod <= 365 days);

        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: claimPeriod,
            token: wETH
        });

        vm.prank(repoAdmin);
        uint[] memory distributionIds = escrow.distributeRepo(REPO_ID, ACCOUNT_ID, distributions, "");

        Escrow.Distribution memory distribution = escrow.getDistribution(distributionIds[0]);
        assertEq(distribution.claimDeadline, block.timestamp + claimPeriod);
    }

    function test_distributeRepo_distributionCounter() public {
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
        uint[] memory distributionIds = escrow.distributeRepo(REPO_ID, ACCOUNT_ID, distributions, "");

        assertEq(escrow.distributionCount(), initialCount + 3);
        assertEq(distributionIds[0], initialCount);
        assertEq(distributionIds[1], initialCount + 1);
        assertEq(distributionIds[2], initialCount + 2);
    }

    function test_distributeRepo_batchCounter() public {
        uint256 initialBatchCount = escrow.distributionBatchCount();

        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient1,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        vm.prank(repoAdmin);
        escrow.distributeRepo(REPO_ID, ACCOUNT_ID, distributions, "");

        assertEq(escrow.distributionBatchCount(), initialBatchCount + 1);
    }

    function test_distributeSolo_revert_invalidToken() public {
        // Test token validation through distributeSolo which calls _createDistribution directly
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
        escrow.distributeSolo(distributions);
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