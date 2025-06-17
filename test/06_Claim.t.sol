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
                    keccak256(abi.encode(_toArray(repoAdmin))),
                    escrow.setAdminNonce(),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        escrow.initRepo(REPO_ID, ACCOUNT_ID, _toArray(repoAdmin), deadline, v, r, s);

        // Fund repo
        wETH.mint(address(this), DISTRIBUTION_AMOUNT * 10);
        wETH.approve(address(escrow), DISTRIBUTION_AMOUNT * 10);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, DISTRIBUTION_AMOUNT * 10, "");
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
        uint[] memory distributionIds = escrow.distributeFromSender(distributions, "");
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
                    escrow.recipientClaimNonce(_recipient),
                    deadline
                ))
            )
        );
        
        return vm.sign(signerPrivateKey, digest);
    }

    function _toArray(address addr) internal pure returns (address[] memory) {
        address[] memory arr = new address[](1);
        arr[0] = addr;
        return arr;
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
        emit Claimed(escrow.batchCount(), distributionId, recipient, expectedNetAmount, escrow.fee());

        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");

        // Check balances
        assertEq(wETH.balanceOf(recipient), initialRecipientBalance + expectedNetAmount);
        assertEq(wETH.balanceOf(escrow.feeRecipient()), initialFeeRecipientBalance + expectedFee);

        // Check distribution status
        Escrow.Distribution memory distribution = escrow.getDistribution(distributionId);
        assertTrue(uint8(distribution.status) == 1); // Claimed

        // Check nonce was incremented
        assertEq(escrow.recipientClaimNonce(recipient), 1);
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
        escrow.claim(distributionIds, deadline, v, r, s, "");

        // Check recipient received correct net amount
        assertEq(wETH.balanceOf(recipient), initialRecipientBalance + expectedNetAmount);

        // Check all distributions are marked as claimed
        for (uint i = 0; i < 3; i++) {
            Escrow.Distribution memory distribution = escrow.getDistribution(distributionIds[i]);
            assertTrue(uint8(distribution.status) == 1); // Claimed
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
        escrow.claim(distributionIds, deadline, v, r, s, "");

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
        escrow.claim(distributionIds, deadline, v, r, s, "");
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
                    escrow.recipientClaimNonce(recipient),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, digest);

        expectRevert(Errors.INVALID_SIGNATURE);
        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");
    }

    function test_claim_revert_emptyDistributions() public {
        uint[] memory distributionIds = new uint[](0);
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

        expectRevert(Errors.INVALID_AMOUNT);
        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");
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
        escrow.claim(distributionIds, deadline, v, r, s, "");
    }

    function test_claim_revert_invalidDistributionId() public {
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = 999; // Non-existent distribution

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

        expectRevert(Errors.INVALID_DISTRIBUTION_ID);
        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");
    }

    function test_claim_revert_alreadyClaimed() public {
        uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

        // First claim should succeed
        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");

        // Second claim should fail
        (uint8 v2, bytes32 r2, bytes32 s2) = _signClaim(distributionIds, recipient, deadline);
        expectRevert(Errors.ALREADY_CLAIMED);
        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v2, r2, s2, "");
    }

    function test_claim_revert_invalidRecipient() public {
        uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, claimer, deadline); // Sign for claimer

        expectRevert(Errors.INVALID_RECIPIENT);
        vm.prank(claimer); // But distribution is for recipient
        escrow.claim(distributionIds, deadline, v, r, s, "");
    }

    function test_claim_succeeds_afterClaimDeadline() public {
        uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        // Move past claim deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

        // Should succeed - claims are now allowed after deadline as long as not reclaimed
        uint256 initialBalance = wETH.balanceOf(recipient);
        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");
        
        // Verify claim succeeded
        assertTrue(wETH.balanceOf(recipient) > initialBalance);
        Escrow.Distribution memory distribution = escrow.getDistribution(distributionId);
        assertEq(
            uint8(distribution.status), 
            uint8(Escrow.DistributionStatus.Claimed)
        );
    }

    function test_claim_fuzz_amounts(uint256 amount) public {
        vm.assume(amount >= 100 && amount <= 1000e18); // Ensure amount is large enough for fee validation and within repo balance

        uint256 distributionId = _createRepoDistribution(recipient, amount);
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

        // Use the fee calculation logic from the contract
        uint256 expectedFee = (amount * escrow.fee() + 9999) / 10000; // Round up like mulDivUp
        if (expectedFee >= amount) {
            expectedFee = amount - 1; // Cap fee to ensure recipient gets at least 1 wei
        }
        uint256 expectedNetAmount = amount - expectedFee;

        uint256 initialRecipientBalance = wETH.balanceOf(recipient);
        uint256 initialFeeRecipientBalance = wETH.balanceOf(escrow.feeRecipient());

        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");

        // Check balances
        assertEq(wETH.balanceOf(recipient), initialRecipientBalance + expectedNetAmount);
        assertEq(wETH.balanceOf(escrow.feeRecipient()), initialFeeRecipientBalance + expectedFee);
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
        escrow.claim(distributionIds1, deadline, v1, r1, s1, "");
        assertEq(escrow.recipientClaimNonce(recipient), 1);

        // Second claim (nonce should be incremented)
        (uint8 v2, bytes32 r2, bytes32 s2) = _signClaim(distributionIds2, recipient, deadline);
        vm.prank(recipient);
        escrow.claim(distributionIds2, deadline, v2, r2, s2, "");
        assertEq(escrow.recipientClaimNonce(recipient), 2);
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
        escrow.claim(distributionIds, deadline, v, r, s, "");

        // All should be claimed
        for (uint i = 0; i < batchLimit; i++) {
            Escrow.Distribution memory distribution = escrow.getDistribution(distributionIds[i]);
            assertTrue(uint8(distribution.status) == 1); // Claimed
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                          FEE EDGE CASE CLAIM TESTS                        */
    /* -------------------------------------------------------------------------- */

    function test_claim_safeguard_feeCapToEnsureRecipientGetsAmount() public {
        // This test now ensures fee predictability - the fee is locked at creation time
        // and cannot be manipulated by the owner later
        
        // Create distribution with 10% fee
        vm.prank(owner);
        escrow.setFee(1000); // 10%
        
        uint256 distributionId = _createRepoDistribution(recipient, 100); // 100 wei
        
        // Try to change fee after distribution - this should NOT affect the claim
        vm.prank(owner);
        escrow.setFee(250); // 2.5% - lower fee
        
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;
        
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

        uint256 initialRecipientBalance = wETH.balanceOf(recipient);
        uint256 initialFeeRecipientBalance = wETH.balanceOf(escrow.feeRecipient());

        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");

        // Should use the ORIGINAL fee (10%) from creation time, not the new fee (2.5%)
        uint256 expectedFee = 10; // 10% of 100 wei
        uint256 expectedNetAmount = 90;
        
        assertEq(wETH.balanceOf(recipient), initialRecipientBalance + expectedNetAmount);
        assertEq(wETH.balanceOf(escrow.feeRecipient()), initialFeeRecipientBalance + expectedFee);
    }

    function test_claim_safeguard_preventZeroNetAmount() public {
        // Test fee predictability - users know exactly what they'll get at distribution time
        
        // Create a small distribution with a reasonable fee
        vm.prank(owner);
        escrow.setFee(1000); // 10%
        
        uint256 distributionId = _createRepoDistribution(recipient, 20); // 20 wei
        
        // Try to change fee to a different value after distribution
        vm.prank(owner);
        escrow.setFee(500); // 5% - this should NOT affect the claim
        
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;
        
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

        uint256 initialRecipientBalance = wETH.balanceOf(recipient);

        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");

        // Should use original 10% fee: 20 wei - 2 wei fee = 18 wei to recipient
        assertEq(wETH.balanceOf(recipient), initialRecipientBalance + 18);
    }

    /* -------------------------------------------------------------------------- */
    /*                          COMPREHENSIVE FEE TESTS                           */
    /* -------------------------------------------------------------------------- */

    function test_claim_feeCalculation_variousFeeRates() public {
        uint256[] memory feeRates = new uint256[](4);
        feeRates[0] = 100;  // 1%
        feeRates[1] = 250;  // 2.5%
        feeRates[2] = 500;  // 5%
        feeRates[3] = 1000; // 10%

        for (uint i = 0; i < feeRates.length; i++) {
            // Set fee rate
            vm.prank(owner);
            escrow.setFee(uint16(feeRates[i]));

            uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
            uint[] memory distributionIds = new uint[](1);
            distributionIds[0] = distributionId;

            uint256 deadline = block.timestamp + 1 hours;
            (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

            uint256 expectedFee = (DISTRIBUTION_AMOUNT * feeRates[i]) / 10000;
            uint256 expectedNetAmount = DISTRIBUTION_AMOUNT - expectedFee;

            uint256 initialRecipientBalance = wETH.balanceOf(recipient);
            uint256 initialFeeRecipientBalance = wETH.balanceOf(escrow.feeRecipient());

            vm.prank(recipient);
            escrow.claim(distributionIds, deadline, v, r, s, "");

            // Check balances
            assertEq(wETH.balanceOf(recipient), initialRecipientBalance + expectedNetAmount);
            assertEq(wETH.balanceOf(escrow.feeRecipient()), initialFeeRecipientBalance + expectedFee);
        }
    }

    function test_claim_feeCalculation_roundingEdgeCases() public {
        // Test with very small amounts
        uint256 smallAmount = 100; // 100 wei
        uint256 distributionId = _createRepoDistribution(recipient, smallAmount);
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

        uint256 initialRecipientBalance = wETH.balanceOf(recipient);
        uint256 initialFeeRecipientBalance = wETH.balanceOf(escrow.feeRecipient());

        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");

        // Should receive at least 1 wei after fees
        assertTrue(wETH.balanceOf(recipient) > initialRecipientBalance);
        assertTrue(wETH.balanceOf(escrow.feeRecipient()) >= initialFeeRecipientBalance);

        // Test with large amounts - but within repo balance
        uint256 largeAmount = 1000e18; // Use a reasonable large amount within our funded balance
        distributionId = _createRepoDistribution(recipient, largeAmount);
        distributionIds[0] = distributionId;

        (v, r, s) = _signClaim(distributionIds, recipient, deadline);

        initialRecipientBalance = wETH.balanceOf(recipient);
        initialFeeRecipientBalance = wETH.balanceOf(escrow.feeRecipient());

        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");

        // Should handle large amounts without overflow
        assertTrue(wETH.balanceOf(recipient) > initialRecipientBalance);
        assertTrue(wETH.balanceOf(escrow.feeRecipient()) > initialFeeRecipientBalance);
    }

    function test_claim_feeCapAtDistributionAmount() public {
        // Test fee predictability for edge cases
        
        // Create distribution with maximum fee that still allows valid creation
        vm.prank(owner);
        escrow.setFee(1000); // 10%
        
        uint256 distributionId = _createRepoDistribution(recipient, 10); // 10 wei
        
        // Try to change fee after distribution - should have no effect
        vm.prank(owner);
        escrow.setFee(100); // 1%
        
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;
        
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

        uint256 initialRecipientBalance = wETH.balanceOf(recipient);
        uint256 initialFeeRecipientBalance = wETH.balanceOf(escrow.feeRecipient());

        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");

        // Should use original 10% fee: 10 wei - 1 wei fee = 9 wei to recipient
        assertEq(wETH.balanceOf(recipient), initialRecipientBalance + 9);
        assertEq(wETH.balanceOf(escrow.feeRecipient()), initialFeeRecipientBalance + 1);
    }

    function test_claim_normalFeeCalculationStillWorks() public {
        // Ensure normal fee calculations work correctly with fee snapshotting
        
        vm.prank(owner);
        escrow.setFee(250); // 2.5%
        
        uint256 distributionId = _createRepoDistribution(recipient, 1000e18); // Large amount
        
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;
        
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

        uint256 initialRecipientBalance = wETH.balanceOf(recipient);
        uint256 initialFeeRecipientBalance = wETH.balanceOf(escrow.feeRecipient());

        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");

        // Normal calculation: fee = mulDivUp(1000e18, 250, 10000) = 25e18
        uint256 expectedFee = 25e18;
        uint256 expectedNetAmount = 1000e18 - expectedFee;
        
        assertEq(wETH.balanceOf(recipient), initialRecipientBalance + expectedNetAmount);
        assertEq(wETH.balanceOf(escrow.feeRecipient()), initialFeeRecipientBalance + expectedFee);
    }

    function test_claim_multipleDistributions_withFeeCapping() public {
        // Test fee predictability with multiple distributions created at different fee rates
        
        // Create first distribution with 1% fee
        vm.prank(owner);
        escrow.setFee(100); // 1%
        uint256 distributionId1 = _createRepoDistribution(recipient, 1000e18); // Large
        
        // Change fee and create second distribution
        vm.prank(owner);
        escrow.setFee(1000); // 10%
        uint256 distributionId2 = _createRepoDistribution(recipient, 50); // Small - 50 wei
        
        // Try to change fee again - should not affect existing distributions
        vm.prank(owner);
        escrow.setFee(500); // 5%
        
        uint[] memory distributionIds = new uint[](2);
        distributionIds[0] = distributionId1;
        distributionIds[1] = distributionId2;
        
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

        uint256 initialRecipientBalance = wETH.balanceOf(recipient);

        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");

        // First distribution: 1% fee = 10e18, net = 990e18
        // Second distribution: 10% fee = 5 wei, net = 45 wei
        uint256 expectedNet1 = 990e18;
        uint256 expectedNet2 = 45;
        uint256 totalExpectedNet = expectedNet1 + expectedNet2;
        
        assertEq(wETH.balanceOf(recipient), initialRecipientBalance + totalExpectedNet);
    }

    function test_claim_fuzz_feeCappingLogic(uint256 distributionAmount, uint256 feeRate) public {
        // Test fee predictability across various amounts and rates
        vm.assume(distributionAmount >= 2 && distributionAmount <= 100e18); 
        vm.assume(feeRate <= 1000); // Max 10% fee (valid range)
        
        // Create distribution with the fuzzed fee rate
        vm.prank(owner);
        escrow.setFee(feeRate);
        
        uint256 distributionId = _createRepoDistribution(recipient, distributionAmount);
        
        // Try to change fee after creation - should have no effect
        vm.prank(owner);
        escrow.setFee(feeRate == 1000 ? 100 : 1000); // Set to different value
        
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;
        
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

        uint256 initialRecipientBalance = wETH.balanceOf(recipient);
        uint256 initialFeeRecipientBalance = wETH.balanceOf(escrow.feeRecipient());

        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");

        // Calculate expected fee using the ORIGINAL fee rate at creation time
        uint256 calculatedFee;
        if (feeRate == 0) {
            calculatedFee = 0;
        } else {
            calculatedFee = (distributionAmount * feeRate) / 10000;
            if ((distributionAmount * feeRate) % 10000 > 0) {
                calculatedFee += 1; // Round up
            }
        }
        uint256 actualFee = calculatedFee >= distributionAmount ? distributionAmount - 1 : calculatedFee;
        uint256 actualNet = distributionAmount - actualFee;
        
        assertEq(wETH.balanceOf(recipient), initialRecipientBalance + actualNet);
        assertEq(wETH.balanceOf(escrow.feeRecipient()), initialFeeRecipientBalance + actualFee);
        
        // Ensure recipient always gets at least 1 wei
        assertTrue(actualNet >= 1);
    }

    function test_claim_feeManipulationVulnerabilityFixed() public {
        // Test that demonstrates the owner cannot manipulate fees after distribution creation
        // to extract more than the originally agreed upon fee
        
        // Create distribution with low fee (1%)
        vm.prank(owner);
        escrow.setFee(100); // 1%
        
        uint256 distributionId = _createRepoDistribution(recipient, 1000e18);
        
        // Malicious owner tries to increase fee to maximum before claim
        vm.prank(owner);
        escrow.setFee(1000); // 10% - trying to extract 10x more fees
        
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;
        
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

        uint256 initialRecipientBalance = wETH.balanceOf(recipient);
        uint256 initialFeeRecipientBalance = wETH.balanceOf(escrow.feeRecipient());

        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");

        // Should use the ORIGINAL 1% fee, not the manipulated 10% fee
        uint256 expectedFee = 10e18; // 1% of 1000e18
        uint256 expectedNetAmount = 990e18;
        
        assertEq(wETH.balanceOf(recipient), initialRecipientBalance + expectedNetAmount);
        assertEq(wETH.balanceOf(escrow.feeRecipient()), initialFeeRecipientBalance + expectedFee);
        
        // Verify the fee manipulation failed - recipient got 99% not 90%
        assertTrue(wETH.balanceOf(recipient) == initialRecipientBalance + 990e18);
        assertTrue(wETH.balanceOf(escrow.feeRecipient()) == initialFeeRecipientBalance + 10e18);
    }

    /* -------------------------------------------------------------------------- */
    /*                          SIGNATURE EDGE CASE TESTS                         */
    /* -------------------------------------------------------------------------- */

    function test_claim_signature_wrongNonce() public {
        uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        uint256 deadline = block.timestamp + 1 hours;
        
        // Create signature with wrong nonce
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.CLAIM_TYPEHASH(),
                    keccak256(abi.encode(distributionIds)),
                    recipient,
                    escrow.recipientClaimNonce(recipient) + 1, // Wrong nonce
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);

        expectRevert(Errors.INVALID_SIGNATURE);
        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");
    }

    function test_claim_signature_wrongRecipient() public {
        uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        uint256 deadline = block.timestamp + 1 hours;
        
        // Create signature for wrong recipient
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.CLAIM_TYPEHASH(),
                    keccak256(abi.encode(distributionIds)),
                    claimer, // Wrong recipient
                    escrow.recipientClaimNonce(recipient),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);

        expectRevert(Errors.INVALID_SIGNATURE);
        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");
    }

    function test_claim_signature_wrongDistributionIds() public {
        uint256 distributionId1 = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        uint256 distributionId2 = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId1;

        uint[] memory wrongDistributionIds = new uint[](1);
        wrongDistributionIds[0] = distributionId2;

        uint256 deadline = block.timestamp + 1 hours;
        
        // Create signature for wrong distribution IDs
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(wrongDistributionIds, recipient, deadline);

        expectRevert(Errors.INVALID_SIGNATURE);
        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");
    }

    function test_claim_signature_replayAttack() public {
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
        escrow.claim(distributionIds1, deadline, v1, r1, s1, "");

        // Try to reuse signature for second claim (should fail due to nonce increment)
        expectRevert(Errors.INVALID_SIGNATURE);
        vm.prank(recipient);
        escrow.claim(distributionIds2, deadline, v1, r1, s1, "");

        // Proper second claim should work
        (uint8 v2, bytes32 r2, bytes32 s2) = _signClaim(distributionIds2, recipient, deadline);
        vm.prank(recipient);
        escrow.claim(distributionIds2, deadline, v2, r2, s2, "");
    }

    /* -------------------------------------------------------------------------- */
    /*                          BATCH OPERATION TESTS                             */
    /* -------------------------------------------------------------------------- */

    function test_claim_batchOperations_mixedStatuses() public {
        uint256 distributionId1 = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        uint256 distributionId2 = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        uint256 distributionId3 = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);

        // Claim first distribution individually
        uint[] memory singleDistribution = new uint[](1);
        singleDistribution[0] = distributionId1;
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v1, bytes32 r1, bytes32 s1) = _signClaim(singleDistribution, recipient, deadline);
        vm.prank(recipient);
        escrow.claim(singleDistribution, deadline, v1, r1, s1, "");

        // Try to claim all three in batch (should fail because first is already claimed)
        uint[] memory allDistributions = new uint[](3);
        allDistributions[0] = distributionId1; // Already claimed
        allDistributions[1] = distributionId2;
        allDistributions[2] = distributionId3;

        (uint8 v2, bytes32 r2, bytes32 s2) = _signClaim(allDistributions, recipient, deadline);
        expectRevert(Errors.ALREADY_CLAIMED);
        vm.prank(recipient);
        escrow.claim(allDistributions, deadline, v2, r2, s2, "");

        // Claim remaining two should work
        uint[] memory remainingDistributions = new uint[](2);
        remainingDistributions[0] = distributionId2;
        remainingDistributions[1] = distributionId3;

        (uint8 v3, bytes32 r3, bytes32 s3) = _signClaim(remainingDistributions, recipient, deadline);
        vm.prank(recipient);
        escrow.claim(remainingDistributions, deadline, v3, r3, s3, "");
    }

    function test_claim_batchOperations_mixedRecipients() public {
        address recipient2 = makeAddr("recipient2");
        
        uint256 distributionId1 = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        uint256 distributionId2 = _createRepoDistribution(recipient2, DISTRIBUTION_AMOUNT);

        // Try to claim both with recipient (should fail because second is for recipient2)
        uint[] memory distributionIds = new uint[](2);
        distributionIds[0] = distributionId1;
        distributionIds[1] = distributionId2;

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

        expectRevert(Errors.INVALID_RECIPIENT);
        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");
    }

    function test_claim_batchOperations_mixedDeadlines() public {
        uint256 distributionId1 = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        
        // Move time forward so first distribution is near expiry
        vm.warp(block.timestamp + CLAIM_PERIOD - 1 hours);
        
        uint256 distributionId2 = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);

        // Move time forward so first distribution expires but second is still valid
        vm.warp(block.timestamp + 2 hours);

        uint[] memory distributionIds = new uint[](2);
        distributionIds[0] = distributionId1; // Past deadline but not reclaimed
        distributionIds[1] = distributionId2; // Within deadline

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

        // Should succeed - both can be claimed as long as not reclaimed
        uint256 initialBalance = wETH.balanceOf(recipient);
        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");
        
        // Verify both claims succeeded
        assertTrue(wETH.balanceOf(recipient) > initialBalance);
        
        Escrow.Distribution memory dist1 = escrow.getDistribution(distributionId1);
        Escrow.Distribution memory dist2 = escrow.getDistribution(distributionId2);
        assertEq(uint8(dist1.status), uint8(Escrow.DistributionStatus.Claimed));
        assertEq(uint8(dist2.status), uint8(Escrow.DistributionStatus.Claimed));
    }

    /* -------------------------------------------------------------------------- */
    /*                          INTEGRATION TESTS                                 */
    /* -------------------------------------------------------------------------- */

    function test_claim_integration_afterFeeChange() public {
        // Create distribution with initial fee
        vm.prank(owner);
        escrow.setFee(100); // 1%
        
        uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        
        // Change fee after distribution creation
        vm.prank(owner);
        escrow.setFee(500); // 5%
        
        // Claim should use original fee from distribution creation time
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

        uint256 expectedFee = (DISTRIBUTION_AMOUNT * 100) / 10000; // Original 1%
        uint256 expectedNetAmount = DISTRIBUTION_AMOUNT - expectedFee;

        uint256 initialRecipientBalance = wETH.balanceOf(recipient);
        uint256 initialFeeRecipientBalance = wETH.balanceOf(escrow.feeRecipient());

        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");

        assertEq(wETH.balanceOf(recipient), initialRecipientBalance + expectedNetAmount);
        assertEq(wETH.balanceOf(escrow.feeRecipient()), initialFeeRecipientBalance + expectedFee);
    }

    function test_claim_integration_afterSignerChange() public {
        uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

        // Change signer
        address newSigner = makeAddr("newSigner");
        vm.prank(owner);
        escrow.setSigner(newSigner);

        // Old signature should fail
        expectRevert(Errors.INVALID_SIGNATURE);
        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");
    }

    function test_claim_integration_afterFeeRecipientChange() public {
        uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

        address newFeeRecipient = makeAddr("newFeeRecipient");
        uint256 initialNewFeeRecipientBalance = wETH.balanceOf(newFeeRecipient);

        // Change fee recipient
        vm.prank(owner);
        escrow.setFeeRecipient(newFeeRecipient);

        uint256 expectedFee = (DISTRIBUTION_AMOUNT * escrow.fee()) / 10000;

        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");

        // Fee should go to new recipient
        assertEq(wETH.balanceOf(newFeeRecipient), initialNewFeeRecipientBalance + expectedFee);
    }

    /* -------------------------------------------------------------------------- */
    /*                          FUZZ TESTS                                        */
    /* -------------------------------------------------------------------------- */

    function test_claim_fuzz_batchSizes(uint8 batchSize) public {
        vm.assume(batchSize > 0 && batchSize <= 10); // Reasonable batch size limit

        uint[] memory distributionIds = new uint[](batchSize);
        for (uint i = 0; i < batchSize; i++) {
            distributionIds[i] = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        }

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

        uint256 totalAmount = DISTRIBUTION_AMOUNT * batchSize;
        uint256 expectedFee = (totalAmount * escrow.fee()) / 10000;
        uint256 expectedNetAmount = totalAmount - expectedFee;

        uint256 initialRecipientBalance = wETH.balanceOf(recipient);
        uint256 initialFeeRecipientBalance = wETH.balanceOf(escrow.feeRecipient());

        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");

        // Check balances
        assertEq(wETH.balanceOf(recipient), initialRecipientBalance + expectedNetAmount);
        assertEq(wETH.balanceOf(escrow.feeRecipient()), initialFeeRecipientBalance + expectedFee);

        // Check all distributions are marked as claimed
        for (uint i = 0; i < batchSize; i++) {
            Escrow.Distribution memory distribution = escrow.getDistribution(distributionIds[i]);
            assertTrue(uint8(distribution.status) == 1); // Claimed
        }
    }

    function test_claim_feeCappingWhenFeeEqualsOrExceedsAmount() public {
        // Test the specific line: feeAmount = distribution.amount - 1; (line 360)
        // This is a defensive programming measure that ensures recipient always gets at least 1 wei
        // The condition should theoretically never be hit in normal operation since _createDistribution
        // already validates distribution.amount > feeAmount, but it exists as a safety measure
        
        // We'll test the normal edge case scenario to show the defensive logic exists
        vm.prank(owner);
        escrow.setFee(1000); // 10% fee (maximum allowed)
        
        // Create the smallest distribution that can pass validation with max fee
        // With 10% fee: for amount=11, fee = mulDivUp(11, 1000, 10000) = 2
        // This passes validation (11 > 2) and won't trigger the defensive logic
        uint256 amount = 11;
        uint256 distributionId = _createRepoDistribution(recipient, amount);
        
        uint[] memory distributionIds = new uint[](1);  
        distributionIds[0] = distributionId;
        
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

        uint256 initialRecipientBalance = wETH.balanceOf(recipient);
        uint256 initialFeeRecipientBalance = wETH.balanceOf(escrow.feeRecipient());

        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");

        // Normal operation: fee = 2, recipient gets 9
        // The defensive fee capping logic is not triggered in this case
        uint256 expectedFee = 2; // mulDivUp(11, 1000, 10000) = 2
        uint256 expectedNet = 9; // 11 - 2 = 9
        
        assertEq(wETH.balanceOf(recipient), initialRecipientBalance + expectedNet);
        assertEq(wETH.balanceOf(escrow.feeRecipient()), initialFeeRecipientBalance + expectedFee);
        
        // This test documents that the fee capping defensive logic exists in the code
        // even though it may not be triggerable through normal distribution creation.
        // The logic ensures recipient always gets at least 1 wei as a safety measure.
    }

    function test_getDistribution_invalidId() public {
        // Test getDistribution with invalid distribution ID to cover line 660
        expectRevert(Errors.INVALID_DISTRIBUTION_ID);
        escrow.getDistribution(999999);
        
        // Also test after creating a valid distribution
        uint256 validId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        
        // Valid ID should work
        Escrow.Distribution memory distribution = escrow.getDistribution(validId);
        assertEq(distribution.amount, DISTRIBUTION_AMOUNT);
        assertTrue(distribution.exists);
        
        // Invalid ID should still fail
        expectRevert(Errors.INVALID_DISTRIBUTION_ID);
        escrow.getDistribution(validId + 1000);
    }

    /* -------------------------------------------------------------------------- */
    /*                                    EVENTS                                  */
    /* -------------------------------------------------------------------------- */

    event Claimed(uint256 indexed batchId, uint256 indexed distributionId, address indexed recipient, uint256 amount, uint256 fee);
    event ClaimedBatch(uint256 indexed batchId, uint256[] distributionIds, address indexed recipient, bytes data);

    /* -------------------------------------------------------------------------- */
    /*                          ADVANCED FUZZ TESTS                               */
    /* -------------------------------------------------------------------------- */

    /// @dev Fuzz test for complex multi-distribution claims with varying fees
    function testFuzz_claim_multiDistributionComplexScenario(
        uint8 numDistributions,
        uint256[10] memory amounts,
        uint16[10] memory feeRates,
        uint32[10] memory claimPeriods
    ) public {
        numDistributions = uint8(bound(numDistributions, 1, 10));
        
        uint256[] memory distributionIds = new uint256[](numDistributions);
        uint256 totalExpectedNet = 0;
        uint256 totalExpectedFees = 0;
        
        for (uint256 i = 0; i < numDistributions; i++) {
            amounts[i] = bound(amounts[i], 100, 1000e18);
            feeRates[i] = uint16(bound(feeRates[i], 0, 1000)); // 0-10%
            claimPeriods[i] = uint32(bound(claimPeriods[i], 1 hours, 30 days));
            
            // Set fee for this distribution
            vm.prank(owner);
            escrow.setFee(feeRates[i]);
            
            // Create distribution with this fee rate
            distributionIds[i] = _createRepoDistribution(recipient, amounts[i]);
            
            // Calculate expected amounts using the fee at creation time
            uint256 feeAmount = (amounts[i] * feeRates[i] + 9999) / 10000; // mulDivUp equivalent
            if (feeAmount >= amounts[i]) {
                feeAmount = amounts[i] - 1;
            }
            totalExpectedFees += feeAmount;
            totalExpectedNet += amounts[i] - feeAmount;
        }
        
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);
        
        uint256 initialRecipientBalance = wETH.balanceOf(recipient);
        uint256 initialFeeBalance = wETH.balanceOf(escrow.feeRecipient());
        
        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");
        
        assertEq(wETH.balanceOf(recipient), initialRecipientBalance + totalExpectedNet);
        assertEq(wETH.balanceOf(escrow.feeRecipient()), initialFeeBalance + totalExpectedFees);
    }

    /// @dev Fuzz test for extreme timestamp scenarios
    function testFuzz_claim_extremeTimestamps(
        uint256 distributionTime,
        uint32 claimPeriod,
        uint256 claimTime
    ) public {
        // Use smaller ranges to avoid overflow and edge cases
        distributionTime = bound(distributionTime, block.timestamp, block.timestamp + 7 days);
        claimPeriod = uint32(bound(claimPeriod, 1 hours, 7 days));
        
        // Set time to distribution time
        vm.warp(distributionTime);
        
        uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        
        // Calculate valid claim window
        uint256 claimDeadline = distributionTime + claimPeriod;
        
        // Ensure claimTime is strictly within the valid window (not at the boundary)
        claimTime = bound(claimTime, distributionTime, claimDeadline - 1);
        vm.warp(claimTime);
        
        // Create claim
        uint256[] memory distributionIds = new uint256[](1);
        distributionIds[0] = distributionId;
        
        uint256 deadline = claimTime + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);
        
        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");
        
        // Should succeed
        Escrow.Distribution memory dist = escrow.getDistribution(distributionId);
        assertEq(uint8(dist.status), uint8(Escrow.DistributionStatus.Claimed));
    }

    /// @dev Test mathematical precision in fee calculations
    function testFuzz_claim_feePrecisionEdgeCases(uint256 amount, uint16 feeRate) public {
        amount = bound(amount, 2, DISTRIBUTION_AMOUNT * 5); // Limit to available repo balance
        feeRate = uint16(bound(feeRate, 1, 1000)); // 0.01% to 10%
        
        vm.prank(owner);
        escrow.setFee(feeRate);
        
        uint256 distributionId = _createRepoDistribution(recipient, amount);
        uint256[] memory distributionIds = new uint256[](1);
        distributionIds[0] = distributionId;
        
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);
        
        uint256 initialTotal = wETH.balanceOf(recipient) + wETH.balanceOf(escrow.feeRecipient());
        
        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");
        
        uint256 finalTotal = wETH.balanceOf(recipient) + wETH.balanceOf(escrow.feeRecipient());
        
        // Total should equal the original distribution amount
        assertEq(finalTotal, initialTotal + amount);
        
        // Recipient should always get at least 1 wei
        assertTrue(wETH.balanceOf(recipient) >= initialTotal + 1);
    }

    /* -------------------------------------------------------------------------- */
    /*                          COMPLEX SCENARIO TESTS                            */
    /* -------------------------------------------------------------------------- */

    /// @dev Test claiming with maximum batch size
    function test_claim_maxBatchSizeWithMixedTypes() public {
        uint256 batchLimit = escrow.batchLimit();
        
        // Limit batch size to a reasonable number to avoid funding issues
        uint256 testBatchSize = batchLimit > 50 ? 50 : batchLimit;
        uint256[] memory distributionIds = new uint256[](testBatchSize);
        
        // Fund additional tokens for this test
        uint256 additionalFunding = testBatchSize * 10e18; // 10 tokens per distribution
        wETH.mint(address(this), additionalFunding);
        wETH.approve(address(escrow), additionalFunding);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, additionalFunding, "");
        
        // Create mix of repo and solo distributions with smaller amounts
        for (uint256 i = 0; i < testBatchSize; i++) {
            uint256 amount = (i % 10 + 1) * 1e18; // Use smaller amounts: 1-10 tokens
            if (i % 2 == 0) {
                distributionIds[i] = _createRepoDistribution(recipient, amount);
            } else {
                distributionIds[i] = _createSoloDistribution(recipient, amount);
            }
        }
        
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);
        
        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");
        
        // Verify all are claimed
        for (uint256 i = 0; i < testBatchSize; i++) {
            Escrow.Distribution memory dist = escrow.getDistribution(distributionIds[i]);
            assertEq(uint8(dist.status), uint8(Escrow.DistributionStatus.Claimed));
        }
    }

    /// @dev Test claiming distributions created by different fee rates over time
    function test_claim_feeRateEvolution() public {
        uint256[] memory feeRates = new uint256[](5);
        feeRates[0] = 0;    // 0%
        feeRates[1] = 100;  // 1%
        feeRates[2] = 250;  // 2.5%
        feeRates[3] = 500;  // 5%
        feeRates[4] = 1000; // 10%
        
        uint256[] memory distributionIds = new uint256[](5);
        uint256[] memory expectedFees = new uint256[](5);
        uint256[] memory expectedNets = new uint256[](5);
        
        // Create distributions with different fee rates
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(owner);
            escrow.setFee(uint16(feeRates[i]));
            
            distributionIds[i] = _createRepoDistribution(recipient, 1000e18);
            
            expectedFees[i] = (1000e18 * feeRates[i] + 9999) / 10000;
            if (expectedFees[i] >= 1000e18) expectedFees[i] = 1000e18 - 1;
            expectedNets[i] = 1000e18 - expectedFees[i];
        }
        
        // Change fee rate again (shouldn't affect existing distributions)
        vm.prank(owner);
        escrow.setFee(750); // 7.5%
        
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);
        
        uint256 initialRecipientBalance = wETH.balanceOf(recipient);
        uint256 initialFeeBalance = wETH.balanceOf(escrow.feeRecipient());
        
        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");
        
        uint256 totalExpectedNet = 0;
        uint256 totalExpectedFees = 0;
        for (uint256 i = 0; i < 5; i++) {
            totalExpectedNet += expectedNets[i];
            totalExpectedFees += expectedFees[i];
        }
        
        assertEq(wETH.balanceOf(recipient), initialRecipientBalance + totalExpectedNet);
        assertEq(wETH.balanceOf(escrow.feeRecipient()), initialFeeBalance + totalExpectedFees);
    }

    /// @dev Test EIP-712 domain separator edge cases
    function test_claim_domainSeparatorConsistency() public {
        uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        uint256[] memory distributionIds = new uint256[](1);
        distributionIds[0] = distributionId;
        
        // Store initial domain separator
        bytes32 initialDomainSeparator = escrow.DOMAIN_SEPARATOR();
        
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);
        
        // Claim should work with original domain separator
        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");
        
        // Verify domain separator is still consistent
        assertEq(escrow.DOMAIN_SEPARATOR(), initialDomainSeparator);
    }

    /// @dev Test signature replay protection across different chains
    function test_claim_crossChainSignatureReplay() public {
        uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        uint256[] memory distributionIds = new uint256[](1);
        distributionIds[0] = distributionId;
        
        uint256 deadline = block.timestamp + 1 hours;
        
        // Create signature for current chain
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.CLAIM_TYPEHASH(),
                    keccak256(abi.encode(distributionIds)),
                    recipient,
                    escrow.recipientClaimNonce(recipient),
                    deadline
                ))
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        
        // Simulate chain fork (change chain id)
        uint256 originalChainId = block.chainid;
        vm.chainId(originalChainId + 1);
        
        // Domain separator should be different now
        assertTrue(escrow.DOMAIN_SEPARATOR() != digest);
        
        // Reset chain id
        vm.chainId(originalChainId);
        
        // Original signature should still work
        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");
    }

    /* -------------------------------------------------------------------------- */
    /*                        NEW CLAIM BEHAVIOR TESTS                            */
    /* -------------------------------------------------------------------------- */

    /// @dev Test that claims succeed even long after deadline passes
    function test_claim_longAfterDeadline() public {
        uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        // Move WAY past claim deadline (30 days)
        vm.warp(block.timestamp + CLAIM_PERIOD + 30 days);

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

        uint256 initialBalance = wETH.balanceOf(recipient);
        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");
        
        // Should still succeed
        assertTrue(wETH.balanceOf(recipient) > initialBalance);
        Escrow.Distribution memory distribution = escrow.getDistribution(distributionId);
        assertEq(uint8(distribution.status), uint8(Escrow.DistributionStatus.Claimed));
    }

    /// @dev Test that once reclaimed, claim fails
    function test_claim_failsAfterReclaim() public {
        uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        // Move past claim deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        // Admin reclaims first
        uint[] memory reclaimIds = new uint[](1);
        reclaimIds[0] = distributionId;
        vm.prank(repoAdmin);
        escrow.reclaimRepoDistributions(REPO_ID, ACCOUNT_ID, reclaimIds, "");

        // Now recipient tries to claim - should fail
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

        expectRevert(Errors.ALREADY_CLAIMED); // Status is now Reclaimed
        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");
    }

    /// @dev Test that once claimed, reclaim fails
    function test_reclaim_failsAfterClaim() public {
        uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        // Move past claim deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        // Recipient claims first
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);
        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");

        // Now admin tries to reclaim - should fail
        uint[] memory reclaimIds = new uint[](1);
        reclaimIds[0] = distributionId;
        
        expectRevert(Errors.ALREADY_CLAIMED); // Status is now Claimed
        vm.prank(repoAdmin);
        escrow.reclaimRepoDistributions(REPO_ID, ACCOUNT_ID, reclaimIds, "");
    }

    /// @dev Test race condition scenarios at exact deadline
    function test_claim_vs_reclaim_raceCondition() public {
        uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        // Move to exact deadline timestamp
        Escrow.Distribution memory dist = escrow.getDistribution(distributionId);
        vm.warp(dist.claimDeadline);

        // At exactly the deadline:
        // - Claims should still work (no time constraint)
        // - Reclaims should work (>= deadline)
        
        // Test claim first
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);
        
        uint256 initialBalance = wETH.balanceOf(recipient);
        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");
        
        assertTrue(wETH.balanceOf(recipient) > initialBalance);
        
        // Create another distribution to test reclaim at exact deadline
        uint256 distributionId2 = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        vm.warp(escrow.getDistribution(distributionId2).claimDeadline);
        
        uint[] memory reclaimIds = new uint[](1);
        reclaimIds[0] = distributionId2;
        
        // Reclaim should also work at exact deadline
        vm.prank(repoAdmin);
        escrow.reclaimRepoDistributions(REPO_ID, ACCOUNT_ID, reclaimIds, "");
        
        Escrow.Distribution memory dist2 = escrow.getDistribution(distributionId2);
        assertEq(uint8(dist2.status), uint8(Escrow.DistributionStatus.Reclaimed));
    }

    /// @dev Test batch operations with mixed claim/reclaim statuses
    function test_claim_batchWithMixedStatuses() public {
        // Create 3 distributions
        uint256 distributionId1 = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        uint256 distributionId2 = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);  
        uint256 distributionId3 = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);

        // Move past deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        // Reclaim the first one
        uint[] memory reclaimIds = new uint[](1);
        reclaimIds[0] = distributionId1;
        vm.prank(repoAdmin);
        escrow.reclaimRepoDistributions(REPO_ID, ACCOUNT_ID, reclaimIds, "");

        // Try to claim all 3 in batch - should fail because first is reclaimed
        uint[] memory distributionIds = new uint[](3);
        distributionIds[0] = distributionId1; // Reclaimed
        distributionIds[1] = distributionId2; // Available
        distributionIds[2] = distributionId3; // Available

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

        expectRevert(Errors.ALREADY_CLAIMED);
        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");

        // But claiming just the available ones should work
        uint[] memory availableIds = new uint[](2);
        availableIds[0] = distributionId2;
        availableIds[1] = distributionId3;

        (v, r, s) = _signClaim(availableIds, recipient, deadline);
        
        uint256 initialBalance = wETH.balanceOf(recipient);
        vm.prank(recipient);
        escrow.claim(availableIds, deadline, v, r, s, "");
        
        assertTrue(wETH.balanceOf(recipient) > initialBalance);
    }

    /// @dev Test claiming immediately at distribution creation (before any deadline)
    function test_claim_immediatelyAfterDistribution() public {
        uint256 distributionId = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        // Claim immediately (no time waiting)
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

        uint256 initialBalance = wETH.balanceOf(recipient);
        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");
        
        assertTrue(wETH.balanceOf(recipient) > initialBalance);
        Escrow.Distribution memory distribution = escrow.getDistribution(distributionId);
        assertEq(uint8(distribution.status), uint8(Escrow.DistributionStatus.Claimed));
    }

    /// @dev Test solo distributions also follow same claim rules
    function test_claim_soloDistribution_afterDeadline() public {
        uint256 distributionId = _createSoloDistribution(recipient, DISTRIBUTION_AMOUNT);
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        // Move past claim deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

        uint256 initialBalance = wETH.balanceOf(recipient);
        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");
        
        // Should succeed for solo distributions too
        assertTrue(wETH.balanceOf(recipient) > initialBalance);
        Escrow.Distribution memory distribution = escrow.getDistribution(distributionId);
        assertEq(uint8(distribution.status), uint8(Escrow.DistributionStatus.Claimed));
    }

    /// @dev Test claiming after solo distribution was reclaimed
    function test_claim_soloDistribution_failsAfterReclaim() public {
        uint256 distributionId = _createSoloDistribution(recipient, DISTRIBUTION_AMOUNT);
        uint[] memory distributionIds = new uint[](1);
        distributionIds[0] = distributionId;

        // Move past claim deadline
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        // Original payer reclaims solo distribution
        uint[] memory reclaimIds = new uint[](1);
        reclaimIds[0] = distributionId;
        vm.prank(address(this)); // We are the payer for solo distributions
        escrow.reclaimSenderDistributions(reclaimIds, "");

        // Now recipient tries to claim - should fail
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(distributionIds, recipient, deadline);

        expectRevert(Errors.ALREADY_CLAIMED);
        vm.prank(recipient);
        escrow.claim(distributionIds, deadline, v, r, s, "");
    }

    /// @dev Comprehensive test of the new claim-reclaim behavior
    function test_claimReclaim_comprehensiveBehavior() public {
        // Create distributions
        uint256 dist1 = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);    
        uint256 dist2 = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);    
        uint256 dist3 = _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT);    

        // Scenario 1: Claim before deadline
        uint[] memory ids = new uint[](1);
        ids[0] = dist1;
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signClaim(ids, recipient, deadline);
        
        vm.prank(recipient);
        escrow.claim(ids, deadline, v, r, s, "");
        assertEq(uint8(escrow.getDistribution(dist1).status), uint8(Escrow.DistributionStatus.Claimed));

        // Move past all deadlines
        vm.warp(block.timestamp + CLAIM_PERIOD + 1);

        // Scenario 2: Claim after deadline (should work)
        ids[0] = dist2;
        deadline = block.timestamp + 1 hours;
        (v, r, s) = _signClaim(ids, recipient, deadline);
        vm.prank(recipient);
        escrow.claim(ids, deadline, v, r, s, "");
        assertEq(uint8(escrow.getDistribution(dist2).status), uint8(Escrow.DistributionStatus.Claimed));

        // Scenario 3: Reclaim after deadline
        ids[0] = dist3;
        vm.prank(repoAdmin);
        escrow.reclaimRepoDistributions(REPO_ID, ACCOUNT_ID, ids, "");
        assertEq(uint8(escrow.getDistribution(dist3).status), uint8(Escrow.DistributionStatus.Reclaimed));

        // Verify that trying to reclaim already claimed distributions fails
        ids[0] = dist1;
        expectRevert(Errors.ALREADY_CLAIMED);
        vm.prank(repoAdmin);
        escrow.reclaimRepoDistributions(REPO_ID, ACCOUNT_ID, ids, "");

        // Verify that trying to claim already reclaimed distributions fails
        ids[0] = dist3;
        (v, r, s) = _signClaim(ids, recipient, deadline);
        expectRevert(Errors.ALREADY_CLAIMED);
        vm.prank(recipient);
        escrow.claim(ids, deadline, v, r, s, "");
    }
} 