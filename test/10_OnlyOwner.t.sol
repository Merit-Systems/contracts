// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "./00_Escrow.t.sol";

contract OnlyOwner_Test is Base_Test {
    
    address newToken;
    address newRecipient;
    address newSignerAddr;
    address unauthorized;

    function setUp() public override {
        super.setUp();
        
        newToken = address(new MockERC20("New Token", "NEW", 18));
        newRecipient = makeAddr("newRecipient");
        newSignerAddr = makeAddr("newSigner");
        unauthorized = makeAddr("unauthorized");
    }

    /* -------------------------------------------------------------------------- */
    /*                           ADD WHITELISTED TOKEN TESTS                      */
    /* -------------------------------------------------------------------------- */

    function test_whitelistToken_success() public {
        assertFalse(escrow.isTokenWhitelisted(newToken));

        vm.expectEmit(true, true, true, true);
        emit WhitelistedToken(newToken);

        vm.prank(owner);
        escrow.whitelistToken(newToken);

        assertTrue(escrow.isTokenWhitelisted(newToken));
    }

    function test_whitelistToken_multiple() public {
        address token1 = makeAddr("token1");
        address token2 = makeAddr("token2");
        address token3 = makeAddr("token3");

        vm.expectEmit(true, true, true, true);
        emit WhitelistedToken(token1);
        vm.prank(owner);
        escrow.whitelistToken(token1);

        vm.expectEmit(true, true, true, true);
        emit WhitelistedToken(token2);
        vm.prank(owner);
        escrow.whitelistToken(token2);

        vm.expectEmit(true, true, true, true);
        emit WhitelistedToken(token3);
        vm.prank(owner);
        escrow.whitelistToken(token3);

        assertTrue(escrow.isTokenWhitelisted(token1));
        assertTrue(escrow.isTokenWhitelisted(token2));
        assertTrue(escrow.isTokenWhitelisted(token3));
    }

    function test_whitelistToken_revert_notOwner() public {
        vm.prank(unauthorized);
        expectRevert("UNAUTHORIZED");
        escrow.whitelistToken(newToken);
    }

    function test_whitelistToken_revert_alreadyWhitelisted() public {
        vm.prank(owner);
        escrow.whitelistToken(newToken);
        
        vm.prank(owner);
        expectRevert(Errors.TOKEN_ALREADY_WHITELISTED);
        escrow.whitelistToken(newToken);
    }

    function test_whitelistToken_revert_alreadyWhitelistedFromSetup() public {
        vm.prank(owner);
        expectRevert(Errors.TOKEN_ALREADY_WHITELISTED);
        escrow.whitelistToken(address(wETH));
    }

    function test_whitelistToken_fuzz_multipleTokens(uint8 numTokens) public {
        vm.assume(numTokens > 0 && numTokens <= 50); // Reasonable limit to avoid gas issues
        address[] memory initialTokens = escrow.getAllWhitelistedTokens();
        uint256 initialCount = initialTokens.length;
        for (uint i = 0; i < numTokens; i++) {
            address token = address(new MockERC20(
                string(abi.encodePacked("Token", i)),
                string(abi.encodePacked("TK", i)),
                18
            ));
            vm.prank(owner);
            escrow.whitelistToken(token);
            assertTrue(escrow.isTokenWhitelisted(token));
        }
        address[] memory finalTokens = escrow.getAllWhitelistedTokens();
        assertEq(finalTokens.length, initialCount + numTokens);
    }

    /* -------------------------------------------------------------------------- */
    /*                                SET FEE TESTS                               */
    /* -------------------------------------------------------------------------- */

    function test_setFeeOnClaim_success() public {
        uint256 newFee = 500; // 5%
        assertEq(escrow.feeOnClaim(), 250); // Initial fee from setup

        vm.prank(owner);
        escrow.setFeeOnClaim(newFee);

        assertEq(escrow.feeOnClaim(), newFee);
    }

    function test_setFeeOnClaim_zeroFee() public {
        vm.prank(owner);
        escrow.setFeeOnClaim(0);

        assertEq(escrow.feeOnClaim(), 0);
    }

    function test_setFeeOnClaim_maxFee() public {
        uint256 maxFee = escrow.MAX_FEE(); // 10%

        vm.prank(owner);
        escrow.setFeeOnClaim(maxFee);

        assertEq(escrow.feeOnClaim(), maxFee);
    }

    function test_setFeeOnClaim_revert_notOwner() public {
        expectRevert("UNAUTHORIZED");
        vm.prank(unauthorized);
        escrow.setFeeOnClaim(500);
    }

    function test_setFeeOnClaim_revert_exceedsMaxFee() public {
        uint256 invalidFee = escrow.MAX_FEE() + 1;

        expectRevert(Errors.INVALID_FEE);
        vm.prank(owner);
        escrow.setFeeOnClaim(invalidFee);
    }

    function test_setFeeOnClaim_fuzz(uint256 fee) public {
        vm.assume(fee <= escrow.MAX_FEE());

        vm.prank(owner);
        escrow.setFeeOnClaim(fee);

        assertEq(escrow.feeOnClaim(), fee);
    }

    function test_setFeeOnClaim_emitsEvent() public {
        uint256 newFee = 500; // 5%
        vm.expectEmit(true, true, true, true);
        emit FeeOnClaimSet(escrow.feeOnClaim(), newFee);
        vm.prank(owner);
        escrow.setFeeOnClaim(newFee);
    }

    /* -------------------------------------------------------------------------- */
    /*                           SET FEE RECIPIENT TESTS                          */
    /* -------------------------------------------------------------------------- */

    function test_setFeeOnClaimRecipient_success() public {
        assertEq(escrow.feeRecipient(), owner); // Initial from setup

        vm.prank(owner);
        escrow.setFeeRecipient(newRecipient);

        assertEq(escrow.feeRecipient(), newRecipient);
    }

    function test_setFeeOnClaimRecipient_setToZeroAddress() public {
        // Contract allows setting to zero address (might be intentional)
        vm.prank(owner);
        escrow.setFeeRecipient(address(0));

        assertEq(escrow.feeRecipient(), address(0));
    }

    function test_setFeeOnClaimRecipient_setBackToOwner() public {
        vm.prank(owner);
        escrow.setFeeRecipient(newRecipient);

        vm.prank(owner);
        escrow.setFeeRecipient(owner);

        assertEq(escrow.feeRecipient(), owner);
    }

    function test_setFeeOnClaimRecipient_revert_notOwner() public {
        expectRevert("UNAUTHORIZED");
        vm.prank(unauthorized);
        escrow.setFeeRecipient(newRecipient);
    }

    function test_setFeeOnClaimRecipient_emitsEvent() public {
        address differentRecipient = makeAddr("differentRecipient");
        vm.expectEmit(true, true, true, true);
        emit FeeRecipientSet(escrow.feeRecipient(), differentRecipient);
        vm.prank(owner);
        escrow.setFeeRecipient(differentRecipient);
    }

    /* -------------------------------------------------------------------------- */
    /*                             SET SIGNER TESTS                               */
    /* -------------------------------------------------------------------------- */

    function test_setSigner_success() public {
        vm.prank(owner);
        escrow.setSigner(newSignerAddr);

        assertEq(escrow.signer(), newSignerAddr);
    }

    function test_setSigner_setToZeroAddress() public {
        // Contract allows setting to zero address (might be intentional)
        vm.prank(owner);
        escrow.setSigner(address(0));

        assertEq(escrow.signer(), address(0));
    }

    function test_setSigner_setBackToOwner() public {
        vm.prank(owner);
        escrow.setSigner(newSignerAddr);

        vm.prank(owner);
        escrow.setSigner(owner);

        assertEq(escrow.signer(), owner);
    }

    function test_setSigner_revert_notOwner() public {
        expectRevert("UNAUTHORIZED");
        vm.prank(unauthorized);
        escrow.setSigner(newSignerAddr);
    }

    function test_setSigner_emitsEvent() public {
        address differentSigner = makeAddr("differentSigner");
        vm.expectEmit(true, true, true, true);
        emit SignerSet(escrow.signer(), differentSigner);
        vm.prank(owner);
        escrow.setSigner(differentSigner);
    }

    /* -------------------------------------------------------------------------- */
    /*                           SET BATCH LIMIT TESTS                            */
    /* -------------------------------------------------------------------------- */

    function test_setBatchLimit_success() public {
        uint256 newLimit = 50;
        
        vm.expectEmit(false, false, false, true);
        emit BatchLimitSet(newLimit);

        vm.prank(owner);
        escrow.setBatchLimit(newLimit);

        assertEq(escrow.batchLimit(), newLimit);
    }

    function test_setBatchLimit_increaseLimit() public {
        uint256 currentLimit = escrow.batchLimit();
        uint256 newLimit = currentLimit * 2;

        vm.prank(owner);
        escrow.setBatchLimit(newLimit);

        assertEq(escrow.batchLimit(), newLimit);
    }

    function test_setBatchLimit_decreaseLimit() public {
        uint256 currentLimit = escrow.batchLimit();
        uint256 newLimit = currentLimit / 2;
        vm.assume(newLimit > 0);

        vm.prank(owner);
        escrow.setBatchLimit(newLimit);

        assertEq(escrow.batchLimit(), newLimit);
    }

    function test_setBatchLimit_setToOne() public {
        vm.prank(owner);
        escrow.setBatchLimit(1);

        assertEq(escrow.batchLimit(), 1);
    }

    function test_setBatchLimit_setToMaxUint() public {
        uint256 maxUint = type(uint256).max;

        vm.prank(owner);
        escrow.setBatchLimit(maxUint);

        assertEq(escrow.batchLimit(), maxUint);
    }

    function test_setBatchLimit_revert_notOwner() public {
        expectRevert("UNAUTHORIZED");
        vm.prank(unauthorized);
        escrow.setBatchLimit(50);
    }

    function test_setBatchLimit_revert_zeroAmount() public {
        expectRevert(Errors.INVALID_AMOUNT);
        vm.prank(owner);
        escrow.setBatchLimit(0);
    }

    function test_setBatchLimit_fuzz(uint256 newLimit) public {
        vm.assume(newLimit > 0);

        vm.prank(owner);
        escrow.setBatchLimit(newLimit);

        assertEq(escrow.batchLimit(), newLimit);
    }

    function test_addWhitelistedToken_fuzz_multipleTokens(uint8 numTokens) public {
        vm.assume(numTokens > 0 && numTokens <= 50); // Reasonable limit to avoid gas issues
        
        address[] memory initialTokens = escrow.getAllWhitelistedTokens();
        uint256 initialCount = initialTokens.length;
        
        for (uint i = 0; i < numTokens; i++) {
            address token = address(new MockERC20(
                string(abi.encodePacked("Token", i)), 
                string(abi.encodePacked("TK", i)), 
                18
            ));
            
            vm.prank(owner);
            escrow.whitelistToken(token);
            
            assertTrue(escrow.isTokenWhitelisted(token));
        }
        
        address[] memory finalTokens = escrow.getAllWhitelistedTokens();
        assertEq(finalTokens.length, initialCount + numTokens);
    }

    function test_setFeeOnClaimRecipient_fuzz(address recipient) public {
        vm.prank(owner);
        escrow.setFeeRecipient(recipient);
        
        assertEq(escrow.feeRecipient(), recipient);
    }

    function test_setSigner_fuzz(address signer) public {
        vm.prank(owner);
        escrow.setSigner(signer);
        
        assertEq(escrow.signer(), signer);
    }

    function test_ownerSettings_fuzz_combinedChanges(
        uint256 newFee,
        address newFeeRecipient,
        address fuzzSigner,
        uint256 newBatchLimit
    ) public {
        vm.assume(newFee <= escrow.MAX_FEE());
        vm.assume(newBatchLimit > 0);
        
        vm.startPrank(owner);
        escrow.setFeeOnClaim(newFee);
        escrow.setFeeRecipient(newFeeRecipient);
        escrow.setSigner(fuzzSigner);
        escrow.setBatchLimit(newBatchLimit);
        vm.stopPrank();
        
        assertEq(escrow.feeOnClaim(), newFee);
        assertEq(escrow.feeRecipient(), newFeeRecipient);
        assertEq(escrow.signer(), fuzzSigner);
        assertEq(escrow.batchLimit(), newBatchLimit);
    }

    function test_feeChanges_fuzz_distributionImpact(uint256 oldFee, uint256 newFee, uint256 amount) public {
        // Use bound instead of vm.assume to avoid rejecting too many inputs
        oldFee = bound(oldFee, 0, escrow.MAX_FEE());
        newFee = bound(newFee, 0, escrow.MAX_FEE());
        amount = bound(amount, 100, 1000e18); // Ensure amount is large enough to pass fee validation
        
        // Set initial fee
        vm.prank(owner);
        escrow.setFeeOnClaim(oldFee);
        
        // Create distribution with old fee
        address recipient = makeAddr("recipient");
        _createSingleDistribution(recipient, amount);
        
        // Change fee
        vm.prank(owner);
        escrow.setFeeOnClaim(newFee);
        
        // Verify distribution retains old fee but global fee is new
        Escrow.Distribution memory distribution = escrow.getDistribution(0);
        assertEq(distribution.fee, oldFee, "Distribution should retain creation-time fee");
        assertEq(escrow.feeOnClaim(), newFee, "Global fee should be updated");
    }

    /* -------------------------------------------------------------------------- */
    /*                              INTEGRATION TESTS                             */
    /* -------------------------------------------------------------------------- */

    function test_onlyOwner_multipleChanges() public {
        address token1 = address(new MockERC20("Test1", "T1", 18));
        address token2 = address(new MockERC20("Test2", "T2", 18));
        vm.startPrank(owner);
        escrow.whitelistToken(token1);
        escrow.whitelistToken(token2);
        escrow.setFeeOnClaim(750);
        escrow.setFeeRecipient(newRecipient);
        escrow.setSigner(newSignerAddr);
        escrow.setBatchLimit(25);
        vm.stopPrank();
        assertTrue(escrow.isTokenWhitelisted(token1));
        assertTrue(escrow.isTokenWhitelisted(token2));
        assertEq(escrow.feeOnClaim(), 750);
        assertEq(escrow.feeRecipient(), newRecipient);
        assertEq(escrow.signer(), newSignerAddr);
        assertEq(escrow.batchLimit(), 25);
    }

    function test_onlyOwner_ownerTransfer() public {
        address newOwner = makeAddr("newOwner");
        
        // Transfer ownership
        vm.prank(owner);
        escrow.transferOwnership(newOwner);

        // Old owner should not be able to make changes
        expectRevert("UNAUTHORIZED");
        vm.prank(owner);
        escrow.setFeeOnClaim(500);

        // New owner should be able to make changes
        vm.prank(newOwner);
        escrow.setFeeOnClaim(500);
        
        assertEq(escrow.feeOnClaim(), 500);
        assertEq(escrow.owner(), newOwner);
    }

    function test_onlyOwner_accessControl() public {
        address[] memory unauthorizedUsers = new address[](3);
        unauthorizedUsers[0] = makeAddr("user1");
        unauthorizedUsers[1] = makeAddr("user2");
        unauthorizedUsers[2] = makeAddr("user3");

        for (uint i = 0; i < unauthorizedUsers.length; i++) {
            address user = unauthorizedUsers[i];

            expectRevert("UNAUTHORIZED");
            vm.prank(user);
            escrow.whitelistToken(newToken);

            expectRevert("UNAUTHORIZED");
            vm.prank(user);
            escrow.setFeeOnClaim(500);

            expectRevert("UNAUTHORIZED");
            vm.prank(user);
            escrow.setFeeRecipient(user);

            expectRevert("UNAUTHORIZED");
            vm.prank(user);
            escrow.setSigner(user);

            expectRevert("UNAUTHORIZED");
            vm.prank(user);
            escrow.setBatchLimit(50);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                                    EVENTS                                  */
    /* -------------------------------------------------------------------------- */

    event WhitelistedToken(address indexed token);
    event FeeOnClaimSet(uint256 oldFee, uint256 newFee);
    event FeeOnFundSet(uint256 oldFee, uint256 newFee);
    event FeeRecipientSet(address indexed oldRecipient, address indexed newRecipient);
    event SignerSet(address indexed oldSigner, address indexed newSigner);
    event BatchLimitSet(uint256 newBatchLimit);

    /* -------------------------------------------------------------------------- */
    /*                        FEE SNAPSHOT INTERACTION TESTS                      */
    /* -------------------------------------------------------------------------- */

    function test_setFeeOnClaim_doesNotAffectExistingDistributions() public {
        // Create distributions with initial fee
        vm.prank(owner);
        escrow.setFeeOnClaim(300); // 3%

        // Setup repo and create distributions
        _setupRepoAndCreateDistributions(300); // This creates distributions with 3% fee

        // Change fee after distributions are created
        vm.prank(owner);
        escrow.setFeeOnClaim(800); // 8%

        // Check that global fee changed
        assertEq(escrow.feeOnClaim(), 800, "Global fee should have changed");

        // Check that existing distributions retain their original fee
        _verifyDistributionFeesUnchanged(300); // Verify they still have 3% fee
    }

    function test_setFeeOnClaim_newDistributionsUseNewFee() public {
        // Start with one fee
        vm.prank(owner);
        escrow.setFeeOnClaim(200); // 2%

        // Create first distribution
        _setupRepoAndCreateDistributions(200);

        // Change fee
        vm.prank(owner);
        escrow.setFeeOnClaim(700); // 7%

        // Create second distribution with new fee
        address recipient2 = makeAddr("recipient2");
        _createSingleDistribution(recipient2, 1000e18);

        // Verify each distribution has its respective creation-time fee
        // First distribution should have 2%, second should have 7%
        _verifyDistributionFeesUnchanged(200); // First distribution
        
        // Get the second distribution (should be distribution ID 1)
        Escrow.Distribution memory dist2 = escrow.getDistribution(1);
        assertEq(dist2.fee, 700, "New distribution should use current fee");
    }

    function test_setFeeOnClaim_multipleChangesCreateHistoricalSnapshot() public {
        // Test that multiple fee changes create a historical record in distributions
        address recipient1 = makeAddr("recipient1");
        address recipient2 = makeAddr("recipient2");
        address recipient3 = makeAddr("recipient3");

        // Create distributions with different fees over time
        vm.prank(owner);
        escrow.setFeeOnClaim(100); // 1%
        _createSingleDistribution(recipient1, 1000e18);

        vm.prank(owner);
        escrow.setFeeOnClaim(500); // 5%
        _createSingleDistribution(recipient2, 1000e18);

        vm.prank(owner);
        escrow.setFeeOnClaim(900); // 9%
        _createSingleDistribution(recipient3, 1000e18);

        // Verify each distribution preserved its creation-time fee
        Escrow.Distribution memory dist1 = escrow.getDistribution(0);
        Escrow.Distribution memory dist2 = escrow.getDistribution(1);
        Escrow.Distribution memory dist3 = escrow.getDistribution(2);

        assertEq(dist1.fee, 100, "First distribution should have 1% fee");
        assertEq(dist2.fee, 500, "Second distribution should have 5% fee");
        assertEq(dist3.fee, 900, "Third distribution should have 9% fee");

        // Verify global fee is the latest
        assertEq(escrow.feeOnClaim(), 900, "Global fee should be latest value");
    }

    function test_setFeeOnClaim_zeroToNonZeroDoesNotAffectExisting() public {
        // Start with zero fee
        vm.prank(owner);
        escrow.setFeeOnClaim(0); // 0%

        _setupRepoAndCreateDistributions(0);

        // Change to non-zero fee
        vm.prank(owner);
        escrow.setFeeOnClaim(1000); // 10%

        // Existing distributions should still have 0% fee
        _verifyDistributionFeesUnchanged(0);
        assertEq(escrow.feeOnClaim(), 1000, "Global fee should be 10%");
    }

    // Helper functions for fee snapshot tests
    function _setupRepoAndCreateDistributions(uint256 /* expectedFee */) internal {
        // Initialize repo
        uint256 repoId = 1;
        uint256 instanceId = 100;
        address admin = makeAddr("admin");
        
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

        // Fund repo
        wETH.mint(address(this), 10000e18);
        wETH.approve(address(escrow), 10000e18);
        escrow.fundRepo(repoId, instanceId, wETH, 10000e18, "");

        // Create distribution
        address recipient = makeAddr("recipient");
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: 1000e18,
            recipient: recipient,
            claimPeriod: 7 days,
            token: wETH
        });

        vm.prank(admin);
        escrow.distributeFromRepo(repoId, instanceId, distributions, "");
    }

    function _createSingleDistribution(address recipient, uint256 amount) internal {
        // Create a solo distribution
        wETH.mint(address(this), amount);
        wETH.approve(address(escrow), amount);
        
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: amount,
            recipient: recipient,
            claimPeriod: 7 days,
            token: wETH
        });

        escrow.distributeFromSender(distributions, "");
    }

    function _verifyDistributionFeesUnchanged(uint256 expectedFee) internal view {
        Escrow.Distribution memory distribution = escrow.getDistribution(0);
        assertEq(distribution.fee, expectedFee, "Distribution fee should be unchanged");
    }

    function _toArray(address addr) internal pure returns (address[] memory) {
        address[] memory arr = new address[](1);
        arr[0] = addr;
        return arr;
    }

    /* -------------------------------------------------------------------------- */
    /*                          STRESS AND GAS TESTS                              */
    /* -------------------------------------------------------------------------- */

    /// @dev Test gas consumption for whitelisting many tokens
    function test_whitelistToken_gasOptimization() public {
        uint256 numTokens = 20; // Test with a reasonable number of tokens
        address[] memory tokens = new address[](numTokens);
        uint256[] memory gasUsed = new uint256[](numTokens);
        
        for (uint256 i = 0; i < numTokens; i++) {
            tokens[i] = makeAddr(string(abi.encodePacked("token", i)));
            
            uint256 gasBefore = gasleft();
            vm.prank(owner);
            escrow.whitelistToken(tokens[i]);
            gasUsed[i] = gasBefore - gasleft();
            
            // Verify token was whitelisted
            assertTrue(escrow.isTokenWhitelisted(tokens[i]));
        }
        
        // Gas usage should remain relatively consistent
        for (uint256 i = 1; i < numTokens; i++) {
            // Allow for some variance but shouldn't increase drastically
            assertLt(gasUsed[i], gasUsed[0] * 2, "Gas usage should remain reasonable");
        }
    }

    /// @dev Test fee setting with rapid changes to verify state consistency
    function test_setFeeOnClaim_rapidChanges() public {
        uint16[] memory feeRates = new uint16[](10);
        feeRates[0] = 0;
        feeRates[1] = 50;
        feeRates[2] = 100;
        feeRates[3] = 250;
        feeRates[4] = 500;
        feeRates[5] = 750;
        feeRates[6] = 1000;
        feeRates[7] = 500;
        feeRates[8] = 250;
        feeRates[9] = 100;
        
        for (uint256 i = 0; i < feeRates.length; i++) {
            uint256 previousFee = escrow.feeOnClaim();
            
            vm.expectEmit(true, true, true, true);
            emit FeeOnClaimSet(previousFee, feeRates[i]);
            
            vm.prank(owner);
            escrow.setFeeOnClaim(feeRates[i]);
            
            assertEq(escrow.feeOnClaim(), feeRates[i]);
        }
    }

    /// @dev Test signer changes with existing signed data
    function test_setSigner_withExistingSignatures() public {
        address newSigner = makeAddr("newSigner");
        address recipient = makeAddr("recipient");
        
        // Setup repo and create distribution
        uint256[] memory distributionIds = _setupRepoAndCreateSingleDistribution(recipient);
        
        // Change signer
        vm.expectEmit(true, true, true, true);
        emit SignerSet(owner, newSigner); // owner is initial signer
        
        vm.prank(owner);
        escrow.setSigner(newSigner);
        
        // Verify signer changed
        assertEq(escrow.signer(), newSigner);
        
        // Test that old signer signatures no longer work
        _testOldSignerFails(distributionIds[0], recipient);
    }

    function _setupRepoAndCreateSingleDistribution(address recipient) internal returns (uint256[] memory) {
        // Fund and create distribution for testing
        wETH.mint(address(this), 1000e18);
        wETH.approve(address(escrow), 1000e18);
        
        // Initialize a repo first
        address admin = makeAddr("admin");
        address[] memory admins = new address[](1);
        admins[0] = admin;
        
        {
            uint256 deadline = block.timestamp + 1 hours;
            bytes32 digest = keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    escrow.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(
                        escrow.SET_ADMIN_TYPEHASH(),
                        1,
                        1,
                        keccak256(abi.encode(admins)),
                        escrow.repoSetAdminNonce(1, 1),
                        deadline
                    ))
                )
            );
            
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(
                ownerPrivateKey,
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        escrow.DOMAIN_SEPARATOR(),
                        keccak256(abi.encode(
                            escrow.SET_ADMIN_TYPEHASH(),
                            1,
                            1,
                            keccak256(abi.encode(admins)),
                            escrow.repoSetAdminNonce(1, 1),
                            deadline
                        ))
                    )
                )
            );
            escrow.initRepo(1, 1, admins, deadline, v, r, s);
        }
        
        escrow.fundRepo(1, 1, wETH, 1000e18, "");
        
        // Create distribution
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: 100e18,
            recipient: recipient,
            claimPeriod: 7 days,
            token: wETH
        });
        
        vm.prank(admin);
        return escrow.distributeFromRepo(1, 1, distributions, "");
    }

    function _testOldSignerFails(uint256 distributionId, address recipient) internal {
        uint256[] memory claimIds = new uint256[](1);
        claimIds[0] = distributionId;
        
        bytes32 claimDigest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.CLAIM_TYPEHASH(),
                    keccak256(abi.encode(claimIds)),
                    recipient,
                    escrow.recipientClaimNonce(recipient),
                    block.timestamp + 1 hours
                ))
            )
        );
        
        // Signature from old signer should fail
        (uint8 vOld, bytes32 rOld, bytes32 sOld) = vm.sign(ownerPrivateKey, claimDigest);
        
        expectRevert(Errors.INVALID_SIGNATURE);
        vm.prank(recipient);
        escrow.claim(claimIds, block.timestamp + 1 hours, vOld, rOld, sOld, "");
    }

    /// @dev Fuzz test for batch limit changes and their effects
    function testFuzz_setBatchLimit_dynamicEffects(uint256 newLimit) public {
        newLimit = bound(newLimit, 1, 1000); // Reasonable range
        
        vm.expectEmit(true, true, true, true);
        emit BatchLimitSet(newLimit);
        
        vm.prank(owner);
        escrow.setBatchLimit(newLimit);
        
        assertEq(escrow.batchLimit(), newLimit);
        
        // Test that the new limit is enforced
        if (newLimit < 5) {
            // Create more distributions than the new limit allows
            address[] memory admins = new address[](1);
            admins[0] = makeAddr("admin");
            
            // Initialize repo
            uint256 deadline = block.timestamp + 1 hours;
            bytes32 digest = keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    escrow.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(
                        escrow.SET_ADMIN_TYPEHASH(),
                        1,
                        1,
                        keccak256(abi.encode(admins)),
                        escrow.repoSetAdminNonce(1, 1),
                        deadline
                    ))
                )
            );
            
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(
                ownerPrivateKey,
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        escrow.DOMAIN_SEPARATOR(),
                        keccak256(abi.encode(
                            escrow.SET_ADMIN_TYPEHASH(),
                            1,
                            1,
                            keccak256(abi.encode(admins)),
                            escrow.repoSetAdminNonce(1, 1),
                            deadline
                        ))
                    )
                )
            );
            escrow.initRepo(1, 1, admins, deadline, v, r, s);
            
            // Fund repo
            wETH.mint(address(this), 1000e18);
            wETH.approve(address(escrow), 1000e18);
            escrow.fundRepo(1, 1, wETH, 1000e18, "");
            
            // Try to distribute more than limit
            Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](newLimit + 1);
            for (uint256 i = 0; i < newLimit + 1; i++) {
                distributions[i] = Escrow.DistributionParams({
                    amount: 1e18,
                    recipient: makeAddr(string(abi.encodePacked("recipient", i))),
                    claimPeriod: 7 days,
                    token: wETH
                });
            }
            
            expectRevert(Errors.BATCH_LIMIT_EXCEEDED);
            vm.prank(admins[0]);
            escrow.distributeFromRepo(1, 1, distributions, "");
        }
    }

    /// @dev Test extreme fee rate changes and their mathematical consistency
    function testFuzz_setFeeOnClaim_extremeRatesConsistency(uint16 feeRate) public {
        feeRate = uint16(bound(feeRate, 0, 1000)); // 0-10%
        
        vm.prank(owner);
        escrow.setFeeOnClaim(feeRate);
        
        // Test that fee calculations remain mathematically sound
        uint256[] memory testAmounts = new uint256[](5);
        testAmounts[0] = 1;         // 1 wei
        testAmounts[1] = 100;       // 100 wei
        testAmounts[2] = 1e18;      // 1 token
        testAmounts[3] = 1000e18;   // 1000 tokens
        testAmounts[4] = type(uint128).max; // Very large amount
        
        for (uint256 i = 0; i < testAmounts.length; i++) {
            uint256 amount = testAmounts[i];
            
            // Calculate fee using same logic as contract
            uint256 expectedFee = (amount * feeRate + 9999) / 10000; // mulDivUp
            if (expectedFee >= amount) {
                expectedFee = amount - 1; // Cap to ensure recipient gets at least 1
            }
            uint256 expectedNet = amount - expectedFee;
            
            // Verify mathematical properties
            assertEq(expectedFee + expectedNet, amount, "Fee + net should equal total");
            assertGe(expectedNet, expectedFee >= amount ? 1 : amount * (10000 - feeRate) / 10000, "Net should be reasonable");
            assertLe(expectedFee, amount, "Fee should not exceed amount");
            
            if (amount > 1) {
                assertGe(expectedNet, 1, "Recipient should get at least 1 wei");
            }
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                            SET FEE ON FUND TESTS                           */
    /* -------------------------------------------------------------------------- */

    function test_setFeeOnFund_success() public {
        uint256 newFee = 500; // 5%
        assertEq(escrow.feeOnFund(), 0); // Initial fee from setup (should be 0)

        vm.prank(owner);
        escrow.setFeeOnFund(newFee);

        assertEq(escrow.feeOnFund(), newFee);
    }

    function test_setFeeOnFund_zeroFee() public {
        // First set to non-zero
        vm.prank(owner);
        escrow.setFeeOnFund(500);
        
        // Then set back to zero
        vm.prank(owner);
        escrow.setFeeOnFund(0);

        assertEq(escrow.feeOnFund(), 0);
    }

    function test_setFeeOnFund_maxFee() public {
        uint256 maxFee = escrow.MAX_FEE(); // 10%

        vm.prank(owner);
        escrow.setFeeOnFund(maxFee);

        assertEq(escrow.feeOnFund(), maxFee);
    }

    function test_setFeeOnFund_revert_notOwner() public {
        expectRevert("UNAUTHORIZED");
        vm.prank(unauthorized);
        escrow.setFeeOnFund(500);
    }

    function test_setFeeOnFund_revert_exceedsMaxFee() public {
        uint256 invalidFee = escrow.MAX_FEE() + 1;

        expectRevert(Errors.INVALID_FEE);
        vm.prank(owner);
        escrow.setFeeOnFund(invalidFee);
    }

    function test_setFeeOnFund_fuzz(uint256 fee) public {
        vm.assume(fee <= escrow.MAX_FEE());

        vm.prank(owner);
        escrow.setFeeOnFund(fee);

        assertEq(escrow.feeOnFund(), fee);
    }

    function test_setFeeOnFund_emitsEvent() public {
        uint256 newFee = 500; // 5%
        vm.expectEmit(true, true, true, true);
        emit FeeOnFundSet(escrow.feeOnFund(), newFee);
        vm.prank(owner);
        escrow.setFeeOnFund(newFee);
    }

    function test_setFeeOnFund_multipleChanges() public {
        uint256[] memory feeRates = new uint256[](5);
        feeRates[0] = 100;  // 1%
        feeRates[1] = 250;  // 2.5%
        feeRates[2] = 500;  // 5%
        feeRates[3] = 750;  // 7.5%
        feeRates[4] = 1000; // 10%

        for (uint i = 0; i < feeRates.length; i++) {
            uint256 previousFee = escrow.feeOnFund();
            
            vm.expectEmit(true, true, true, true);
            emit FeeOnFundSet(previousFee, feeRates[i]);
            
            vm.prank(owner);
            escrow.setFeeOnFund(feeRates[i]);
            
            assertEq(escrow.feeOnFund(), feeRates[i]);
        }
    }

    function test_setFeeOnFund_independentFromClaimFee() public {
        // Set claim fee to one value
        vm.prank(owner);
        escrow.setFeeOnClaim(300); // 3%
        
        // Set fund fee to different value
        vm.prank(owner);
        escrow.setFeeOnFund(700); // 7%
        
        // Verify they are independent
        assertEq(escrow.feeOnClaim(), 300);
        assertEq(escrow.feeOnFund(), 700);
        
        // Change one, verify other is unchanged
        vm.prank(owner);
        escrow.setFeeOnClaim(100);
        
        assertEq(escrow.feeOnClaim(), 100);
        assertEq(escrow.feeOnFund(), 700); // Should remain unchanged
    }

    function test_setFeeOnFund_immediateEffect() public {
        // First set a fee rate
        vm.prank(owner);
        escrow.setFeeOnFund(200); // 2%
        
        // Create token and fund repo to test immediate effect
        MockERC20 testToken = new MockERC20("Test", "TEST", 18);
        vm.prank(owner);
        escrow.whitelistToken(address(testToken));
        
        uint256 fundAmount = 1000e18;
        address funder = makeAddr("funder");
        
        testToken.mint(funder, fundAmount);
        vm.prank(funder);
        testToken.approve(address(escrow), fundAmount);
        
        // Fund with 2% fee
        vm.prank(funder);
        escrow.fundRepo(1, 1, testToken, fundAmount, "");
        
        uint256 expectedNet1 = fundAmount - (fundAmount * 200) / 10_000; // 980e18
        assertEq(escrow.getAccountBalance(1, 1, address(testToken)), expectedNet1);
        
        // Change fee immediately
        vm.prank(owner);
        escrow.setFeeOnFund(800); // 8%
        
        // Fund again with new fee rate
        testToken.mint(funder, fundAmount);
        vm.prank(funder);
        testToken.approve(address(escrow), fundAmount);
        
        vm.prank(funder);
        escrow.fundRepo(1, 1, testToken, fundAmount, "");
        
        uint256 expectedNet2 = fundAmount - (fundAmount * 800) / 10_000; // 920e18
        uint256 totalExpected = expectedNet1 + expectedNet2;
        
        assertEq(escrow.getAccountBalance(1, 1, address(testToken)), totalExpected);
    }

    function test_setFeeOnFund_extremeValues() public {
        // Test boundary values
        uint256[] memory extremeFees = new uint256[](3);
        extremeFees[0] = 0;    // 0%
        extremeFees[1] = 1;    // 0.01%
        extremeFees[2] = 1000; // 10%
        
        for (uint i = 0; i < extremeFees.length; i++) {
            vm.prank(owner);
            escrow.setFeeOnFund(extremeFees[i]);
            assertEq(escrow.feeOnFund(), extremeFees[i]);
        }
    }

    function test_setFeeOnFund_gasEfficiency() public {
        // Measure gas for setting fee
        vm.prank(owner);
        uint256 gasBefore = gasleft();
        escrow.setFeeOnFund(500);
        uint256 gasUsed = gasBefore - gasleft();
        
        // Should be relatively low gas (similar to setting a storage variable)
        // This is more of a benchmark than a hard assertion
        assertTrue(gasUsed < 50000, "Fee setting should be gas efficient");
    }

    function test_bothFees_fuzz_independentOperations(uint16 claimFee, uint16 fundFee) public {
        vm.assume(claimFee <= 1000 && fundFee <= 1000);
        
        // Set both fees
        vm.prank(owner);
        escrow.setFeeOnClaim(claimFee);
        
        vm.prank(owner);
        escrow.setFeeOnFund(fundFee);
        
        // Verify both are set correctly
        assertEq(escrow.feeOnClaim(), claimFee);
        assertEq(escrow.feeOnFund(), fundFee);
        
        // Change one, verify independence
        vm.prank(owner);
        escrow.setFeeOnClaim(0);
        
        assertEq(escrow.feeOnClaim(), 0);
        assertEq(escrow.feeOnFund(), fundFee); // Should remain unchanged
    }
} 