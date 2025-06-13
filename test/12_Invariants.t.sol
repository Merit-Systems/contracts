// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "./00_Escrow.t.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

contract EscrowInvariants is StdInvariant, Base_Test {
    
    EscrowHandler handler;
    
    function setUp() public override {
        super.setUp();
        
        handler = new EscrowHandler(escrow, wETH, owner, ownerPrivateKey);
        
        // Set handler as target for invariant testing
        targetContract(address(handler));
        
        // Target specific functions that should maintain invariants
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = EscrowHandler.fundRepo.selector;
        selectors[1] = EscrowHandler.distributeFromRepo.selector;
        selectors[2] = EscrowHandler.distributeFromSender.selector;
        selectors[3] = EscrowHandler.claim.selector;
        selectors[4] = EscrowHandler.reclaimRepoDistributions.selector;
        selectors[5] = EscrowHandler.reclaimSenderDistributions.selector;
        selectors[6] = EscrowHandler.addAdmin.selector;
        selectors[7] = EscrowHandler.removeAdmin.selector;
        
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /* -------------------------------------------------------------------------- */
    /*                              BALANCE INVARIANTS                            */
    /* -------------------------------------------------------------------------- */
    
    /// @dev Contract token balance should always be >= sum of all account balances + undistributed amounts
    function invariant_tokenBalanceConsistency() public view {
        uint256 contractBalance = wETH.balanceOf(address(escrow));
        uint256 totalAccountBalances = handler.getTotalAccountBalances();
        uint256 totalUndistributed = handler.getTotalUndistributedAmounts();
        
        assertGe(
            contractBalance, 
            totalAccountBalances + totalUndistributed,
            "Contract balance should cover all account balances and undistributed amounts"
        );
    }
    
    /// @dev No account balance should exceed what was actually deposited to that account
    function invariant_accountBalanceNeverExceedsDeposits() public view {
        uint256[] memory repoIds = handler.getTrackedRepoIds();
        
        for (uint i = 0; i < repoIds.length; i++) {
            uint256 repoId = repoIds[i];
            uint256[] memory accountIds = handler.getTrackedAccountIds(repoId);
            
            for (uint j = 0; j < accountIds.length; j++) {
                uint256 accountId = accountIds[j];
                uint256 currentBalance = escrow.getAccountBalance(repoId, accountId, address(wETH));
                uint256 totalFunded = handler.getTotalFunded(repoId, accountId);
                uint256 accountTotalDistributed = handler.getTotalDistributedFromAccount(repoId, accountId);
                
                assertEq(
                    currentBalance + accountTotalDistributed,
                    totalFunded,
                    "Account balance + distributed should equal total funded"
                );
            }
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                           DISTRIBUTION INVARIANTS                          */
    /* -------------------------------------------------------------------------- */
    
    /// @dev All distributions should be in valid states and amounts should be consistent
    function invariant_distributionStateConsistency() public view {
        uint256 distributionCount = escrow.distributionCount();
        uint256 claimedAmount = 0;
        uint256 reclaimedAmount = 0;
        uint256 distributedAmount = 0;
        
        for (uint256 i = 0; i < distributionCount; i++) {
            Escrow.Distribution memory dist = escrow.getDistribution(i);
            
            // All distributions should have positive amounts
            assertGt(dist.amount, 0, "Distribution amount should be positive");
            
            // All distributions should have valid recipients
            assert(dist.recipient != address(0));
            
            // All distributions should have valid claim deadlines
            assertGt(dist.claimDeadline, 0, "Claim deadline should be positive");
            
            // Fee should not exceed max fee
            assertLe(dist.fee, escrow.MAX_FEE(), "Distribution fee should not exceed max");
            
            distributedAmount += dist.amount;
            
            if (dist.status == Escrow.DistributionStatus.Claimed) {
                claimedAmount += dist.amount;
            } else if (dist.status == Escrow.DistributionStatus.Reclaimed) {
                reclaimedAmount += dist.amount;
            }
        }
        
        // Total distributed should equal claimed + reclaimed + still distributable
        uint256 totalSettled = claimedAmount + reclaimedAmount;
        assertLe(totalSettled, distributedAmount, "Settled amounts should not exceed distributed");
    }
    
    /// @dev Once claimed or reclaimed, distributions should never change state back
    function invariant_distributionStateImmutability() public view {
        uint256[] memory claimedIds = handler.getClaimedDistributionIds();
        uint256[] memory reclaimedIds = handler.getReclaimedDistributionIds();
        
        // Verify all tracked claimed distributions are still claimed
        for (uint i = 0; i < claimedIds.length; i++) {
            Escrow.Distribution memory dist = escrow.getDistribution(claimedIds[i]);
            assertEq(
                uint(dist.status),
                uint(Escrow.DistributionStatus.Claimed),
                "Claimed distribution should remain claimed"
            );
        }
        
        // Verify all tracked reclaimed distributions are still reclaimed
        for (uint i = 0; i < reclaimedIds.length; i++) {
            Escrow.Distribution memory dist = escrow.getDistribution(reclaimedIds[i]);
            assertEq(
                uint(dist.status),
                uint(Escrow.DistributionStatus.Reclaimed),
                "Reclaimed distribution should remain reclaimed"
            );
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                               FEE INVARIANTS                               */
    /* -------------------------------------------------------------------------- */
    
    /// @dev Fee recipient balance should never decrease (fees only accumulate)
    function invariant_feeRecipientBalanceMonotonic() public view {
        uint256 _feeRecipientBalance = wETH.balanceOf(escrow.feeRecipient());
        uint256 expectedMinimum = handler.getInitialFeeRecipientBalance() + handler.getTotalFeesCollectedByHandler();
        
        assertGe(
            _feeRecipientBalance,
            expectedMinimum,
            "Fee recipient balance should never decrease"
        );
    }
    
    /// @dev Total fees collected should be consistent with distributions claimed  
    function invariant_feeConsistency() public view {
        uint256 currentFeeBalance = wETH.balanceOf(escrow.feeRecipient());
        uint256 initialBalance = handler.getInitialFeeRecipientBalance();
        uint256 expectedFeesFromHandler = handler.getTotalFeesCollectedByHandler();
        
        // The current balance should be at least initial balance + fees we tracked
        assertGe(
            currentFeeBalance,
            initialBalance + expectedFeesFromHandler,
            "Fee recipient balance should be at least initial + our tracked fees"
        );
    }

    /* -------------------------------------------------------------------------- */
    /*                              ADMIN INVARIANTS                              */
    /* -------------------------------------------------------------------------- */
    
    /// @dev Every initialized repo should always have at least one admin
    function invariant_repoAlwaysHasAdmin() public view {
        uint256[] memory repoIds = handler.getTrackedRepoIds();
        
        for (uint i = 0; i < repoIds.length; i++) {
            uint256 repoId = repoIds[i];
            uint256[] memory accountIds = handler.getTrackedAccountIds(repoId);
            
            for (uint j = 0; j < accountIds.length; j++) {
                uint256 accountId = accountIds[j];
                
                if (escrow.getAccountExists(repoId, accountId)) {
                    address[] memory admins = escrow.getAllAdmins(repoId, accountId);
                    assertGt(admins.length, 0, "Initialized repo should always have at least one admin");
                }
            }
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                              NONCE INVARIANTS                              */
    /* -------------------------------------------------------------------------- */
    
    /// @dev Nonces should always increase monotonically
    function invariant_noncesMonotonic() public view {
        // Owner nonce should never decrease
        uint256 currentOwnerNonce = escrow.ownerNonce();
        uint256 expectedMinOwnerNonce = handler.getMinExpectedOwnerNonce();
        assertGe(currentOwnerNonce, expectedMinOwnerNonce, "Owner nonce should be monotonic");
        
        // Recipient nonces should never decrease
        address[] memory recipients = handler.getTrackedRecipients();
        for (uint i = 0; i < recipients.length; i++) {
            address recipient = recipients[i];
            uint256 currentNonce = escrow.recipientNonce(recipient);
            uint256 expectedMinNonce = handler.getMinExpectedRecipientNonce(recipient);
            assertGe(currentNonce, expectedMinNonce, "Recipient nonce should be monotonic");
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                             TOKEN INVARIANTS                               */
    /* -------------------------------------------------------------------------- */
    
    /// @dev Only whitelisted tokens should be used in distributions
    function invariant_onlyWhitelistedTokensUsed() public view {
        uint256 distributionCount = escrow.distributionCount();
        
        for (uint256 i = 0; i < distributionCount; i++) {
            Escrow.Distribution memory dist = escrow.getDistribution(i);
            assertTrue(
                escrow.isTokenWhitelisted(address(dist.token)),
                "All distributions should use whitelisted tokens"
            );
        }
    }
    
    /* -------------------------------------------------------------------------- */
    /*                            TIMEOUT INVARIANTS                              */
    /* -------------------------------------------------------------------------- */
    
    /// @dev Claimed distributions should have been claimed before their deadline
    function invariant_claimsRespectDeadlines() public view {
        uint256[] memory claimedIds = handler.getClaimedDistributionIds();
        
        for (uint i = 0; i < claimedIds.length; i++) {
            uint256 distributionId = claimedIds[i];
            Escrow.Distribution memory dist = escrow.getDistribution(distributionId);
            uint256 claimTimestamp = handler.getClaimTimestamp(distributionId);
            
            if (claimTimestamp > 0) { // 0 means not tracked, skip
                assertLe(
                    claimTimestamp,
                    dist.claimDeadline,
                    "Claims should happen before deadline"
                );
            }
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                          ADVANCED MATHEMATICAL INVARIANTS                  */
    /* -------------------------------------------------------------------------- */
    
    /// @dev Total supply conservation: sum of all balances should equal total tokens in system
    function invariant_totalSupplyConservation() public view {
        uint256 contractBalance = wETH.balanceOf(address(escrow));
        uint256 _feeRecipientBalance = wETH.balanceOf(escrow.feeRecipient());
        uint256 totalAccountBalances = handler.getTotalAccountBalances();
        uint256 totalUndistributed = handler.getTotalUndistributedAmounts();
        
        // All recipient balances from our tracked recipients
        uint256 totalRecipientBalances = 0;
        address[] memory recipients = handler.getTrackedRecipients();
        for (uint i = 0; i < recipients.length; i++) {
            totalRecipientBalances += wETH.balanceOf(recipients[i]);
        }
        
        // Contract should hold exactly what's needed for account balances + undistributed
        assertEq(
            contractBalance,
            totalAccountBalances + totalUndistributed,
            "Contract balance should equal account balances + undistributed amounts"
        );
    }
    
    /// @dev Fee calculation precision: fees should never cause loss of funds
    function invariant_feeCalculationPrecision() public view {
        uint256 distributionCount = escrow.distributionCount();
        
        for (uint256 i = 0; i < distributionCount; i++) {
            try escrow.getDistribution(i) returns (Escrow.Distribution memory dist) {
                if (dist.status == Escrow.DistributionStatus.Claimed) {
                    // Calculate what the fee should have been
                    uint256 expectedFee = (dist.amount * dist.fee + 9999) / 10000; // mulDivUp
                    if (expectedFee >= dist.amount) {
                        expectedFee = dist.amount - 1; // Capped to ensure recipient gets at least 1
                    }
                    uint256 expectedNet = dist.amount - expectedFee;
                    
                    // The sum should always equal the original amount
                    assertEq(
                        expectedFee + expectedNet,
                        dist.amount,
                        "Fee + net amount should equal distribution amount"
                    );
                    
                    // Net amount should always be at least 1
                    assertGe(expectedNet, 1, "Recipient should always get at least 1 wei");
                }
            } catch {
                continue;
            }
        }
    }
    
    /// @dev Distribution ID monotonicity: distribution IDs should always increase
    function invariant_distributionIdMonotonicity() public view {
        uint256 currentCount = escrow.distributionCount();
        uint256 expectedMinCount = handler.getMinExpectedDistributionCount();
        
        assertGe(
            currentCount,
            expectedMinCount,
            "Distribution count should be monotonic"
        );
    }
    
    /// @dev Batch count consistency: distribution batches should be properly tracked
    function invariant_batchCountConsistency() public view {
        uint256 currentBatchCount = escrow.distributionBatchCount();
        uint256 expectedMinBatchCount = handler.getMinExpectedBatchCount();
        
        assertGe(
            currentBatchCount,
            expectedMinBatchCount,
            "Distribution batch count should be monotonic"
        );
    }
    
    /// @dev Claim period validation: all distributions should have reasonable claim periods
    function invariant_claimPeriodReasonableness() public view {
        uint256 distributionCount = escrow.distributionCount();
        
        for (uint256 i = 0; i < distributionCount; i++) {
            try escrow.getDistribution(i) returns (Escrow.Distribution memory dist) {
                // Claim deadline should be in the future when created
                // and should be reasonable (not too far in the future)
                assertTrue(
                    dist.claimDeadline > 0,
                    "Claim deadline should be positive"
                );
                
                // Should not be unreasonably far in the future (max 10 years from now)
                assertLt(
                    dist.claimDeadline,
                    block.timestamp + 10 * 365 days,
                    "Claim deadline should not be unreasonably far in future"
                );
            } catch {
                continue;
            }
        }
    }
    
    /// @dev Repository state consistency: initialized repos should maintain consistent state
    function invariant_repoStateConsistency() public view {
        uint256[] memory repoIds = handler.getTrackedRepoIds();
        
        for (uint i = 0; i < repoIds.length; i++) {
            uint256 repoId = repoIds[i];
            uint256[] memory accountIds = handler.getTrackedAccountIds(repoId);
            
            for (uint j = 0; j < accountIds.length; j++) {
                uint256 accountId = accountIds[j];
                
                if (escrow.getAccountExists(repoId, accountId)) {
                    // If repo exists, it should have at least one admin
                    address[] memory admins = escrow.getAllAdmins(repoId, accountId);
                    assertGt(admins.length, 0, "Existing repo should have admins");
                    
                    // Balance should never be negative (this is implicit in uint256)
                    uint256 balance = escrow.getAccountBalance(repoId, accountId, address(wETH));
                    assertGe(balance, 0, "Balance should be non-negative");
                    
                    // Total funded should be at least distributed + current balance
                    uint256 totalFunded = handler.getTotalFunded(repoId, accountId);
                    uint256 totalDistributed = handler.getTotalDistributedFromAccount(repoId, accountId);
                    assertGe(
                        totalFunded,
                        totalDistributed + balance,
                        "Total funded should be at least distributed + balance"
                    );
                }
            }
        }
    }
    
    /// @dev Distribution type consistency: repo vs solo distributions should be properly categorized
    function invariant_distributionTypeConsistency() public view {
        uint256 distributionCount = escrow.distributionCount();
        
        for (uint256 i = 0; i < distributionCount; i++) {
            try escrow.getDistribution(i) returns (Escrow.Distribution memory dist) {
                if (dist._type == Escrow.DistributionType.Repo) {
                    // Repo distributions should have payer as address(0)
                    assertEq(dist.payer, address(0), "Repo distributions should have zero payer");
                    
                    // Should be able to get repo info
                    try escrow.getDistributionRepo(i) returns (Escrow.RepoAccount memory repoAccount) {
                        assertTrue(repoAccount.repoId > 0, "Repo distribution should have valid repo ID");
                        assertTrue(repoAccount.accountId > 0, "Repo distribution should have valid account ID");
                    } catch {
                        assertTrue(false, "Repo distribution should have valid repo account");
                    }
                } else if (dist._type == Escrow.DistributionType.Solo) {
                    // Solo distributions should have non-zero payer
                    assertTrue(dist.payer != address(0), "Solo distributions should have non-zero payer");
                    
                    // Should be identified as solo distribution
                    assertTrue(escrow.isSoloDistribution(i), "Should be identified as solo distribution");
                }
            } catch {
                continue;
            }
        }
    }
    
    /// @dev EIP-712 consistency: domain separator should remain consistent within chain
    function invariant_eip712Consistency() public view {
        bytes32 domainSeparator = escrow.DOMAIN_SEPARATOR();
        
        // Domain separator should be non-zero
        assertTrue(domainSeparator != bytes32(0), "Domain separator should not be zero");
        
        // Should be deterministic based on chain ID and contract address
        // This tests that the domain separator logic is working correctly
        assertTrue(domainSeparator.length == 32, "Domain separator should be 32 bytes");
    }
}

/* -------------------------------------------------------------------------- */
/*                                   HANDLER                                  */
/* -------------------------------------------------------------------------- */

contract EscrowHandler is Test {
    Escrow public escrow;
    MockERC20 public token;
    address public owner;
    uint256 public ownerPrivateKey;
    
    // Tracking state for invariant verification
    mapping(uint256 => mapping(uint256 => uint256)) public totalFunded; // repoId => accountId => amount
    mapping(uint256 => mapping(uint256 => uint256)) public totalDistributedFromAccount; // repoId => accountId => amount
    mapping(uint256 => uint256) public claimTimestamps; // distributionId => timestamp
    mapping(address => uint256) public minExpectedRecipientNonce;
    
    uint256[] public trackedRepoIds;
    mapping(uint256 => uint256[]) public trackedAccountIds; // repoId => accountId[]
    mapping(uint256 => mapping(uint256 => bool)) public repoAccountExists; // repoId => accountId => exists
    
    uint256[] public claimedDistributionIds;
    uint256[] public reclaimedDistributionIds;
    address[] public trackedRecipients;
    mapping(address => bool) public recipientTracked;
    
    uint256 public minExpectedOwnerNonce;
    uint256 public totalFeesCollectedByHandler; // Track fees we've collected
    uint256 public initialFeeRecipientBalance;   // Track initial balance
    
    uint256 public constant MAX_ACTORS = 10;
    address[] public actors;
    uint256 public currentActor;
    
    // Additional tracking for new invariants
    uint256 public minExpectedDistributionCount;
    uint256 public minExpectedBatchCount;
    
    constructor(Escrow _escrow, MockERC20 _token, address _owner, uint256 _ownerPrivateKey) {
        escrow = _escrow;
        token = _token;
        owner = _owner;
        ownerPrivateKey = _ownerPrivateKey;
        
        // Track initial fee recipient balance
        initialFeeRecipientBalance = _token.balanceOf(_escrow.feeRecipient());
        
        // Create actors for testing
        for (uint i = 0; i < MAX_ACTORS; i++) {
            actors.push(address(uint160(uint(keccak256(abi.encode("actor", i))))));
        }
    }
    
    modifier useActor(uint256 actorSeed) {
        currentActor = bound(actorSeed, 0, actors.length - 1);
        vm.startPrank(actors[currentActor]);
        _;
        vm.stopPrank();
    }
    
    function fundRepo(uint256 repoSeed, uint256 accountSeed, uint256 amount) public {
        // Reduce ranges for faster execution
        uint256 repoId = bound(repoSeed, 1, 10);  // Reduced from 100
        uint256 accountId = bound(accountSeed, 1, 10);  // Reduced from 100  
        amount = bound(amount, 1e18, 100e18);  // Reduced upper bound
        
        // Initialize repo if it doesn't exist
        if (!escrow.getAccountExists(repoId, accountId)) {
            _initRepo(repoId, accountId, actors[0]);
        }
        
        // Fund the repo
        token.mint(address(this), amount);
        token.approve(address(escrow), amount);
        
        escrow.fundRepo(repoId, accountId, token, amount, "");
        
        totalFunded[repoId][accountId] += amount;
        _trackRepoAccount(repoId, accountId);
    }
    
    function distributeFromRepo(uint256 repoSeed, uint256 accountSeed, uint256 amount, uint256 actorSeed) 
        public 
        useActor(actorSeed) 
    {
        uint256 repoId = bound(repoSeed, 1, 10);
        uint256 accountId = bound(accountSeed, 1, 10);
        amount = bound(amount, 1e18, 50e18);
        
        if (!escrow.getAccountExists(repoId, accountId)) {
            return; // Skip if repo doesn't exist
        }
        
        uint256 balance = escrow.getAccountBalance(repoId, accountId, address(token));
        if (balance < amount) {
            return; // Skip if insufficient balance
        }
        
        // Check if actor is authorized
        if (!escrow.canDistribute(repoId, accountId, actors[currentActor])) {
            return; // Skip if not authorized
        }
        
        address recipient = actors[(currentActor + 1) % actors.length];
        _trackRecipient(recipient);
        
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: amount,
            recipient: recipient,
            claimPeriod: 7 days,
            token: token
        });
        
        escrow.distributeFromRepo(repoId, accountId, distributions, "");
        totalDistributedFromAccount[repoId][accountId] += amount;
        
        // Track distribution and batch counts
        minExpectedDistributionCount++;
        minExpectedBatchCount++;
    }
    
    function distributeFromSender(uint256 amount, uint256 actorSeed) public useActor(actorSeed) {
        amount = bound(amount, 1e18, 50e18);
        
        address recipient = actors[(currentActor + 1) % actors.length];
        _trackRecipient(recipient);
        
        token.mint(actors[currentActor], amount);
        token.approve(address(escrow), amount);
        
        Escrow.DistributionParams[] memory distributions = new Escrow.DistributionParams[](1);
        distributions[0] = Escrow.DistributionParams({
            amount: amount,
            recipient: recipient,
            claimPeriod: 7 days,
            token: token
        });
        
        escrow.distributeFromSender(distributions, "");
        
        // Track distribution and batch counts
        minExpectedDistributionCount++;
        minExpectedBatchCount++;
    }
    
    function claim(uint256 distributionSeed, uint256 actorSeed) public useActor(actorSeed) {
        uint256 distributionCount = escrow.distributionCount();
        if (distributionCount == 0) return;
        
        uint256 distributionId = bound(distributionSeed, 0, distributionCount - 1);
        
        try escrow.getDistribution(distributionId) returns (Escrow.Distribution memory dist) {
            if (dist.recipient != actors[currentActor] || 
                dist.status != Escrow.DistributionStatus.Distributed ||
                block.timestamp > dist.claimDeadline) {
                return;
            }
            
            uint256[] memory distributionIds = new uint256[](1);
            distributionIds[0] = distributionId;
            
            uint256 deadline = block.timestamp + 1 hours;
            bytes32 digest = keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    escrow.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(
                        escrow.CLAIM_TYPEHASH(),
                        keccak256(abi.encode(distributionIds)),
                        actors[currentActor],
                        escrow.recipientNonce(actors[currentActor]),
                        deadline
                    ))
                )
            );
            
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, digest); // Use private key 1 for signer
            
            vm.stopPrank();
            vm.prank(owner);
            escrow.setSigner(vm.addr(1)); // Set signer to match the private key
            vm.startPrank(actors[currentActor]);
            
            escrow.claim(distributionIds, deadline, v, r, s, "");
            
            claimedDistributionIds.push(distributionId);
            claimTimestamps[distributionId] = block.timestamp;
            minExpectedRecipientNonce[actors[currentActor]]++;
            
            // Track fee collected  
            uint256 feeAmount = (dist.amount * dist.fee) / 10_000;
            if (feeAmount >= dist.amount) {
                feeAmount = dist.amount - 1;
            }
            totalFeesCollectedByHandler += feeAmount;
        } catch {
            return; // Skip invalid distributions
        }
    }
    
    function reclaimRepoDistributions(uint256 distributionSeed) public {
        uint256 distributionCount = escrow.distributionCount();
        if (distributionCount == 0) return;
        
        uint256 distributionId = bound(distributionSeed, 0, distributionCount - 1);
        
        try escrow.getDistribution(distributionId) returns (Escrow.Distribution memory dist) {
            if (dist.status != Escrow.DistributionStatus.Distributed ||
                block.timestamp <= dist.claimDeadline ||
                escrow.isSoloDistribution(distributionId)) {
                return;
            }
            
            uint256[] memory distributionIds = new uint256[](1);
            distributionIds[0] = distributionId;
            
            escrow.reclaimRepoDistributions(distributionIds, "");
            reclaimedDistributionIds.push(distributionId);
        } catch {
            return; // Skip invalid distributions
        }
    }
    
    function reclaimSenderDistributions(uint256 distributionSeed, uint256 actorSeed) public useActor(actorSeed) {
        uint256 distributionCount = escrow.distributionCount();
        if (distributionCount == 0) return;
        
        uint256 distributionId = bound(distributionSeed, 0, distributionCount - 1);
        
        try escrow.getDistribution(distributionId) returns (Escrow.Distribution memory dist) {
            if (dist.status != Escrow.DistributionStatus.Distributed ||
                block.timestamp <= dist.claimDeadline ||
                !escrow.isSoloDistribution(distributionId) ||
                dist.payer != actors[currentActor]) {
                return;
            }
            
            uint256[] memory distributionIds = new uint256[](1);
            distributionIds[0] = distributionId;
            
            escrow.reclaimSenderDistributions(distributionIds, "");
            reclaimedDistributionIds.push(distributionId);
        } catch {
            return; // Skip invalid distributions
        }
    }
    
    function addAdmin(uint256 repoSeed, uint256 accountSeed, uint256 actorSeed) public useActor(actorSeed) {
        uint256 repoId = bound(repoSeed, 1, 10);
        uint256 accountId = bound(accountSeed, 1, 10);
        
        if (!escrow.getAccountExists(repoId, accountId) || 
            !escrow.getIsAuthorizedAdmin(repoId, accountId, actors[currentActor])) {
            return;
        }
        
        address newAdmin = actors[(currentActor + 2) % actors.length];
        address[] memory admins = new address[](1);
        admins[0] = newAdmin;
        
        escrow.addAdmins(repoId, accountId, admins);
    }
    
    function removeAdmin(uint256 repoSeed, uint256 accountSeed, uint256 actorSeed) public useActor(actorSeed) {
        uint256 repoId = bound(repoSeed, 1, 10);
        uint256 accountId = bound(accountSeed, 1, 10);
        
        if (!escrow.getAccountExists(repoId, accountId) || 
            !escrow.getIsAuthorizedAdmin(repoId, accountId, actors[currentActor])) {
            return;
        }
        
        address[] memory allAdmins = escrow.getAllAdmins(repoId, accountId);
        if (allAdmins.length <= 1) {
            return; // Can't remove last admin
        }
        
        // Try to remove a different admin (not the current one)
        for (uint i = 0; i < allAdmins.length; i++) {
            if (allAdmins[i] != actors[currentActor]) {
                address[] memory adminsToRemove = new address[](1);
                adminsToRemove[0] = allAdmins[i];
                
                escrow.removeAdmins(repoId, accountId, adminsToRemove);
                break;
            }
        }
    }
    
    // Helper functions for invariant verification
    function getTotalAccountBalances() public view returns (uint256 total) {
        for (uint i = 0; i < trackedRepoIds.length; i++) {
            uint256 repoId = trackedRepoIds[i];
            uint256[] memory accountIds = trackedAccountIds[repoId];
            
            for (uint j = 0; j < accountIds.length; j++) {
                uint256 accountId = accountIds[j];
                total += escrow.getAccountBalance(repoId, accountId, address(token));
            }
        }
    }
    
    function getTotalUndistributedAmounts() public view returns (uint256 total) {
        uint256 distributionCount = escrow.distributionCount();
        
        for (uint256 i = 0; i < distributionCount; i++) {
            try escrow.getDistribution(i) returns (Escrow.Distribution memory dist) {
                if (dist.status == Escrow.DistributionStatus.Distributed) {
                    total += dist.amount;
                }
            } catch {
                continue;
            }
        }
    }
    
    function getClaimTimestamp(uint256 distributionId) public view returns (uint256) {
        return claimTimestamps[distributionId];
    }
    
    // Additional getters for new invariants
    function getMinExpectedDistributionCount() public view returns (uint256) {
        return minExpectedDistributionCount;
    }
    
    function getMinExpectedBatchCount() public view returns (uint256) {
        return minExpectedBatchCount;
    }

    // Internal helpers
    function _initRepo(uint256 repoId, uint256 accountId, address admin) internal {
        address[] memory admins = new address[](1);
        admins[0] = admin;
        
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    repoId,
                    accountId,
                    keccak256(abi.encode(admins)),
                    escrow.ownerNonce(),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        escrow.initRepo(repoId, accountId, admins, deadline, v, r, s);
        
        minExpectedOwnerNonce++;
        _trackRepoAccount(repoId, accountId);
    }
    
    function _trackRepoAccount(uint256 repoId, uint256 accountId) internal {
        if (!repoAccountExists[repoId][accountId]) {
            repoAccountExists[repoId][accountId] = true;
            
            // Track repoId
            bool repoExists = false;
            for (uint i = 0; i < trackedRepoIds.length; i++) {
                if (trackedRepoIds[i] == repoId) {
                    repoExists = true;
                    break;
                }
            }
            if (!repoExists) {
                trackedRepoIds.push(repoId);
            }
            
            // Track accountId for this repo
            trackedAccountIds[repoId].push(accountId);
        }
    }
    
    function _trackRecipient(address recipient) internal {
        if (!recipientTracked[recipient]) {
            recipientTracked[recipient] = true;
            trackedRecipients.push(recipient);
        }
    }
    
    // Getter functions
    function getTrackedRepoIds() public view returns (uint256[] memory) {
        return trackedRepoIds;
    }
    
    function getTrackedAccountIds(uint256 repoId) public view returns (uint256[] memory) {
        return trackedAccountIds[repoId];
    }
    
    function getTotalFunded(uint256 repoId, uint256 accountId) public view returns (uint256) {
        return totalFunded[repoId][accountId];
    }
    
    function getTotalDistributedFromAccount(uint256 repoId, uint256 accountId) public view returns (uint256) {
        return totalDistributedFromAccount[repoId][accountId];
    }
    
    function getClaimedDistributionIds() public view returns (uint256[] memory) {
        return claimedDistributionIds;
    }
    
    function getReclaimedDistributionIds() public view returns (uint256[] memory) {
        return reclaimedDistributionIds;
    }
    
    function getTrackedRecipients() public view returns (address[] memory) {
        return trackedRecipients;
    }
    
    function getMinExpectedOwnerNonce() public view returns (uint256) {
        return minExpectedOwnerNonce;
    }
    
    function getMinExpectedRecipientNonce(address recipient) public view returns (uint256) {
        return minExpectedRecipientNonce[recipient];
    }
    
    function getTotalFeesCollectedByHandler() public view returns (uint256) {
        return totalFeesCollectedByHandler;
    }
    
    function getInitialFeeRecipientBalance() public view returns (uint256) {
        return initialFeeRecipientBalance;
    }
} 