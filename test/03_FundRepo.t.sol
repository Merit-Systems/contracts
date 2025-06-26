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

    // Event for testing
    event FundedRepo(uint256 indexed repoId, uint256 indexed instanceId, address indexed token, address sender, uint256 amount, uint256 feeAmount, bytes data);
} 