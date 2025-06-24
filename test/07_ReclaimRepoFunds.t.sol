// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "./00_Escrow.t.sol";

contract ReclaimFund_Test is Base_Test {
    
    uint256 constant REPO_ID = 1;
    uint256 constant ACCOUNT_ID = 100;
    uint256 constant FUND_AMOUNT = 5000e18;
    uint256 constant DISTRIBUTION_AMOUNT = 1000e18;

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
                    keccak256(abi.encode(_toArray(repoAdmin))),
                    escrow.repoSetAdminNonce(REPO_ID, ACCOUNT_ID),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        escrow.initRepo(REPO_ID, ACCOUNT_ID, _toArray(repoAdmin), deadline, v, r, s);
    }

    function _fundRepo(uint256 amount) internal {
        wETH.mint(address(this), amount);
        wETH.approve(address(escrow), amount);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wETH, amount, "");
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

    function _createRepoDistribution(address _recipient, uint256 amount, uint32 claimPeriod) internal returns (uint256 distributionId) {
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: amount,
            recipient: _recipient,
            claimPeriod: claimPeriod,
            token: wETH
        });

        vm.prank(repoAdmin);
        uint[] memory distributionIds = escrow.distributeFromRepo(REPO_ID, ACCOUNT_ID, distributions, "");
        return distributionIds[0];
    }

    /* -------------------------------------------------------------------------- */
    /*                              RECLAIM FUND TESTS                            */
    /* -------------------------------------------------------------------------- */

    function test_reclaimFund_success() public {
        _fundRepoAs(repoAdmin, FUND_AMOUNT);
        
        uint256 reclaimAmount = 2000e18;
        uint256 initialAdminBalance = wETH.balanceOf(repoAdmin);
        uint256 initialRepoBalance = escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH));

        vm.expectEmit(true, true, true, true);
        emit ReclaimedRepoFunds(REPO_ID, ACCOUNT_ID, repoAdmin, reclaimAmount);

        vm.prank(repoAdmin);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), reclaimAmount);

        // Check balances
        assertEq(wETH.balanceOf(repoAdmin), initialAdminBalance + reclaimAmount);
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), initialRepoBalance - reclaimAmount);
    }

    function test_reclaimFund_fullAmount() public {
        _fundRepoAs(repoAdmin, FUND_AMOUNT);

        vm.prank(repoAdmin);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), FUND_AMOUNT);

        // Should be able to reclaim all funds
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), 0);
        assertEq(wETH.balanceOf(repoAdmin), FUND_AMOUNT);
    }

    function test_reclaimFund_partialAmount() public {
        _fundRepoAs(repoAdmin, FUND_AMOUNT);
        
        uint256 reclaimAmount = FUND_AMOUNT / 2;
        uint256 expectedRemainingBalance = FUND_AMOUNT - reclaimAmount;

        vm.prank(repoAdmin);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), reclaimAmount);

        // Should have partial amount remaining
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), expectedRemainingBalance);
        assertEq(wETH.balanceOf(repoAdmin), reclaimAmount);
    }

    function test_reclaimFund_multipleReclaimsBeforeDistributions() public {
        _fundRepoAs(repoAdmin, FUND_AMOUNT);
        
        uint256 firstReclaim = 1000e18;
        uint256 secondReclaim = 500e18;
        
        // First reclaim
        vm.prank(repoAdmin);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), firstReclaim);
        
        // Second reclaim
        vm.prank(repoAdmin);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), secondReclaim);
        
        uint256 expectedBalance = FUND_AMOUNT - firstReclaim - secondReclaim;
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), expectedBalance);
        assertEq(wETH.balanceOf(repoAdmin), firstReclaim + secondReclaim);
    }

    function test_reclaimFund_differentRepos() public {
        uint256 repoId2 = 2;
        uint256 instanceId2 = 200;
        address admin2 = makeAddr("admin2");
        
        // Initialize second repo
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    repoId2,
                    instanceId2,
                    keccak256(abi.encode(_toArray(admin2))),
                    escrow.repoSetAdminNonce(repoId2, instanceId2),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        escrow.initRepo(repoId2, instanceId2, _toArray(admin2), deadline, v, r, s);
        
        // Fund both repos with respective funders
        _fundRepoAs(repoAdmin, REPO_ID, ACCOUNT_ID, FUND_AMOUNT);
        _fundRepoAs(admin2, repoId2, instanceId2, FUND_AMOUNT);
        
        // Reclaim from both repos
        vm.prank(repoAdmin);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), FUND_AMOUNT);
        
        vm.prank(admin2);
        escrow.reclaimRepoFunds(repoId2, instanceId2, address(wETH), FUND_AMOUNT);
        
        // Check balances
        assertEq(wETH.balanceOf(repoAdmin), FUND_AMOUNT);
        assertEq(wETH.balanceOf(admin2), FUND_AMOUNT);
    }

    function test_reclaimFund_revert_notFunder() public {
        _fundRepoAs(repoAdmin, FUND_AMOUNT);

        address nonFunder = makeAddr("nonFunder");
        expectRevert(Errors.INSUFFICIENT_BALANCE); // Non-funder has no contribution to reclaim
        vm.prank(nonFunder);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), FUND_AMOUNT);
    }

    function test_reclaimFund_revert_invalidToken() public {
        _fundRepoAs(repoAdmin, FUND_AMOUNT);
        
        MockERC20 nonWhitelistedToken = new MockERC20("Non-Whitelisted", "NWT", 18);

        expectRevert(Errors.INVALID_TOKEN);
        vm.prank(repoAdmin);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(nonWhitelistedToken), FUND_AMOUNT);
    }

    function test_reclaimFund_revert_zeroAmount() public {
        _fundRepoAs(repoAdmin, FUND_AMOUNT);

        expectRevert(Errors.INVALID_AMOUNT);
        vm.prank(repoAdmin);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), 0);
    }

    function test_reclaimFund_revert_repoHasDistributions() public {
        _fundRepoAs(repoAdmin, FUND_AMOUNT);
        
        // Create a distribution (this sets hasDistributions flag)
        _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT, 7 days);

        expectRevert(Errors.REPO_HAS_DISTRIBUTIONS);
        vm.prank(repoAdmin);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), FUND_AMOUNT);
    }

    function test_reclaimFund_revert_insufficientBalance() public {
        _fundRepoAs(repoAdmin, FUND_AMOUNT);

        expectRevert(Errors.INSUFFICIENT_BALANCE);
        vm.prank(repoAdmin);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), FUND_AMOUNT + 1);
    }

    function test_reclaimFund_revert_noFundsToReclaim() public {
        // Don't fund the repo
        
        expectRevert(Errors.INSUFFICIENT_BALANCE);
        vm.prank(repoAdmin);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), 1);
    }

    function test_reclaimFund_revert_afterFullReclaim() public {
        _fundRepoAs(repoAdmin, FUND_AMOUNT);
        
        // Reclaim all funds first
        vm.prank(repoAdmin);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), FUND_AMOUNT);
        
        // Try to reclaim again
        expectRevert(Errors.INSUFFICIENT_BALANCE);
        vm.prank(repoAdmin);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), 1);
    }

    function test_reclaimFund_fuzz_amounts(uint256 fundAmount, uint256 reclaimAmount) public {
        vm.assume(fundAmount > 0 && fundAmount <= 1000000e18);
        vm.assume(reclaimAmount > 0 && reclaimAmount <= fundAmount);
        
        _fundRepoAs(repoAdmin, fundAmount);
        
        uint256 initialAdminBalance = wETH.balanceOf(repoAdmin);
        uint256 initialRepoBalance = escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH));
        
        vm.prank(repoAdmin);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), reclaimAmount);
        
        assertEq(wETH.balanceOf(repoAdmin), initialAdminBalance + reclaimAmount);
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), initialRepoBalance - reclaimAmount);
    }

    function test_reclaimFund_fuzz_invalidAmounts(uint256 fundAmount, uint256 reclaimAmount) public {
        vm.assume(fundAmount > 0 && fundAmount <= 1000000e18);
        vm.assume(reclaimAmount > fundAmount && reclaimAmount <= type(uint128).max);
        
        _fundRepoAs(repoAdmin, fundAmount);
        
        expectRevert(Errors.INSUFFICIENT_BALANCE);
        vm.prank(repoAdmin);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), reclaimAmount);
    }

    function test_reclaimFund_fuzz_repoAndAccountIds(uint256 repoId, uint256 instanceId, uint256 amount) public {
        vm.assume(amount > 0 && amount <= 1000e18);
        vm.assume(repoId != REPO_ID || instanceId != ACCOUNT_ID); // Avoid conflict with existing repo
        vm.assume(repoId <= type(uint128).max && instanceId <= type(uint128).max);
        
        address admin = makeAddr("fuzzAdmin");
        
        // Initialize new repo
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
        
        // Fund the repo with the admin as the funder
        _fundRepoAs(admin, repoId, instanceId, amount);
        
        uint256 initialAdminBalance = wETH.balanceOf(admin);
        
        // Reclaim funds
        vm.prank(admin);
        escrow.reclaimRepoFunds(repoId, instanceId, address(wETH), amount);
        
        assertEq(wETH.balanceOf(admin), initialAdminBalance + amount);
        assertEq(escrow.getAccountBalance(repoId, instanceId, address(wETH)), 0);
    }

    function test_reclaimFund_fuzz_multipleReclaims(uint8 numReclaims, uint256 baseAmount) public {
        vm.assume(numReclaims > 0 && numReclaims <= 10);
        vm.assume(baseAmount > 0 && baseAmount <= 100e18);
        
        uint256 totalFundAmount = baseAmount * numReclaims;
        _fundRepoAs(repoAdmin, totalFundAmount);
        
        uint256 totalReclaimed = 0;
        uint256 initialAdminBalance = wETH.balanceOf(repoAdmin);
        
        for (uint i = 0; i < numReclaims; i++) {
            vm.prank(repoAdmin);
            escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), baseAmount);
            totalReclaimed += baseAmount;
        }
        
        assertEq(wETH.balanceOf(repoAdmin), initialAdminBalance + totalReclaimed);
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), totalFundAmount - totalReclaimed);
    }

    function test_reclaimFund_multipleFunders() public {
        address funder1 = makeAddr("funder1");
        address funder2 = makeAddr("funder2");
        uint256 amount1 = 2000e18;
        uint256 amount2 = 3000e18;
        
        // Fund with multiple addresses
        _fundRepoAs(funder1, amount1);
        _fundRepoAs(funder2, amount2);
        
        // Check contributions
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), funder1), amount1);
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), funder2), amount2);
        
        // Each funder can only reclaim their own contribution
        vm.prank(funder1);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), amount1);
        
        vm.prank(funder2);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), amount2);
        
        // Check balances
        assertEq(wETH.balanceOf(funder1), amount1);
        assertEq(wETH.balanceOf(funder2), amount2);
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), 0);
    }

    function test_reclaimFund_revert_exceedOwnContribution() public {
        address funder1 = makeAddr("funder1");
        address funder2 = makeAddr("funder2");
        uint256 amount1 = 2000e18;
        uint256 amount2 = 3000e18;
        
        // Fund with multiple addresses
        _fundRepoAs(funder1, amount1);
        _fundRepoAs(funder2, amount2);
        
        // Funder1 tries to reclaim more than their contribution
        expectRevert(Errors.INSUFFICIENT_BALANCE);
        vm.prank(funder1);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), amount1 + 1);
        
        // Funder2 tries to reclaim amount2 + amount1 (more than their contribution)
        expectRevert(Errors.INSUFFICIENT_BALANCE);
        vm.prank(funder2);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), amount1 + amount2);
    }

    function test_reclaimFund_sameFunderMultipleFundings() public {
        address funder = makeAddr("funder");
        uint256 amount1 = 1000e18;
        uint256 amount2 = 1500e18;
        uint256 amount3 = 500e18;
        uint256 totalAmount = amount1 + amount2 + amount3;
        
        // Same funder contributes multiple times
        _fundRepoAs(funder, amount1);
        _fundRepoAs(funder, amount2);
        _fundRepoAs(funder, amount3);
        
        // Verify total contribution is tracked correctly
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), funder), totalAmount);
        
        // Reclaim partially multiple times
        uint256 firstReclaim = 800e18;
        uint256 secondReclaim = 1200e18;
        
        vm.prank(funder);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), firstReclaim);
        
        // Check remaining contribution
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), funder), totalAmount - firstReclaim);
        
        vm.prank(funder);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), secondReclaim);
        
        // Check final contribution
        uint256 expectedRemaining = totalAmount - firstReclaim - secondReclaim;
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), funder), expectedRemaining);
        assertEq(wETH.balanceOf(funder), firstReclaim + secondReclaim);
    }

    function test_reclaimFund_crossRepoIsolation() public {
        address funder = makeAddr("crossRepoFunder");
        uint256 amount = 2000e18;
        uint256 repoId2 = 999;
        uint256 instanceId2 = 888;
        address admin2 = makeAddr("admin2");
        
        // Initialize second repo
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    repoId2,
                    instanceId2,
                    keccak256(abi.encode(_toArray(admin2))),
                    escrow.repoSetAdminNonce(repoId2, instanceId2),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        escrow.initRepo(repoId2, instanceId2, _toArray(admin2), deadline, v, r, s);
        
        // Fund only repo1
        _fundRepoAs(funder, REPO_ID, ACCOUNT_ID, amount);
        
        // Verify funder has contribution in repo1 but not repo2
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), funder), amount);
        assertEq(escrow.getFunding(repoId2, instanceId2, address(wETH), funder), 0);
        
        // Funder tries to reclaim from repo2 (which they never funded)
        expectRevert(Errors.INSUFFICIENT_BALANCE);
        vm.prank(funder);
        escrow.reclaimRepoFunds(repoId2, instanceId2, address(wETH), amount);
        
        // Funder can successfully reclaim from repo1
        vm.prank(funder);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), amount);
        assertEq(wETH.balanceOf(funder), amount);
    }

    function test_reclaimFund_mixedTokensMultipleFunders() public {
        address funder1 = makeAddr("funder1");
        address funder2 = makeAddr("funder2");
        address funder3 = makeAddr("funder3");
        
        // Create second token and whitelist it
        MockERC20 wBTC = new MockERC20("Wrapped Bitcoin", "wBTC", 8);
        vm.prank(owner);
        escrow.whitelistToken(address(wBTC));
        
        uint256 ethAmount1 = 1000e18;
        uint256 ethAmount2 = 2000e18;
        uint256 btcAmount1 = 5e8; // 5 BTC (8 decimals)
        uint256 btcAmount2 = 3e8; // 3 BTC
        
        // Complex funding scenario with multiple tokens and funders
        _fundRepoAs(funder1, REPO_ID, ACCOUNT_ID, ethAmount1); // funder1: 1000 ETH
        
        // funder2: 2000 ETH + 5 BTC
        _fundRepoAs(funder2, REPO_ID, ACCOUNT_ID, ethAmount2);
        wBTC.mint(funder2, btcAmount1);
        vm.prank(funder2);
        wBTC.approve(address(escrow), btcAmount1);
        vm.prank(funder2);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wBTC, btcAmount1, "");
        
        // funder3: 3 BTC only
        wBTC.mint(funder3, btcAmount2);
        vm.prank(funder3);
        wBTC.approve(address(escrow), btcAmount2);
        vm.prank(funder3);
        escrow.fundRepo(REPO_ID, ACCOUNT_ID, wBTC, btcAmount2, "");
        
        // Verify contributions are tracked correctly
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), funder1), ethAmount1);
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), funder2), ethAmount2);
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), funder3), 0);
        
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wBTC), funder1), 0);
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wBTC), funder2), btcAmount1);
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wBTC), funder3), btcAmount2);
        
        // Each funder can only reclaim their own contributions
        vm.prank(funder1);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), ethAmount1);
        
        vm.prank(funder2);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), ethAmount2);
        vm.prank(funder2);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wBTC), btcAmount1);
        
        vm.prank(funder3);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wBTC), btcAmount2);
        
        // Verify balances
        assertEq(wETH.balanceOf(funder1), ethAmount1);
        assertEq(wETH.balanceOf(funder2), ethAmount2);
        assertEq(wBTC.balanceOf(funder2), btcAmount1);
        assertEq(wBTC.balanceOf(funder3), btcAmount2);
        
        // Repo should have zero balance
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), 0);
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wBTC)), 0);
    }

    function test_reclaimFund_sequentialFundersWithPartialReclaims() public {
        address[] memory funders = new address[](5);
        uint256[] memory amounts = new uint256[](5);
        
        for (uint i = 0; i < 5; i++) {
            funders[i] = makeAddr(string(abi.encodePacked("funder", i)));
            amounts[i] = (i + 1) * 1000e18; // 1000, 2000, 3000, 4000, 5000 ETH
            _fundRepoAs(funders[i], amounts[i]);
        }
        
        // Partial reclaims in reverse order
        for (uint i = 5; i > 0; i--) {
            uint idx = i - 1;
            uint256 reclaimAmount = amounts[idx] / 2; // Reclaim half
            
            vm.prank(funders[idx]);
            escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), reclaimAmount);
            
            // Verify remaining contribution
            assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), funders[idx]), amounts[idx] - reclaimAmount);
            assertEq(wETH.balanceOf(funders[idx]), reclaimAmount);
        }
        
        // Now reclaim remaining amounts in forward order
        for (uint i = 0; i < 5; i++) {
            uint256 remainingAmount = amounts[i] / 2;
            
            vm.prank(funders[i]);
            escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), remainingAmount);
            
            // Verify full reclaim
            assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), funders[i]), 0);
            assertEq(wETH.balanceOf(funders[i]), amounts[i]);
        }
    }

    function test_reclaimFund_fundingTrackingAccuracy() public {
        address funder = makeAddr("accuracyTester");
        uint256[] memory fundingAmounts = new uint256[](10);
        uint256 totalFunded = 0;
        
        // Multiple funding rounds
        for (uint i = 0; i < 10; i++) {
            fundingAmounts[i] = (i + 1) * 100e18;
            totalFunded += fundingAmounts[i];
            _fundRepoAs(funder, fundingAmounts[i]);
            
            // Verify cumulative tracking
            assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), funder), totalFunded);
        }
        
        uint256 totalReclaimed = 0;
        // Partial reclaims
        for (uint i = 0; i < 5; i++) {
            uint256 reclaimAmount = fundingAmounts[i];
            totalReclaimed += reclaimAmount;
            
            vm.prank(funder);
            escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), reclaimAmount);
            
            // Verify tracking decreases correctly
            assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), funder), totalFunded - totalReclaimed);
        }
        
        // Final full reclaim
        uint256 remainingAmount = totalFunded - totalReclaimed;
        vm.prank(funder);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), remainingAmount);
        
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), funder), 0);
        assertEq(wETH.balanceOf(funder), totalFunded);
    }

    function test_reclaimFund_integrationWithDistributionsStrict() public {
        address funder1 = makeAddr("funder1");
        address funder2 = makeAddr("funder2");
        uint256 amount1 = 3000e18;
        uint256 amount2 = 2000e18;
        
        // Both funders contribute
        _fundRepoAs(funder1, amount1);
        _fundRepoAs(funder2, amount2);
        
        // Both can reclaim before any distributions
        vm.prank(funder1);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), 1000e18);
        
        vm.prank(funder2);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), 500e18);
        
        // Create a distribution to set hasDistributions flag
        _createRepoDistribution(recipient, 1000e18, 7 days);
        
        // Now neither funder can reclaim anything
        expectRevert(Errors.REPO_HAS_DISTRIBUTIONS);
        vm.prank(funder1);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), 1);
        
        expectRevert(Errors.REPO_HAS_DISTRIBUTIONS);
        vm.prank(funder2);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), 1);
        
        // Verify their contributions are still tracked (but not reclaimable due to distributions)
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), funder1), amount1 - 1000e18);
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), funder2), amount2 - 500e18);
    }

    function test_reclaimFund_edgeCaseZeroAfterReclaim() public {
        address funder = makeAddr("zeroTester");
        uint256 amount = 1000e18;
        
        _fundRepoAs(funder, amount);
        
        // Reclaim exact amount
        vm.prank(funder);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), amount);
        
        // Verify contribution is zero
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), funder), 0);
        
        // Cannot reclaim anything more
        expectRevert(Errors.INSUFFICIENT_BALANCE);
        vm.prank(funder);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), 1);
        
        // Can fund again and it works normally
        _fundRepoAs(funder, 500e18);
        assertEq(escrow.getFunding(REPO_ID, ACCOUNT_ID, address(wETH), funder), 500e18);
        
        vm.prank(funder);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), 500e18);
        assertEq(wETH.balanceOf(funder), amount + 500e18);
    }

    /* -------------------------------------------------------------------------- */
    /*                                    EVENTS                                  */
    /* -------------------------------------------------------------------------- */

    event ReclaimedRepoFunds(uint256 indexed repoId, uint256 indexed instanceId, address indexed admin, uint256 amount);

    function _toArray(address addr) internal pure returns (address[] memory) {
        address[] memory arr = new address[](1);
        arr[0] = addr;
        return arr;
    }
} 