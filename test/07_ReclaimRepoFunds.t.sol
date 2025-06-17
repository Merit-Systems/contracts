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
                    escrow.signerNonce(),
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
        _fundRepo(FUND_AMOUNT);
        
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
        _fundRepo(FUND_AMOUNT);

        vm.prank(repoAdmin);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), FUND_AMOUNT);

        // Should be able to reclaim all funds
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), 0);
        assertEq(wETH.balanceOf(repoAdmin), FUND_AMOUNT);
    }

    function test_reclaimFund_partialAmount() public {
        _fundRepo(FUND_AMOUNT);
        
        uint256 reclaimAmount = FUND_AMOUNT / 2;
        uint256 expectedRemainingBalance = FUND_AMOUNT - reclaimAmount;

        vm.prank(repoAdmin);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), reclaimAmount);

        // Should have partial amount remaining
        assertEq(escrow.getAccountBalance(REPO_ID, ACCOUNT_ID, address(wETH)), expectedRemainingBalance);
        assertEq(wETH.balanceOf(repoAdmin), reclaimAmount);
    }

    function test_reclaimFund_multipleReclaimsBeforeDistributions() public {
        _fundRepo(FUND_AMOUNT);
        
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
                    escrow.signerNonce(),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        escrow.initRepo(repoId2, instanceId2, _toArray(admin2), deadline, v, r, s);
        
        // Fund both repos
        _fundRepo(FUND_AMOUNT);
        wETH.mint(address(this), FUND_AMOUNT);
        wETH.approve(address(escrow), FUND_AMOUNT);
        escrow.fundRepo(repoId2, instanceId2, wETH, FUND_AMOUNT, "");
        
        // Reclaim from both repos
        vm.prank(repoAdmin);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), FUND_AMOUNT);
        
        vm.prank(admin2);
        escrow.reclaimRepoFunds(repoId2, instanceId2, address(wETH), FUND_AMOUNT);
        
        // Check balances
        assertEq(wETH.balanceOf(repoAdmin), FUND_AMOUNT);
        assertEq(wETH.balanceOf(admin2), FUND_AMOUNT);
    }

    function test_reclaimFund_revert_notRepoAdmin() public {
        _fundRepo(FUND_AMOUNT);

        address unauthorized = makeAddr("unauthorized");
        expectRevert(Errors.NOT_REPO_ADMIN);
        vm.prank(unauthorized);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), FUND_AMOUNT);
    }

    function test_reclaimFund_revert_invalidToken() public {
        _fundRepo(FUND_AMOUNT);
        
        MockERC20 nonWhitelistedToken = new MockERC20("Non-Whitelisted", "NWT", 18);

        expectRevert(Errors.INVALID_TOKEN);
        vm.prank(repoAdmin);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(nonWhitelistedToken), FUND_AMOUNT);
    }

    function test_reclaimFund_revert_zeroAmount() public {
        _fundRepo(FUND_AMOUNT);

        expectRevert(Errors.INVALID_AMOUNT);
        vm.prank(repoAdmin);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), 0);
    }

    function test_reclaimFund_revert_repoHasDistributions() public {
        _fundRepo(FUND_AMOUNT);
        
        // Create a distribution (this sets hasDistributions flag)
        _createRepoDistribution(recipient, DISTRIBUTION_AMOUNT, 7 days);

        expectRevert(Errors.REPO_HAS_DISTRIBUTIONS);
        vm.prank(repoAdmin);
        escrow.reclaimRepoFunds(REPO_ID, ACCOUNT_ID, address(wETH), FUND_AMOUNT);
    }

    function test_reclaimFund_revert_insufficientBalance() public {
        _fundRepo(FUND_AMOUNT);

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
        _fundRepo(FUND_AMOUNT);
        
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
        
        _fundRepo(fundAmount);
        
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
        
        _fundRepo(fundAmount);
        
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
                    escrow.signerNonce(),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        escrow.initRepo(repoId, instanceId, _toArray(admin), deadline, v, r, s);
        
        // Fund the repo
        wETH.mint(address(this), amount);
        wETH.approve(address(escrow), amount);
        escrow.fundRepo(repoId, instanceId, wETH, amount, "");
        
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
        _fundRepo(totalFundAmount);
        
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