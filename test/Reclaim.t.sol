// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "./Escrow.t.sol";

contract Reclaim_Test is Base_Test {
    
    uint256 constant REPO_ID = 1;
    uint256 constant ACCOUNT_ID = 100;
    uint256 constant FUND_AMOUNT = 5000e18;
    uint256 constant DISTRIBUTION_AMOUNT = 1000e18;
    uint32 constant CLAIM_PERIOD = 7 days;

    address repoAdmin;
    address recipient;
    address soloPayer;

    uint256 adminPrivateKey = 0x1111111111111111111111111111111111111111111111111111111111111111;
    
    function setUp() public override {
        super.setUp();
        
        repoAdmin = vm.addr(adminPrivateKey);
        recipient = makeAddr("recipient");
        soloPayer = makeAddr("soloPayer");
        
        // Initialize repo
        _initializeRepo();
        
        // Setup solo payer
        wETH.mint(soloPayer, DISTRIBUTION_AMOUNT * 10);
        vm.prank(soloPayer);
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
                    repoAdmin,
                    escrow.ownerNonce(),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        escrow.initRepo(REPO_ID, ACCOUNT_ID, repoAdmin, deadline, v, r, s);
    }

    function _fundRepo(uint256 amount) internal {
        wETH.mint(address(this), amount);
        wETH.approve(address(escrow), amount);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, amount);
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
        uint[] memory distributionIds = escrow.distributeRepo(REPO_ID, ACCOUNT_ID, distributions, "");
        return distributionIds[0];
    }

    function _createSoloDistribution(address _recipient, uint256 amount) internal returns (uint256 distributionId) {
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: amount,
            recipient: _recipient,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        vm.prank(soloPayer);
        uint[] memory distributionIds = escrow.distributeSolo(distributions);
        return distributionIds[0];
    }

    /* -------------------------------------------------------------------------- */
    /*                              RECLAIM FUND TESTS                            */
    /* -------------------------------------------------------------------------- */

    function test_reclaimFund_success() public {
        _fundRepo(FUND_AMOUNT);
        
        uint256 reclaimAmount = 2000e18;
        uint256 initialAdminBalance = wETH.balanceOf(repoAdmin);
        uint256 initialRepoBalance = escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH));

        vm.expectEmit(true, true, true, true);
        emit ReclaimedFund(REPO_ID, repoAdmin, reclaimAmount);

        vm.prank(repoAdmin);
        escrow.reclaimFund(REPO_ID, ACCOUNT_ID, address(wETH), reclaimAmount);

        // Check balances
        assertEq(wETH.balanceOf(repoAdmin), initialAdminBalance + reclaimAmount);
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), initialRepoBalance - reclaimAmount);
    }

    function test_reclaimFund_fullAmount() public {
        _fundRepo(FUND_AMOUNT);

        vm.prank(repoAdmin);
        escrow.reclaimFund(REPO_ID, ACCOUNT_ID, address(wETH), FUND_AMOUNT);

        // Should be able to reclaim all funds
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), 0);
        assertEq(wETH.balanceOf(repoAdmin), FUND_AMOUNT);
    }

    function test_reclaimFund_revert_notRepoAdmin() public {
        _fundRepo(FUND_AMOUNT);

        address unauthorized = makeAddr("unauthorized");
        expectRevert(Errors.NOT_REPO_ADMIN);
        vm.prank(unauthorized);
        escrow.reclaimFund(REPO_ID, ACCOUNT_ID, address(wETH), FUND_AMOUNT);
    }

    function test_reclaimFund_revert_invalidToken() public {
        _fundRepo(FUND_AMOUNT);
        
        MockERC20 nonWhitelistedToken = new MockERC20("Non-Whitelisted", "NWT", 18);

        expectRevert(Errors.INVALID_TOKEN);
        vm.prank(repoAdmin);
        escrow.reclaimFund(REPO_ID, ACCOUNT_ID, address(nonWhitelistedToken), FUND_AMOUNT);
    }

    function test_reclaimFund_revert_zeroAmount() public {
        _fundRepo(FUND_AMOUNT);

        expectRevert(Errors.INVALID_AMOUNT);
        vm.prank(repoAdmin);
        escrow.reclaimFund(REPO_ID, ACCOUNT_ID, address(wETH), 0);
    }

    function test_reclaimFund_revert_repoHasDistributions() public {
        _fundRepo(FUND_AMOUNT);
        
        // Create a distribution (this sets hasDistributions flag)
        _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);

        expectRevert(Errors.REPO_HAS_DISTRIBUTIONS);
        vm.prank(repoAdmin);
        escrow.reclaimFund(REPO_ID, ACCOUNT_ID, address(wETH), FUND_AMOUNT);
    }

    function test_reclaimFund_revert_insufficientBalance() public {
        _fundRepo(FUND_AMOUNT);

        expectRevert(Errors.INSUFFICIENT_BALANCE);
        vm.prank(repoAdmin);
        escrow.reclaimFund(REPO_ID, ACCOUNT_ID, address(wETH), FUND_AMOUNT + 1);
    }

    /* -------------------------------------------------------------------------- */
    /*                              RECLAIM REPO TESTS                            */
    /* -------------------------------------------------------------------------- */

    function test_reclaimRepo_success() public {
        _fundRepo(FUND_AMOUNT);
        uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);

        // Move past claim deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        uint256 initialRepoBalance = escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH));

        vm.expectEmit(true, true, true, true);
        emit ReclaimedRepo(REPO_ID, distributionId, address(this), DISTRIBUTION_AMOUNT);

        escrow.reclaimRepo(distributionIds);

        // Check repo balance increased
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), initialRepoBalance + DISTRIBUTION_AMOUNT);

        // Check distribution status
        Escrow.Distribution memory distribution = escrow.getDistribution(distributionId);
        assertTrue(uint8(distribution.distributionStatus) == 2); // Reclaimed
    }

    function test_reclaimRepo_multipleDistributions() public {
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

        escrow.reclaimRepo(distributionIds);

        // Check repo balance increased by total amount
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), initialRepoBalance + amount1 + amount2);
    }

    function test_reclaimRepo_revert_batchLimitExceeded() public {
        uint256 batchLimit = escrow.batchLimit();
        uint[] memory distributionIds = new uint[](batchLimit + 1);

        expectRevert(Errors.BATCH_LIMIT_EXCEEDED);
        escrow.reclaimRepo(distributionIds);
    }

    function test_reclaimRepo_revert_invalidDistributionId() public {
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = 999; // Non-existent

        expectRevert(Errors.INVALID_DISTRIBUTION_ID);
        escrow.reclaimRepo(distributionIds);
    }

    function test_reclaimRepo_revert_notRepoDistribution() public {
        uint256 distributionId = _createSoloDistribution(recipient, DISTRIBUTION_AMOUNT);
        
        // Move past claim deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        expectRevert(Errors.NOT_REPO_DISTRIBUTION);
        escrow.reclaimRepo(distributionIds);
    }

    function test_reclaimRepo_revert_alreadyClaimed() public {
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
                    escrow.recipientNonce(recipient),
                    block.timestamp + 1 hours
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest); // owner is signer

        vm.prank(recipient);
        escrow.claim(claimIds, block.timestamp + 1 hours, v, r, s);

        // Now try to reclaim the already claimed distribution
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        expectRevert(Errors.ALREADY_CLAIMED);
        escrow.reclaimRepo(distributionIds);
    }

    function test_reclaimRepo_revert_stillClaimable() public {
        _fundRepo(FUND_AMOUNT);
        uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);

        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        // Still within claim period
        expectRevert(Errors.STILL_CLAIMABLE);
        escrow.reclaimRepo(distributionIds);
    }

    /* -------------------------------------------------------------------------- */
    /*                              RECLAIM SOLO TESTS                            */
    /* -------------------------------------------------------------------------- */

    function test_reclaimSolo_success() public {
        uint256 distributionId = _createSoloDistribution(recipient, DISTRIBUTION_AMOUNT);

        // Move past claim deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        uint256 initialPayerBalance = wETH.balanceOf(soloPayer);

        vm.expectEmit(true, true, true, true);
        emit ReclaimedSolo(distributionId, soloPayer, DISTRIBUTION_AMOUNT);

        escrow.reclaimSolo(distributionIds);

        // Check payer received funds back
        assertEq(wETH.balanceOf(soloPayer), initialPayerBalance + DISTRIBUTION_AMOUNT);

        // Check distribution status
        Escrow.Distribution memory distribution = escrow.getDistribution(distributionId);
        assertTrue(uint8(distribution.distributionStatus) == 2); // Reclaimed
    }

    function test_reclaimSolo_multipleDistributions() public {
        uint256 amount1 = 400e18;
        uint256 amount2 = 600e18;
        uint256 distributionId1 = _createSoloDistribution(recipient, amount1);
        uint256 distributionId2 = _createSoloDistribution(recipient, amount2);

        // Move past claim deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        uint[] memory distributionIds = new uint[](2);
        distributionIds[0] = distributionId1;
        distributionIds[1] = distributionId2;

        uint256 initialPayerBalance = wETH.balanceOf(soloPayer);

        escrow.reclaimSolo(distributionIds);

        // Check payer received all funds back
        assertEq(wETH.balanceOf(soloPayer), initialPayerBalance + amount1 + amount2);
    }

    function test_reclaimSolo_multiplePayers() public {
        address payer2 = makeAddr("payer2");
        wETH.mint(payer2, DISTRIBUTION_AMOUNT);
        vm.prank(payer2);
        wETH.approve(address(escrow), DISTRIBUTION_AMOUNT);

        // Create distribution from different payer
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: DISTRIBUTION_AMOUNT,
            recipient: recipient,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        vm.prank(payer2);
        uint[] memory distributionIds2 = escrow.distributeSolo(distributions);

        uint256 distributionId1 = _createSoloDistribution(recipient, DISTRIBUTION_AMOUNT);

        // Move past claim deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        uint[] memory distributionIds = new uint[](2);
        distributionIds[0] = distributionId1;
        distributionIds[1] = distributionIds2[0];

        uint256 initialPayer1Balance = wETH.balanceOf(soloPayer);
        uint256 initialPayer2Balance = wETH.balanceOf(payer2);

        escrow.reclaimSolo(distributionIds);

        // Each payer should get their own distribution back
        assertEq(wETH.balanceOf(soloPayer), initialPayer1Balance + DISTRIBUTION_AMOUNT);
        assertEq(wETH.balanceOf(payer2), initialPayer2Balance + DISTRIBUTION_AMOUNT);
    }

    function test_reclaimSolo_revert_batchLimitExceeded() public {
        uint256 batchLimit = escrow.batchLimit();
        uint[] memory distributionIds = new uint[](batchLimit + 1);

        expectRevert(Errors.BATCH_LIMIT_EXCEEDED);
        escrow.reclaimSolo(distributionIds);
    }

    function test_reclaimSolo_revert_invalidDistributionId() public {
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = 999; // Non-existent

        expectRevert(Errors.INVALID_DISTRIBUTION_ID);
        escrow.reclaimSolo(distributionIds);
    }

    function test_reclaimSolo_revert_notSoloDistribution() public {
        _fundRepo(FUND_AMOUNT);
        uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        
        // Move past claim deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        expectRevert(Errors.NOT_DIRECT_DISTRIBUTION);
        escrow.reclaimSolo(distributionIds);
    }

    function test_reclaimSolo_revert_alreadyClaimed() public {
        uint256 distributionId = _createSoloDistribution(recipient, DISTRIBUTION_AMOUNT);

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
        escrow.claim(claimIds, block.timestamp + 1 hours, v, r, s);

        // Now try to reclaim the already claimed distribution
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        expectRevert(Errors.ALREADY_CLAIMED);
        escrow.reclaimSolo(distributionIds);
    }

    function test_reclaimSolo_revert_stillClaimable() public {
        uint256 distributionId = _createSoloDistribution(recipient, DISTRIBUTION_AMOUNT);

        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        // Still within claim period
        expectRevert(Errors.STILL_CLAIMABLE);
        escrow.reclaimSolo(distributionIds);
    }

    /* -------------------------------------------------------------------------- */
    /*                                MIXED SCENARIOS                             */
    /* -------------------------------------------------------------------------- */

    function test_reclaim_afterPartialClaim() public {
        _fundRepo(FUND_AMOUNT);
        
        uint256 distributionId1 = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        uint256 distributionId2 = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);

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
        escrow.claim(claimIds, block.timestamp + 1 hours, v, r, s);

        // Move past deadline and reclaim the other
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        uint[] memory reclaimIds = new uint[](1);
        reclaimIds[0] = distributionId2;

        uint256 initialRepoBalance = escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH));
        escrow.reclaimRepo(reclaimIds);

        // Should reclaim successfully
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), initialRepoBalance + DISTRIBUTION_AMOUNT);
    }

    function test_reclaim_fuzz_amounts(uint256 amount1, uint256 amount2) public {
        vm.assume(amount1 > 0 && amount1 <= 1000e18);
        vm.assume(amount2 > 0 && amount2 <= 1000e18);

        _fundRepo(amount1 + amount2 + 1000e18); // Extra buffer

        uint256 distributionId1 = _createRepoDistribution(recipient, amount1);
        uint256 distributionId2 = _createSoloDistribution(recipient, amount2);

        // Move past deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        // Reclaim repo distribution
        uint[] memory repoIds = new uint[](1);
        repoIds[0] = distributionId1;
        uint256 initialRepoBalance = escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH));
        escrow.reclaimRepo(repoIds);
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), initialRepoBalance + amount1);

        // Reclaim solo distribution
        uint[] memory soloIds = new uint[](1);
        soloIds[0] = distributionId2;
        uint256 initialPayerBalance = wETH.balanceOf(soloPayer);
        escrow.reclaimSolo(soloIds);
        assertEq(wETH.balanceOf(soloPayer), initialPayerBalance + amount2);
    }

    /* -------------------------------------------------------------------------- */
    /*                                    EVENTS                                  */
    /* -------------------------------------------------------------------------- */

    event ReclaimedFund(uint256 indexed repoId, address indexed admin, uint256 amount);
    event ReclaimedRepo(uint256 indexed repoId, uint256 indexed distributionId, address indexed admin, uint256 amount);
    event ReclaimedSolo(uint256 indexed distributionId, address indexed payer, uint256 amount);
} 