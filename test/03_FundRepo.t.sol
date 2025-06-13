// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "./00_Escrow.t.sol";

contract FundRepo_Test is Base_Test {
    
    uint256 constant REPO_ID = 1;
    uint256 constant ACCOUNT_ID = 100;
    uint256 constant FUND_AMOUNT = 1000e18;

    function setUp() public override {
        super.setUp();
        
        // Give alice some tokens to fund with
        wETH.mint(alice, FUND_AMOUNT * 10);
        
        // Pre-approve the escrow contract
        vm.prank(alice);
        wETH.approve(address(escrow), type(uint256).max);
    }

    function test_fundRepo_success() public {
        uint256 initialEscrowBalance = wETH.balanceOf(address(escrow));
        uint256 initialAliceBalance = wETH.balanceOf(alice);
        uint256 initialAccountBalance = escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH));

        vm.expectEmit(true, true, true, true);
        emit FundedRepo(REPO_ID, address(wETH), alice, FUND_AMOUNT, "");

        vm.prank(alice);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, FUND_AMOUNT, "");

        // Check balances
        assertEq(wETH.balanceOf(address(escrow)), initialEscrowBalance + FUND_AMOUNT);
        assertEq(wETH.balanceOf(alice), initialAliceBalance - FUND_AMOUNT);
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), initialAccountBalance + FUND_AMOUNT);
    }

    function test_fundRepo_multipleFundings() public {
        uint256 firstAmount = 500e18;
        uint256 secondAmount = 300e18;

        vm.prank(alice);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, firstAmount, "");

        vm.prank(alice);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, secondAmount, "");

        // Should accumulate balances
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), firstAmount + secondAmount);
    }

    function test_fundRepo_differentRepos() public {
        uint256 repo1Amount = 400e18;
        uint256 repo2Amount = 600e18;
        uint256 REPO_ID_2 = 2;

        vm.prank(alice);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, repo1Amount, "");

        vm.prank(alice);
        escrow.fundRepo(REPO_ID_2, ACCOUNT_ID, wETH, repo2Amount, "");

        // Should have separate balances
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), repo1Amount);
        assertEq(escrow.getAccountBalance(REPO_ID_2, ACCOUNT_ID, address(wETH)), repo2Amount);
    }

    function test_fundRepo_differentAccounts() public {
        uint256 account1Amount = 400e18;
        uint256 account2Amount = 600e18;
        uint256 ACCOUNT_ID_2 = 200;

        vm.prank(alice);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, account1Amount, "");

        vm.prank(alice);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID_2, wETH, account2Amount, "");

        // Should have separate balances
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), account1Amount);
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID_2, address(wETH)), account2Amount);
    }

    function test_fundRepo_revert_invalidToken() public {
        MockERC20 nonWhitelistedToken = new MockERC20("Non-Whitelisted", "NWT", 18);
        nonWhitelistedToken.mint(alice, FUND_AMOUNT);
        
        vm.prank(alice);
        nonWhitelistedToken.approve(address(escrow), FUND_AMOUNT);

        expectRevert(Errors.INVALID_TOKEN);
        vm.prank(alice);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, nonWhitelistedToken, FUND_AMOUNT, "");
    }

    function test_fundRepo_revert_zeroAmount() public {
        expectRevert(Errors.INVALID_AMOUNT);
        vm.prank(alice);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, 0, "");
    }

    function test_fundRepo_revert_insufficientBalance() public {
        uint256 excessiveAmount = wETH.balanceOf(alice) + 1;

        expectRevert("TRANSFER_FROM_FAILED");
        vm.prank(alice);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, excessiveAmount, "");
    }

    function test_fundRepo_revert_insufficientAllowance() public {
        address charlie = makeAddr("charlie");
        wETH.mint(charlie, FUND_AMOUNT);
        
        // Charlie has tokens but hasn't approved the escrow
        expectRevert("TRANSFER_FROM_FAILED");
        vm.prank(charlie);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, FUND_AMOUNT, "");
    }

    function test_fundRepo_multipleUsers() public {
        uint256 aliceAmount = 400e18;
        uint256 bobAmount = 600e18;

        // Give bob some tokens and approve
        wETH.mint(bob, bobAmount);
        vm.prank(bob);
        wETH.approve(address(escrow), bobAmount);

        // Both users fund the same repo/account
        vm.prank(alice);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, aliceAmount, "");

        vm.prank(bob);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, bobAmount, "");

        // Should accumulate from both users
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), aliceAmount + bobAmount);
    }

    function test_fundRepo_fuzz_amount(uint256 amount) public {
        vm.assume(amount > 0 && amount <= FUND_AMOUNT * 10);
        
        vm.prank(alice);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, amount, "");

        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), amount);
    }

    function test_fundRepo_fuzz_repoAndAccountIds(uint256 repoId, uint256 accountId, uint256 amount) public {
        vm.assume(amount > 0 && amount <= 1000e18);
        vm.assume(repoId <= type(uint128).max && accountId <= type(uint128).max);
        
        vm.prank(alice);
        escrow.fundRepo(repoId, accountId, wETH, amount, "");
        
        assertEq(escrow.getAccountBalance(repoId, accountId, address(wETH)), amount);
    }

    function test_fundRepo_fuzz_multipleFundings(uint8 numFundings, uint256 baseAmount) public {
        vm.assume(numFundings > 0 && numFundings <= 20);
        vm.assume(baseAmount > 0 && baseAmount <= 50e18);
        
        uint256 totalAmount = 0;
        
        for (uint i = 0; i < numFundings; i++) {
            uint256 amount = baseAmount + (i * 1e18); // Vary amounts
            vm.prank(alice);
            escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, amount, abi.encodePacked("funding ", i));
            totalAmount += amount;
        }
        
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), totalAmount);
    }

    function test_fundRepo_fuzz_dataField(bytes calldata data) public {
        vm.assume(data.length <= 1000); // Reasonable data size limit
        uint256 amount = 100e18;
        
        vm.expectEmit(true, true, true, true);
        emit FundedRepo(REPO_ID, address(wETH), alice, amount, data);
        
        vm.prank(alice);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, amount, data);
        
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), amount);
    }

    function test_fundRepo_fuzz_multipleUsers(uint8 numUsers, uint256 amountPerUser) public {
        vm.assume(numUsers > 0 && numUsers <= 10);
        vm.assume(amountPerUser > 0 && amountPerUser <= 100e18);
        
        uint256 totalAmount = 0;
        
        for (uint i = 0; i < numUsers; i++) {
            address user = makeAddr(string(abi.encodePacked("user", i)));
            wETH.mint(user, amountPerUser);
            
            vm.startPrank(user);
            wETH.approve(address(escrow), amountPerUser);
            escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, amountPerUser, "");
            vm.stopPrank();
            
            totalAmount += amountPerUser;
        }
        
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), totalAmount);
    }

    // Event for testing
    event FundedRepo(uint256 indexed repoId, address indexed token, address indexed sender, uint256 amount, bytes data);
} 