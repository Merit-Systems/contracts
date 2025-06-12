// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "./00_Escrow.t.sol";

contract Claim_Test is Base_Test {
    
    uint256 constant REPO_ID = 1;
    uint256 constant ACCOUNT_ID = 100;
    uint256 constant DISTRIBUTION_AMOUNT = 1000e18;
    uint32 constant CLAIM_PERIOD = 7 days;

    address repoAdmin;
    address recipient;
    address claimer;

    uint256 adminPrivateKey = 0x1111111111111111111111111111111111111111111111111111111111111111;
    uint256 signerPrivateKey = 0x4646464646464646464646464646464646464646464646464646464646464646; // owner is signer in setup
    
    function setUp() public override {
        super.setUp();
        
        repoAdmin = vm.addr(adminPrivateKey);
        recipient = makeAddr("recipient");
        claimer = makeAddr("claimer");
        
        // Initialize and fund repo
        _initializeAndFundRepo();
    }

    function _initializeAndFundRepo() internal {
        // Initialize repo
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

        // Fund repo
        wETH.mint(address(this), DISTRIBUTION_AMOUNT * 10);
        wETH.approve(address(escrow), DISTRIBUTION_AMOUNT * 10);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, DISTRIBUTION_AMOUNT * 10);
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
        address payer = makeAddr("payer");
        wETH.mint(payer, amount);
        vm.prank(payer);
        wETH.approve(address(escrow), amount);

        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: amount,
            recipient: _recipient,
            claimPeriod: CLAIM_PERIOD,
            token: wETH
        });

        vm.prank(payer);
        uint[] memory distributionIds = escrow.distributeSolo(distributions);
        return distributionIds[0];
    }

    function _signClaim(uint[] memory distributionIds, address _recipient, uint256 deadline) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.CLAIM_TYPEHASH(),
                    keccak256(abi.encode(distributionIds)),
                    _recipient,
                    escrow.recipientNonce(_recipient),
                    deadline
                ))
            )
        );
        
        return vm.sign(signerPrivateKey, digest);
    }

    /* -------------------------------------------------------------------------- */
    /*                                CLAIM TESTS                                 */
    /* -------------------------------------------------------------------------- */

    function test_claim_success_singleDistribution() public {
        uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

        uint256 expectedFee = (DISTRIBUTION_AMOUNT * escrow.fee()) / 10000;
        uint256 expectedNetAmount = DISTRIBUTION_AMOUNT - expectedFee;

        uint256 initialRecipientBalance = wETH.balanceOf(recipient);
        uint256 initialFeeRecipientBalance = wETH.balanceOf(escrow.feeRecipient());

        vm.expectEmit(true, true, true, true);
        emit Claimed(distributionId, recipient, expectedNetAmount, escrow.fee());

        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s);

        // Check balances
        assertEq(wETH.balanceOf(recipient), initialRecipientBalance + expectedNetAmount);
        assertEq(wETH.balanceOf(escrow.feeRecipient()), initialFeeRecipientBalance + expectedFee);

        // Check distribution status
        Escrow.Distribution memory distribution = escrow.getDistribution(distributionId);
        assertTrue(uint8(distribution.distributionStatus) == 1); // Claimed

        // Check nonce was incremented
        assertEq(escrow.recipientNonce(recipient), 1);
    }

    function test_claim_success_multipleDistributions() public {
        uint256 amount1 = 500e18;
        uint256 amount2 = 750e18;
        uint256 amount3 = 250e18;

        uint256 distributionId1 = _createRepoDistribution(recipient, amount1);
        uint256 distributionId2 = _createSoloDistribution(recipient, amount2);
        uint256 distributionId3 = _createRepoDistribution(recipient, amount3);

        uint[] memory distributionIds = new uint[](3);
        distributionIds[0] = distributionId1;
        distributionIds[1] = distributionId2;
        distributionIds[2] = distributionId3;

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

        uint256 totalAmount = amount1 + amount2 + amount3;
        uint256 expectedFee = (totalAmount * escrow.fee()) / 10000;
        uint256 expectedNetAmount = totalAmount - expectedFee;

        uint256 initialRecipientBalance = wETH.balanceOf(recipient);

        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s);

        // Check recipient received correct net amount
        assertEq(wETH.balanceOf(recipient), initialRecipientBalance + expectedNetAmount);

        // Check all distributions are marked as claimed
        for (uint i = 0; i < 3; i++) {
            Escrow.Distribution memory distribution = escrow.getDistribution(distributionIds[i]);
            assertTrue(uint8(distribution.distributionStatus) == 1); // Claimed
        }
    }

    function test_claim_zeroFee() public {
        // Set fee to 0
        vm.prank(owner);
        escrow.setFee(0);

        uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

        uint256 initialRecipientBalance = wETH.balanceOf(recipient);
        uint256 initialFeeRecipientBalance = wETH.balanceOf(escrow.feeRecipient());

        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s);

        // Should receive full amount with no fee
        assertEq(wETH.balanceOf(recipient), initialRecipientBalance + DISTRIBUTION_AMOUNT);
        assertEq(wETH.balanceOf(escrow.feeRecipient()), initialFeeRecipientBalance); // No change
    }

    function test_claim_revert_expiredSignature() public {
        uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        uint256 deadline = block.timestamp - 1; // Expired
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

        expectRevert(Errors.SIGNATURE_EXPIRED);
        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s);
    }

    function test_claim_revert_invalidSignature() public {
        uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        uint256 deadline = block.timestamp + 1 hours;
        uint256 wrongPrivateKey = 0x2222222222222222222222222222222222222222222222222222222222222222;
        
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.CLAIM_TYPEHASH(),
                    keccak256(abi.encode(distributionIds)),
                    recipient,
                    escrow.recipientNonce(recipient),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, digest);

        expectRevert(Errors.INVALID_SIGNATURE);
        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s);
    }

    function test_claim_revert_emptyDistributions() public {
        uint[] memory distributionIds = new uint[](0);
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

        expectRevert(Errors.INVALID_AMOUNT);
        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s);
    }

    function test_claim_revert_batchLimitExceeded() public {
        uint256 batchLimit = escrow.batchLimit();
        uint[] memory distributionIds = new uint[](batchLimit + 1);
        
        // Create more distributions than batch limit
        for (uint i = 0; i < batchLimit + 1; i++) {
            distributionIds[i] = _createRepoDistribution(recipient, 1e18);
        }

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

        expectRevert(Errors.BATCH_LIMIT_EXCEEDED);
        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s);
    }

    function test_claim_revert_invalidDistributionId() public {
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = 999; // Non-existent distribution

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

        expectRevert(Errors.INVALID_DISTRIBUTION_ID);
        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s);
    }

    function test_claim_revert_alreadyClaimed() public {
        uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

        // First claim should succeed
        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s);

        // Second claim should fail
        (uint8 v2, bytes32 r2, bytes32 s2) = _signClaim(distributionIds, recipient, deadline);
        expectRevert(Errors.ALREADY_CLAIMED);
        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v2, r2, s2);
    }

    function test_claim_revert_invalidRecipient() public {
        uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, claimer, deadline); // Sign for claimer

        expectRevert(Errors.INVALID_RECIPIENT);
        vm.prank(claimer); // But distribution is for recipient
        escrow.claim(distributionIds, deadline, v, r, s);
    }

    function test_claim_revert_claimDeadlinePassed() public {
        uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        // Move past claim deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

        expectRevert(Errors.CLAIM_DEADLINE_PASSED);
        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s);
    }

    function test_claim_fuzz_amounts(uint256 amount1, uint256 amount2) public {
        // Ensure amounts are reasonable to avoid fee > amount scenarios
        vm.assume(amount1 > 1000 && amount1 <= 1000e18);
        vm.assume(amount2 > 1000 && amount2 <= 1000e18);

        // Additional check to ensure each amount can cover at least the fee
        uint256 fee1 = (amount1 * escrow.fee() + 9999) / 10000;
        uint256 fee2 = (amount2 * escrow.fee() + 9999) / 10000;
        vm.assume(amount1 > fee1);
        vm.assume(amount2 > fee2);

        uint256 distributionId1 = _createRepoDistribution(recipient, amount1);
        uint256 distributionId2 = _createSoloDistribution(recipient, amount2);

        uint[] memory distributionIds = new uint[](2);
        distributionIds[0] = distributionId1;
        distributionIds[1] = distributionId2;

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

        // Calculate expected fee using mulDivUp like the contract does
        uint256 expectedTotalFee = fee1 + fee2;
        uint256 expectedNetAmount = (amount1 + amount2) - expectedTotalFee;

        uint256 initialBalance = wETH.balanceOf(recipient);

        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s);

        assertEq(wETH.balanceOf(recipient), initialBalance + expectedNetAmount);
    }

    function test_claim_nonceIncrement() public {
        uint256 distributionId1 = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        uint256 distributionId2 = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);

        uint[] memory distributionIds1 = new uint[](1);
        distributionIds1[0] = distributionId1;

        uint[] memory distributionIds2 = new uint[](1);
        distributionIds2[0] = distributionId2;

        uint256 deadline = block.timestamp + 1 hours;

        // First claim
        (uint8 v1, bytes32 r1, bytes32 s1) = _signClaim(distributionIds1, recipient, deadline);
        vm.prank(recipient);
        escrow.claim(distributionIds1, deadline, v1, r1, s1);
        assertEq(escrow.recipientNonce(recipient), 1);

        // Second claim (nonce should be incremented)
        (uint8 v2, bytes32 r2, bytes32 s2) = _signClaim(distributionIds2, recipient, deadline);
        vm.prank(recipient);
        escrow.claim(distributionIds2, deadline, v2, r2, s2);
        assertEq(escrow.recipientNonce(recipient), 2);
    }

    function test_claim_maxBatchLimit() public {
        uint256 batchLimit = escrow.batchLimit();
        uint[] memory distributionIds = new uint[](batchLimit);
        
        // Create exactly batch limit distributions
        for (uint i = 0; i < batchLimit; i++) {
            distributionIds[i] = _createRepoDistribution(recipient, 1e18);
        }

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s);

        // All should be claimed
        for (uint i = 0; i < batchLimit; i++) {
            Escrow.Distribution memory distribution = escrow.getDistribution(distributionIds[i]);
            assertTrue(uint8(distribution.distributionStatus) == 1); // Claimed
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                                    EVENTS                                  */
    /* -------------------------------------------------------------------------- */

    event Claimed(
        uint256 indexed distributionId,
        address indexed recipient,
        uint256 amount,
        uint256 fee
    );
} 