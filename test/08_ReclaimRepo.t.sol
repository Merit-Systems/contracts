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
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, amount, "");
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

        // Check both distributions are reclaimed
        Escrow.Distribution memory distribution1 = escrow.getDistribution(distributionId1);
        Escrow.Distribution memory distribution2 = escrow.getDistribution(distributionId2);
        assertTrue(uint8(distribution1.distributionStatus) == 2); // Reclaimed
        assertTrue(uint8(distribution2.distributionStatus) == 2); // Reclaimed
    }

    function test_reclaimRepo_anyoneCanReclaim() public {
        _fundRepo(FUND_AMOUNT);
        uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);

        // Move past claim deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        address randomUser = makeAddr("randomUser");

        // Random user should be able to reclaim expired repo distributions
        vm.prank(randomUser);
        escrow.reclaimRepo(distributionIds);

        // Check distribution was reclaimed
        Escrow.Distribution memory distribution = escrow.getDistribution(distributionId);
        assertTrue(uint8(distribution.distributionStatus) == 2); // Reclaimed
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

    function test_reclaimRepo_fuzz_amounts(uint256 amount1, uint256 amount2) public {
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
        escrow.reclaimRepo(distributionIds);
        
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), initialRepoBalance + amount1 + amount2);
    }

    /* -------------------------------------------------------------------------- */
    /*                                    EVENTS                                  */
    /* -------------------------------------------------------------------------- */

    event ReclaimedRepo(uint256 indexed repoId, uint256 indexed distributionId, address indexed admin, uint256 amount);
} 