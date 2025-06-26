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
        emit FundedRepo(REPO_ID, ACCOUNT_ID, address(wETH), alice, FUND_AMOUNT, 0, "");

        vm.prank(alice);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, FUND_AMOUNT, "");

        // Check balances
        assertEq(wETH.balanceOf(address(escrow)), initialEscrowBalance + FUND_AMOUNT);
        assertEq(wETH.balanceOf(alice), initialAliceBalance - FUND_AMOUNT);
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), initialAccountBalance + FUND_AMOUNT);
    }

    function test_fundRepo_trackingSingleFunder() public {
        uint256 fundAmount = 5000e18;
        
        // Fund with this contract as the funder
        wETH.mint(address(this), fundAmount * 2);
        wETH.approve(address(escrow), fundAmount * 2);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, fundAmount, "");
        
        // Check that funding contribution is tracked correctly
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), address(this)), fundAmount);
        
        // Fund again and verify accumulation
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, fundAmount, "");
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), address(this)), fundAmount * 2);
        
        // Total repo balance should also be correct
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), fundAmount * 2);
    }

    function test_fundRepo_trackingMultipleFunders() public {
        address funder1 = makeAddr("funder1");
        address funder2 = makeAddr("funder2");
        address funder3 = makeAddr("funder3");
        
        uint256 amount1 = 1000e18;
        uint256 amount2 = 2000e18;
        uint256 amount3 = 3000e18;
        
        // Fund from different addresses
        _fundRepoAs(funder1, amount1);
        _fundRepoAs(funder2, amount2);
        _fundRepoAs(funder3, amount3);
        
        // Verify individual contributions are tracked
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), funder1), amount1);
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), funder2), amount2);
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), funder3), amount3);
        
        // Verify total repo balance
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), amount1 + amount2 + amount3);
        
        // Verify non-funders have zero contribution
        address nonFunder = makeAddr("nonFunder");
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), nonFunder), 0);
    }

    function test_fundRepo_trackingMultipleTokens() public {
        // Create and whitelist a second token
        MockERC20 wBTC = new MockERC20("Wrapped Bitcoin", "wBTC", 8);
        vm.prank(owner);
        escrow.whitelistToken(address(wBTC));
        
        address funder = makeAddr("multiTokenFunder");
        uint256 ethAmount = 10e18;
        uint256 btcAmount = 5e8; // 5 BTC with 8 decimals
        
        // Fund with ETH
        wETH.mint(funder, ethAmount);
        vm.prank(funder);
        wETH.approve(address(escrow), ethAmount);
        vm.prank(funder);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, ethAmount, "ETH funding");
        
        // Fund with BTC
        wBTC.mint(funder, btcAmount);
        vm.prank(funder);
        wBTC.approve(address(escrow), btcAmount);
        vm.prank(funder);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wBTC, btcAmount, "BTC funding");
        
        // Verify separate token tracking
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), funder), ethAmount);
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wBTC), funder), btcAmount);
        
        // Verify repo balances
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), ethAmount);
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wBTC)), btcAmount);
        
        // Fund more of the same tokens to test accumulation
        wETH.mint(funder, ethAmount); // Mint additional tokens
        vm.prank(funder);
        wETH.approve(address(escrow), ethAmount);
        vm.prank(funder);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, ethAmount, "More ETH");
        
        wBTC.mint(funder, btcAmount); // Mint additional tokens
        vm.prank(funder);
        wBTC.approve(address(escrow), btcAmount);
        vm.prank(funder);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wBTC, btcAmount, "More BTC");
        
        // Verify accumulation
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), funder), ethAmount * 2);
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wBTC), funder), btcAmount * 2);
    }

    function test_fundRepo_trackingAcrossRepos() public {
        address funder = makeAddr("crossRepoFunder");
        uint256 amount = 1000e18;
        
        // Fund repo 1
        _fundRepoAs(funder, REPO_ID, ACCOUNT_ID, amount);
        
        // Initialize and fund repo 2
        uint256 repoId2 = 999;
        uint256 instanceId2 = 888;
        address admin2 = makeAddr("admin2");
        
        address[] memory admins = new address[](1);
        admins[0] = admin2;
        
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    repoId2,
                    instanceId2,
                    keccak256(abi.encode(admins)),
                    escrow.repoSetAdminNonce(repoId2, instanceId2),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        escrow.initRepo(repoId2, instanceId2, admins, deadline, v, r, s);
        
        _fundRepoAs(funder, repoId2, instanceId2, amount * 2);
        
        // Verify separate tracking per repo
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), funder), amount);
        assertEq(escrow.getFunding(repoId2, instanceId2, address(wETH), funder), amount * 2);
        
        // Verify repo balances are separate
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), amount);
        assertEq(escrow.getAccountBalance(repoId2, instanceId2, address(wETH)), amount * 2);
    }

    function test_fundRepo_complexFundingScenario() public {
        // Setup multiple funders, tokens, and repos
        address[] memory funders = new address[](3);
        funders[0] = makeAddr("alice");
        funders[1] = makeAddr("bob");
        funders[2] = makeAddr("charlie");
        
        // Create second token
        MockERC20 wBTC = new MockERC20("Wrapped Bitcoin", "wBTC", 8);
        vm.prank(owner);
        escrow.whitelistToken(address(wBTC));
        
        // Complex funding pattern
        // Alice: 1000 ETH + 2 BTC
        _fundRepoAs(funders[0], 1000e18);
        wBTC.mint(funders[0], 2e8);
        vm.prank(funders[0]);
        wBTC.approve(address(escrow), 2e8);
        vm.prank(funders[0]);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wBTC, 2e8, "");
        
        // Bob: 2000 ETH only
        _fundRepoAs(funders[1], 2000e18);
        
        // Charlie: 3 BTC only
        wBTC.mint(funders[2], 3e8);
        vm.prank(funders[2]);
        wBTC.approve(address(escrow), 3e8);
        vm.prank(funders[2]);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wBTC, 3e8, "");
        
        // Alice funds more
        _fundRepoAs(funders[0], 500e18);
        wBTC.mint(funders[0], 1e8);
        vm.prank(funders[0]);
        wBTC.approve(address(escrow), 1e8);
        vm.prank(funders[0]);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wBTC, 1e8, "");
        
        // Verify final state
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), funders[0]), 1500e18); // Alice: 1000 + 500
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), funders[1]), 2000e18); // Bob: 2000
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), funders[2]), 0);       // Charlie: 0
        
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wBTC), funders[0]), 3e8);     // Alice: 2 + 1
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wBTC), funders[1]), 0);       // Bob: 0
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wBTC), funders[2]), 3e8);     // Charlie: 3
        
        // Verify total repo balances
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), 3500e18); // 1500 + 2000 + 0
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wBTC)), 6e8);     // 3 + 0 + 3
    }

    function _fundRepoAs(address funder, uint256 amount) internal {
        wETH.mint(funder, amount);
        vm.prank(funder);
        wETH.approve(address(escrow), amount);
        vm.prank(funder);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, amount, "");
    }

    function _fundRepoAs(address funder, uint256 repoId, uint256 instanceId, uint256 amount) internal {
        wETH.mint(funder, amount);
        vm.prank(funder);
        wETH.approve(address(escrow), amount);
        vm.prank(funder);
        escrow.fundRepo(repoId, instanceId, wETH, amount, "");
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

    function test_fundRepo_fuzz_repoAndInstanceIds(uint256 repoId, uint256 instanceId, uint256 amount) public {
        vm.assume(repoId <= type(uint128).max && instanceId <= type(uint128).max);
        vm.assume(amount > 0 && amount <= type(uint128).max);
        
        // Mint tokens for the test contract and approve
        wETH.mint(address(this), amount);
        wETH.approve(address(escrow), amount);

        escrow.fundRepo(repoId, instanceId, wETH, amount, "");

        assertEq(escrow.getAccountBalance(repoId, instanceId, address(wETH)), amount);
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
        emit FundedRepo(REPO_ID, ACCOUNT_ID, address(wETH), alice, amount, 0, data);
        
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

    /* -------------------------------------------------------------------------- */
    /*                            FEE ON FUND TESTS                              */
    /* -------------------------------------------------------------------------- */

    function test_fundRepo_withFee_basic() public {
        // Set 5% fee on fund
        vm.prank(owner);
        escrow.setFeeOnFund(500); // 5%
        
        uint256 fundAmount = 1000e18;
        uint256 expectedFee = (fundAmount * 500) / 10_000; // 5% = 50e18
        uint256 expectedNet = fundAmount - expectedFee; // 950e18
        
        uint256 initialFeeRecipientBalance = wETH.balanceOf(owner);
        uint256 initialEscrowBalance = wETH.balanceOf(address(escrow));
        
        vm.expectEmit(true, true, true, true);
        emit FundedRepo(REPO_ID, ACCOUNT_ID, address(wETH), alice, expectedNet, expectedFee, "fee test");
        
        vm.prank(alice);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, fundAmount, "fee test");
        
        // Verify fee recipient received the fee
        assertEq(wETH.balanceOf(owner), initialFeeRecipientBalance + expectedFee);
        
        // Verify escrow received net amount
        assertEq(wETH.balanceOf(address(escrow)), initialEscrowBalance + expectedNet);
        
        // Verify account balance tracks net amount
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), expectedNet);
        
        // Verify funding tracks net amount (for reclaim purposes)
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), alice), expectedNet);
    }

    function test_fundRepo_withFee_zeroFee() public {
        // Set 0% fee
        vm.prank(owner);
        escrow.setFeeOnFund(0);
        
        uint256 fundAmount = 1000e18;
        
        vm.expectEmit(true, true, true, true);
        emit FundedRepo(REPO_ID, ACCOUNT_ID, address(wETH), alice, fundAmount, 0, "");
        
        vm.prank(alice);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, fundAmount, "");
        
        // With 0% fee, full amount should go to account
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), fundAmount);
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), alice), fundAmount);
    }

    function test_fundRepo_withFee_maxFee() public {
        // Set maximum fee (10%)
        vm.prank(owner);
        escrow.setFeeOnFund(1000); // 10%
        
        uint256 fundAmount = 1000e18;
        uint256 expectedFee = (fundAmount * 1000) / 10_000; // 10% = 100e18
        uint256 expectedNet = fundAmount - expectedFee; // 900e18
        
        vm.prank(alice);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, fundAmount, "");
        
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), expectedNet);
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), alice), expectedNet);
    }

    function test_fundRepo_withFee_multipleFundings() public {
        // Set 2.5% fee
        vm.prank(owner);
        escrow.setFeeOnFund(250); // 2.5%
        
        uint256 firstAmount = 1000e18;
        uint256 secondAmount = 500e18;
        
        uint256 firstFee = (firstAmount * 250) / 10_000; // 25e18
        uint256 secondFee = (secondAmount * 250) / 10_000; // 12.5e18
        
        uint256 firstNet = firstAmount - firstFee; // 975e18
        uint256 secondNet = secondAmount - secondFee; // 487.5e18
        
        uint256 initialFeeBalance = wETH.balanceOf(owner);
        
        // First funding
        vm.prank(alice);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, firstAmount, "");
        
        // Second funding
        vm.prank(alice);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, secondAmount, "");
        
        // Verify cumulative amounts
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), firstNet + secondNet);
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), alice), firstNet + secondNet);
        assertEq(wETH.balanceOf(owner), initialFeeBalance + firstFee + secondFee);
    }

    function test_fundRepo_withFee_differentUsers() public {
        // Set 3% fee
        vm.prank(owner);
        escrow.setFeeOnFund(300); // 3%
        
        uint256 aliceAmount = 1000e18;
        uint256 bobAmount = 2000e18;
        
        uint256 aliceFee = (aliceAmount * 300) / 10_000; // 30e18
        uint256 bobFee = (bobAmount * 300) / 10_000; // 60e18
        
        uint256 aliceNet = aliceAmount - aliceFee; // 970e18
        uint256 bobNet = bobAmount - bobFee; // 1940e18
        
        // Setup bob
        wETH.mint(bob, bobAmount);
        vm.prank(bob);
        wETH.approve(address(escrow), bobAmount);
        
        uint256 initialFeeBalance = wETH.balanceOf(owner);
        
        // Alice funds
        vm.prank(alice);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, aliceAmount, "");
        
        // Bob funds
        vm.prank(bob);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, bobAmount, "");
        
        // Verify individual tracking
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), alice), aliceNet);
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), bob), bobNet);
        
        // Verify total account balance
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), aliceNet + bobNet);
        
        // Verify total fees collected
        assertEq(wETH.balanceOf(owner), initialFeeBalance + aliceFee + bobFee);
    }

    function test_fundRepo_withFee_reclaimNetAmount() public {
        // Set 4% fee
        vm.prank(owner);
        escrow.setFeeOnFund(400); // 4%
        
        uint256 fundAmount = 1000e18;
        uint256 expectedFee = (fundAmount * 400) / 10_000; // 40e18
        uint256 expectedNet = fundAmount - expectedFee; // 960e18
        
        // Fund the repo
        vm.prank(alice);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, fundAmount, "");
        
        // Verify alice can only reclaim the net amount
        uint256 initialAliceBalance = wETH.balanceOf(alice);
        
        vm.prank(alice);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), expectedNet);
        
        // Alice should receive back the net amount (what she effectively contributed)
        assertEq(wETH.balanceOf(alice), initialAliceBalance + expectedNet);
        
        // Account balance should be zero
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), 0);
        
        // Alice's funding tracking should be zero
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), alice), 0);
    }

    function test_fundRepo_withFee_cannotReclaimMoreThanNet() public {
        // Set 5% fee
        vm.prank(owner);
        escrow.setFeeOnFund(500); // 5%
        
        uint256 fundAmount = 1000e18;
        uint256 expectedNet = fundAmount - (fundAmount * 500) / 10_000; // 950e18
        
        vm.prank(alice);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, fundAmount, "");
        
        // Try to reclaim original amount (should fail)
        expectRevert(Errors.INSUFFICIENT_FUNDS);
        vm.prank(alice);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), fundAmount);
        
        // Try to reclaim more than net (should fail)
        expectRevert(Errors.INSUFFICIENT_FUNDS);
        vm.prank(alice);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), expectedNet + 1);
    }

    function test_fundRepo_withFee_dynamicFeeChanges() public {
        uint256 fundAmount = 1000e18;
        
        // First funding with 2% fee
        vm.prank(owner);
        escrow.setFeeOnFund(200); // 2%
        
        vm.prank(alice);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, fundAmount, "");
        
        uint256 firstNet = fundAmount - (fundAmount * 200) / 10_000; // 980e18
        
        // Change fee to 6%
        vm.prank(owner);
        escrow.setFeeOnFund(600); // 6%
        
        // Second funding with new fee
        vm.prank(alice);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, fundAmount, "");
        
        uint256 secondNet = fundAmount - (fundAmount * 600) / 10_000; // 940e18
        
        // Verify cumulative tracking
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), firstNet + secondNet);
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), alice), firstNet + secondNet);
    }

    function test_fundRepo_fuzz_withFees(uint16 feeRate, uint256 amount) public {
        vm.assume(feeRate <= 1000); // Max 10% fee
        vm.assume(amount > 0 && amount <= FUND_AMOUNT * 10);
        
        // Set the fee rate
        vm.prank(owner);
        escrow.setFeeOnFund(feeRate);
        
        // Use the same calculation as the contract (mulDivUp)
        uint256 expectedFee = (amount * feeRate + 9999) / 10_000; // This simulates mulDivUp
        vm.assume(amount > expectedFee); // Ensure net amount > 0
        uint256 expectedNet = amount - expectedFee;
        
        uint256 initialFeeBalance = wETH.balanceOf(owner);
        
        vm.prank(alice);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, amount, "");
        
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), expectedNet);
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), alice), expectedNet);
        assertEq(wETH.balanceOf(owner), initialFeeBalance + expectedFee);
    }

    function test_fundRepo_withFee_revert_amountTooSmall() public {
        // Set 10% fee (maximum)
        vm.prank(owner);
        escrow.setFeeOnFund(1000);
        
        // With 10% fee, we need amount where amount <= fee
        // Since we use mulDivUp, let's use amount = 1
        // fee = (1 * 1000) / 10_000 = 0.1, but mulDivUp rounds up, so fee = 1
        // amount (1) == fee (1), so net would be 0, should revert
        uint256 amount = 1;
        
        expectRevert(Errors.INVALID_AMOUNT);
        vm.prank(alice);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, amount, "");
    }

    function test_fundRepo_withFee_interactionWithDistributions() public {
        // Set 3% fee on fund
        vm.prank(owner);
        escrow.setFeeOnFund(300); // 3%
        
        uint256 fundAmount = 1000e18;
        uint256 expectedNet = fundAmount - (fundAmount * 300) / 10_000; // 970e18
        
        // Fund the repo
        vm.prank(alice);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, fundAmount, "");
        
        // Initialize repo to enable distributions
        address[] memory admins = new address[](1);
        admins[0] = alice;
        uint256 deadline = block.timestamp + 1 hours;
        
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    REPO_ID,
                    ACCOUNT_ID,
                    keccak256(abi.encode(admins)),
                    escrow.repoSetAdminNonce(REPO_ID, ACCOUNT_ID),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, deadline, v, r, s);
        
        // Try to distribute more than net amount (should fail)
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: expectedNet + 1,
            recipient: bob,
            claimPeriod: 3600,
            token: wETH
        });
        
        expectRevert(Errors.INSUFFICIENT_BALANCE);
        vm.prank(alice);
        escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");
        
        // Distribute valid amount (should succeed)
        distributions[0].amount = expectedNet / 2; // Half of net amount
        
        vm.prank(alice);
        escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");
        
        // Verify remaining balance
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), expectedNet - (expectedNet / 2));
    }

    // Event for testing
    event FundedRepo(uint256 indexed repoId, uint256 indexed instanceId, address indexed token, address sender, uint256 amount, uint256 feeAmount, bytes data);
} 