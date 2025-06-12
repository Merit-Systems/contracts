// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "./Escrow.t.sol";

contract OnlyOwner_Test is Base_Test {
    
    address newToken;
    address newRecipient;
    address newSigner;
    address unauthorized;

    function setUp() public override {
        super.setUp();
        
        newToken = address(new MockERC20("New Token", "NEW", 18));
        newRecipient = makeAddr("newRecipient");
        newSigner = makeAddr("newSigner");
        unauthorized = makeAddr("unauthorized");
    }

    /* -------------------------------------------------------------------------- */
    /*                           ADD WHITELISTED TOKEN TESTS                      */
    /* -------------------------------------------------------------------------- */

    function test_addWhitelistedToken_success() public {
        assertFalse(escrow.isTokenWhitelisted(newToken));

        vm.expectEmit(true, false, false, false);
        emit TokenWhitelisted(newToken);

        vm.prank(owner);
        escrow.addWhitelistedToken(newToken);

        assertTrue(escrow.isTokenWhitelisted(newToken));
        
        // Check it's in the list
        address[] memory tokens = escrow.getAllWhitelistedTokens();
        bool found = false;
        for (uint i = 0; i < tokens.length; i++) {
            if (tokens[i] == newToken) {
                found = true;
                break;
            }
        }
        assertTrue(found);
    }

    function test_addWhitelistedToken_multiple() public {
        address token1 = address(new MockERC20("Token1", "T1", 18));
        address token2 = address(new MockERC20("Token2", "T2", 18));
        address token3 = address(new MockERC20("Token3", "T3", 18));

        vm.prank(owner);
        escrow.addWhitelistedToken(token1);

        vm.prank(owner);
        escrow.addWhitelistedToken(token2);

        vm.prank(owner);
        escrow.addWhitelistedToken(token3);

        assertTrue(escrow.isTokenWhitelisted(token1));
        assertTrue(escrow.isTokenWhitelisted(token2));
        assertTrue(escrow.isTokenWhitelisted(token3));

        address[] memory tokens = escrow.getAllWhitelistedTokens();
        assertEq(tokens.length, 4); // 3 new + 1 from setup (wETH)
    }

    function test_addWhitelistedToken_revert_notOwner() public {
        expectRevert("UNAUTHORIZED");
        vm.prank(unauthorized);
        escrow.addWhitelistedToken(newToken);
    }

    function test_addWhitelistedToken_revert_alreadyWhitelisted() public {
        vm.prank(owner);
        escrow.addWhitelistedToken(newToken);

        expectRevert(Errors.TOKEN_ALREADY_WHITELISTED);
        vm.prank(owner);
        escrow.addWhitelistedToken(newToken);
    }

    function test_addWhitelistedToken_revert_alreadyWhitelistedFromSetup() public {
        // wETH is already whitelisted in setup
        expectRevert(Errors.TOKEN_ALREADY_WHITELISTED);
        vm.prank(owner);
        escrow.addWhitelistedToken(address(wETH));
    }

    /* -------------------------------------------------------------------------- */
    /*                                SET FEE TESTS                               */
    /* -------------------------------------------------------------------------- */

    function test_setFee_success() public {
        uint256 newFee = 500; // 5%
        assertEq(escrow.fee(), 250); // Initial fee from setup

        vm.prank(owner);
        escrow.setFee(newFee);

        assertEq(escrow.fee(), newFee);
    }

    function test_setFee_zeroFee() public {
        vm.prank(owner);
        escrow.setFee(0);

        assertEq(escrow.fee(), 0);
    }

    function test_setFee_maxFee() public {
        uint256 maxFee = escrow.MAX_FEE_BPS(); // 10%

        vm.prank(owner);
        escrow.setFee(maxFee);

        assertEq(escrow.fee(), maxFee);
    }

    function test_setFee_revert_notOwner() public {
        expectRevert("UNAUTHORIZED");
        vm.prank(unauthorized);
        escrow.setFee(500);
    }

    function test_setFee_revert_exceedsMaxFee() public {
        uint256 invalidFee = escrow.MAX_FEE_BPS() + 1;

        expectRevert(Errors.INVALID_FEE_BPS);
        vm.prank(owner);
        escrow.setFee(invalidFee);
    }

    function test_setFee_fuzz(uint256 fee) public {
        vm.assume(fee <= escrow.MAX_FEE_BPS());

        vm.prank(owner);
        escrow.setFee(fee);

        assertEq(escrow.fee(), fee);
    }

    /* -------------------------------------------------------------------------- */
    /*                           SET FEE RECIPIENT TESTS                          */
    /* -------------------------------------------------------------------------- */

    function test_setFeeRecipient_success() public {
        assertEq(escrow.feeRecipient(), owner); // Initial from setup

        vm.prank(owner);
        escrow.setFeeRecipient(newRecipient);

        assertEq(escrow.feeRecipient(), newRecipient);
    }

    function test_setFeeRecipient_setToZeroAddress() public {
        // Contract allows setting to zero address (might be intentional)
        vm.prank(owner);
        escrow.setFeeRecipient(address(0));

        assertEq(escrow.feeRecipient(), address(0));
    }

    function test_setFeeRecipient_setBackToOwner() public {
        vm.prank(owner);
        escrow.setFeeRecipient(newRecipient);

        vm.prank(owner);
        escrow.setFeeRecipient(owner);

        assertEq(escrow.feeRecipient(), owner);
    }

    function test_setFeeRecipient_revert_notOwner() public {
        expectRevert("UNAUTHORIZED");
        vm.prank(unauthorized);
        escrow.setFeeRecipient(newRecipient);
    }

    /* -------------------------------------------------------------------------- */
    /*                             SET SIGNER TESTS                               */
    /* -------------------------------------------------------------------------- */

    function test_setSigner_success() public {
        assertEq(escrow.signer(), owner); // Initial from setup

        vm.prank(owner);
        escrow.setSigner(newSigner);

        assertEq(escrow.signer(), newSigner);
    }

    function test_setSigner_setToZeroAddress() public {
        // Contract allows setting to zero address (might be intentional)
        vm.prank(owner);
        escrow.setSigner(address(0));

        assertEq(escrow.signer(), address(0));
    }

    function test_setSigner_setBackToOwner() public {
        vm.prank(owner);
        escrow.setSigner(newSigner);

        vm.prank(owner);
        escrow.setSigner(owner);

        assertEq(escrow.signer(), owner);
    }

    function test_setSigner_revert_notOwner() public {
        expectRevert("UNAUTHORIZED");
        vm.prank(unauthorized);
        escrow.setSigner(newSigner);
    }

    /* -------------------------------------------------------------------------- */
    /*                           SET BATCH LIMIT TESTS                            */
    /* -------------------------------------------------------------------------- */

    function test_setBatchLimit_success() public {
        uint256 currentLimit = escrow.batchLimit();
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

    /* -------------------------------------------------------------------------- */
    /*                              INTEGRATION TESTS                             */
    /* -------------------------------------------------------------------------- */

    function test_onlyOwner_multipleChanges() public {
        // Change multiple settings in sequence
        address token1 = address(new MockERC20("Test1", "T1", 18));
        address token2 = address(new MockERC20("Test2", "T2", 18));

        vm.startPrank(owner);
        
        // Add tokens
        escrow.addWhitelistedToken(token1);
        escrow.addWhitelistedToken(token2);
        
        // Change fee settings
        escrow.setFee(750);
        escrow.setFeeRecipient(newRecipient);
        
        // Change operational settings
        escrow.setSigner(newSigner);
        escrow.setBatchLimit(25);
        
        vm.stopPrank();

        // Verify all changes
        assertTrue(escrow.isTokenWhitelisted(token1));
        assertTrue(escrow.isTokenWhitelisted(token2));
        assertEq(escrow.fee(), 750);
        assertEq(escrow.feeRecipient(), newRecipient);
        assertEq(escrow.signer(), newSigner);
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
        escrow.setFee(500);

        // New owner should be able to make changes
        vm.prank(newOwner);
        escrow.setFee(500);
        
        assertEq(escrow.fee(), 500);
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
            escrow.addWhitelistedToken(newToken);

            expectRevert("UNAUTHORIZED");
            vm.prank(user);
            escrow.setFee(500);

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

    event TokenWhitelisted(address indexed token);
    event BatchLimitSet(uint256 newBatchLimit);
} 