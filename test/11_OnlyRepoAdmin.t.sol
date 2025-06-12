// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "./00_Escrow.t.sol";

contract OnlyRepoAdmin_Test is Base_Test {
    
    uint256 constant REPO_ID = 1;
    uint256 constant ACCOUNT_ID = 100;
    uint256 constant REPO_ID_2 = 2;
    uint256 constant ACCOUNT_ID_2 = 200;

    address repoAdmin;
    address newAdmin;
    address distributor1;
    address distributor2;
    address distributor3;
    address unauthorized;

    uint256 adminPrivateKey = 0x1111111111111111111111111111111111111111111111111111111111111111;
    
    function setUp() public override {
        super.setUp();
        
        repoAdmin = vm.addr(adminPrivateKey);
        newAdmin = makeAddr("newAdmin");
        distributor1 = makeAddr("distributor1");
        distributor2 = makeAddr("distributor2");
        distributor3 = makeAddr("distributor3");
        unauthorized = makeAddr("unauthorized");
        
        // Initialize repos
        _initializeRepo(REPO_ID, ACCOUNT_ID, repoAdmin);
        _initializeRepo(REPO_ID_2, ACCOUNT_ID_2, repoAdmin);
    }

    function _initializeRepo(uint256 repoId, uint256 accountId, address admin) internal {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    repoId,
                    accountId,
                    admin,
                    escrow.ownerNonce(),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        escrow.initRepo(repoId, accountId, admin, deadline, v, r, s);
    }

    /* -------------------------------------------------------------------------- */
    /*                           TRANSFER REPO ADMIN TESTS                        */
    /* -------------------------------------------------------------------------- */

    function test_transferRepoAdmin_success() public {
        assertEq(escrow.getAccountAdmin(REPO_ID, ACCOUNT_ID), repoAdmin);

        vm.expectEmit(true, true, true, true);
        emit RepoAdminChanged(REPO_ID, repoAdmin, newAdmin);

        vm.prank(repoAdmin);
        escrow.transferRepoAdmin(REPO_ID, ACCOUNT_ID, newAdmin);

        assertEq(escrow.getAccountAdmin(REPO_ID, ACCOUNT_ID), newAdmin);
    }

    function test_transferRepoAdmin_multipleRepos() public {
        address admin2 = makeAddr("admin2");
        address admin3 = makeAddr("admin3");

        // Transfer different repos to different admins
        vm.prank(repoAdmin);
        escrow.transferRepoAdmin(REPO_ID, ACCOUNT_ID, admin2);

        vm.prank(repoAdmin);
        escrow.transferRepoAdmin(REPO_ID_2, ACCOUNT_ID_2, admin3);

        assertEq(escrow.getAccountAdmin(REPO_ID, ACCOUNT_ID), admin2);
        assertEq(escrow.getAccountAdmin(REPO_ID_2, ACCOUNT_ID_2), admin3);
    }

    function test_transferRepoAdmin_newAdminCanTransfer() public {
        // Transfer to new admin
        vm.prank(repoAdmin);
        escrow.transferRepoAdmin(REPO_ID, ACCOUNT_ID, newAdmin);

        address finalAdmin = makeAddr("finalAdmin");

        // New admin can transfer again
        vm.prank(newAdmin);
        escrow.transferRepoAdmin(REPO_ID, ACCOUNT_ID, finalAdmin);

        assertEq(escrow.getAccountAdmin(REPO_ID, ACCOUNT_ID), finalAdmin);
    }

    function test_transferRepoAdmin_revert_notRepoAdmin() public {
        expectRevert(Errors.NOT_REPO_ADMIN);
        vm.prank(unauthorized);
        escrow.transferRepoAdmin(REPO_ID, ACCOUNT_ID, newAdmin);
    }

    function test_transferRepoAdmin_revert_oldAdminCantTransfer() public {
        // Transfer to new admin
        vm.prank(repoAdmin);
        escrow.transferRepoAdmin(REPO_ID, ACCOUNT_ID, newAdmin);

        // Old admin should no longer be able to transfer
        expectRevert(Errors.NOT_REPO_ADMIN);
        vm.prank(repoAdmin);
        escrow.transferRepoAdmin(REPO_ID, ACCOUNT_ID, unauthorized);
    }

    function test_transferRepoAdmin_revert_invalidAddress() public {
        expectRevert(Errors.INVALID_ADDRESS);
        vm.prank(repoAdmin);
        escrow.transferRepoAdmin(REPO_ID, ACCOUNT_ID, address(0));
    }

    /* -------------------------------------------------------------------------- */
    /*                             ADD DISTRIBUTOR TESTS                          */
    /* -------------------------------------------------------------------------- */

    function test_addDistributor_success() public {
        address[] memory distributors = new address[](1);
        distributors[0] = distributor1;

        assertFalse(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributor1));

        vm.expectEmit(true, true, true, true);
        emit AddedDistributor(REPO_ID, ACCOUNT_ID, distributor1);

        vm.prank(repoAdmin);
        escrow.addDistributor(REPO_ID, ACCOUNT_ID, distributors);

        assertTrue(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributor1));
        assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, distributor1));
    }

    function test_addDistributor_multiple() public {
        address[] memory distributors = new address[](3);
        distributors[0] = distributor1;
        distributors[1] = distributor2;
        distributors[2] = distributor3;

        vm.prank(repoAdmin);
        escrow.addDistributor(REPO_ID, ACCOUNT_ID, distributors);

        assertTrue(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributor1));
        assertTrue(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributor2));
        assertTrue(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributor3));
    }

    function test_addDistributor_alreadyExists() public {
        address[] memory distributors = new address[](1);
        distributors[0] = distributor1;

        // Add distributor first time
        vm.prank(repoAdmin);
        escrow.addDistributor(REPO_ID, ACCOUNT_ID, distributors);

        // Adding again should not emit event (idempotent)
        vm.recordLogs();
        vm.prank(repoAdmin);
        escrow.addDistributor(REPO_ID, ACCOUNT_ID, distributors);
        
        // Should still be authorized
        assertTrue(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributor1));
    }

    function test_addDistributor_adminCanDistribute() public view {
        // Admin should always be able to distribute even without being in distributors list
        assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, repoAdmin));
    }

    function test_addDistributor_separateRepos() public {
        address[] memory distributors = new address[](1);
        distributors[0] = distributor1;

        // Add to first repo
        vm.prank(repoAdmin);
        escrow.addDistributor(REPO_ID, ACCOUNT_ID, distributors);

        // Should only be authorized for first repo
        assertTrue(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributor1));
        assertFalse(escrow.getIsAuthorizedDistributor(REPO_ID_2, ACCOUNT_ID_2, distributor1));
    }

    function test_addDistributor_revert_notRepoAdmin() public {
        address[] memory distributors = new address[](1);
        distributors[0] = distributor1;

        expectRevert(Errors.NOT_REPO_ADMIN);
        vm.prank(unauthorized);
        escrow.addDistributor(REPO_ID, ACCOUNT_ID, distributors);
    }

    function test_addDistributor_revert_batchLimitExceeded() public {
        uint256 batchLimit = escrow.batchLimit();
        address[] memory distributors = new address[](batchLimit + 1);
        
        for (uint i = 0; i < batchLimit + 1; i++) {
            distributors[i] = makeAddr(string(abi.encodePacked("distributor", i)));
        }

        expectRevert(Errors.BATCH_LIMIT_EXCEEDED);
        vm.prank(repoAdmin);
        escrow.addDistributor(REPO_ID, ACCOUNT_ID, distributors);
    }

    function test_addDistributor_revert_invalidAddress() public {
        address[] memory distributors = new address[](2);
        distributors[0] = distributor1;
        distributors[1] = address(0); // Invalid

        expectRevert(Errors.INVALID_ADDRESS);
        vm.prank(repoAdmin);
        escrow.addDistributor(REPO_ID, ACCOUNT_ID, distributors);
    }

    function test_addDistributor_maxBatchLimit() public {
        uint256 batchLimit = escrow.batchLimit();
        address[] memory distributors = new address[](batchLimit);
        
        for (uint i = 0; i < batchLimit; i++) {
            distributors[i] = makeAddr(string(abi.encodePacked("distributor", i)));
        }

        vm.prank(repoAdmin);
        escrow.addDistributor(REPO_ID, ACCOUNT_ID, distributors);

        // All should be authorized
        for (uint i = 0; i < batchLimit; i++) {
            assertTrue(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributors[i]));
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                           REMOVE DISTRIBUTOR TESTS                         */
    /* -------------------------------------------------------------------------- */

    function test_removeDistributor_success() public {
        // First add distributor
        address[] memory distributors = new address[](1);
        distributors[0] = distributor1;

        vm.prank(repoAdmin);
        escrow.addDistributor(REPO_ID, ACCOUNT_ID, distributors);
        assertTrue(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributor1));

        // Then remove
        vm.expectEmit(true, true, true, true);
        emit RemovedDistributor(REPO_ID, ACCOUNT_ID, distributor1);

        vm.prank(repoAdmin);
        escrow.removeDistributor(REPO_ID, ACCOUNT_ID, distributors);

        assertFalse(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributor1));
        assertFalse(escrow.canDistribute(REPO_ID, ACCOUNT_ID, distributor1));
    }

    function test_removeDistributor_multiple() public {
        // Add multiple distributors
        address[] memory distributors = new address[](3);
        distributors[0] = distributor1;
        distributors[1] = distributor2;
        distributors[2] = distributor3;

        vm.prank(repoAdmin);
        escrow.addDistributor(REPO_ID, ACCOUNT_ID, distributors);

        // Remove two of them
        address[] memory toRemove = new address[](2);
        toRemove[0] = distributor1;
        toRemove[1] = distributor3;

        vm.prank(repoAdmin);
        escrow.removeDistributor(REPO_ID, ACCOUNT_ID, toRemove);

        assertFalse(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributor1));
        assertTrue(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributor2)); // Should remain
        assertFalse(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributor3));
    }

    function test_removeDistributor_notExists() public {
        address[] memory distributors = new address[](1);
        distributors[0] = distributor1;

        // Removing non-existent distributor should not emit event (idempotent)
        vm.recordLogs();
        vm.prank(repoAdmin);
        escrow.removeDistributor(REPO_ID, ACCOUNT_ID, distributors);
        
        assertFalse(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributor1));
    }

    function test_removeDistributor_adminStillCanDistribute() public {
        // Even if admin is somehow in distributor list and removed, admin should still be able to distribute
        address[] memory distributors = new address[](1);
        distributors[0] = repoAdmin;

        vm.prank(repoAdmin);
        escrow.addDistributor(REPO_ID, ACCOUNT_ID, distributors);

        vm.prank(repoAdmin);
        escrow.removeDistributor(REPO_ID, ACCOUNT_ID, distributors);

        // Admin should still be able to distribute
        assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, repoAdmin));
    }

    function test_removeDistributor_revert_notRepoAdmin() public {
        address[] memory distributors = new address[](1);
        distributors[0] = distributor1;

        expectRevert(Errors.NOT_REPO_ADMIN);
        vm.prank(unauthorized);
        escrow.removeDistributor(REPO_ID, ACCOUNT_ID, distributors);
    }

    function test_removeDistributor_revert_batchLimitExceeded() public {
        uint256 batchLimit = escrow.batchLimit();
        address[] memory distributors = new address[](batchLimit + 1);
        
        for (uint i = 0; i < batchLimit + 1; i++) {
            distributors[i] = makeAddr(string(abi.encodePacked("distributor", i)));
        }

        expectRevert(Errors.BATCH_LIMIT_EXCEEDED);
        vm.prank(repoAdmin);
        escrow.removeDistributor(REPO_ID, ACCOUNT_ID, distributors);
    }

    /* -------------------------------------------------------------------------- */
    /*                              INTEGRATION TESTS                             */
    /* -------------------------------------------------------------------------- */

    function test_distributorLifecycle() public {
        // Add distributors
        address[] memory distributors = new address[](2);
        distributors[0] = distributor1;
        distributors[1] = distributor2;

        vm.prank(repoAdmin);
        escrow.addDistributor(REPO_ID, ACCOUNT_ID, distributors);

        assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, distributor1));
        assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, distributor2));

        // Remove one
        address[] memory toRemove = new address[](1);
        toRemove[0] = distributor1;

        vm.prank(repoAdmin);
        escrow.removeDistributor(REPO_ID, ACCOUNT_ID, toRemove);

        assertFalse(escrow.canDistribute(REPO_ID, ACCOUNT_ID, distributor1));
        assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, distributor2));

        // Add back
        vm.prank(repoAdmin);
        escrow.addDistributor(REPO_ID, ACCOUNT_ID, toRemove);

        assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, distributor1));
        assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, distributor2));
    }

    function test_adminTransferAndDistributors() public {
        // Add distributors
        address[] memory distributors = new address[](1);
        distributors[0] = distributor1;

        vm.prank(repoAdmin);
        escrow.addDistributor(REPO_ID, ACCOUNT_ID, distributors);

        // Transfer admin
        vm.prank(repoAdmin);
        escrow.transferRepoAdmin(REPO_ID, ACCOUNT_ID, newAdmin);

        // Old admin should not be able to manage distributors
        expectRevert(Errors.NOT_REPO_ADMIN);
        vm.prank(repoAdmin);
        escrow.removeDistributor(REPO_ID, ACCOUNT_ID, distributors);

        // New admin should be able to manage distributors
        vm.prank(newAdmin);
        escrow.removeDistributor(REPO_ID, ACCOUNT_ID, distributors);

        assertFalse(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributor1));

        // New admin should be able to distribute
        assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, newAdmin));
        // Old admin should not
        assertFalse(escrow.canDistribute(REPO_ID, ACCOUNT_ID, repoAdmin));
    }

    function test_multipleReposSeparateDistributors() public {
        address[] memory distributors1 = new address[](1);
        distributors1[0] = distributor1;

        address[] memory distributors2 = new address[](1);
        distributors2[0] = distributor2;

        // Add different distributors to different repos
        vm.prank(repoAdmin);
        escrow.addDistributor(REPO_ID, ACCOUNT_ID, distributors1);

        vm.prank(repoAdmin);
        escrow.addDistributor(REPO_ID_2, ACCOUNT_ID_2, distributors2);

        // Each distributor should only work for their repo
        assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, distributor1));
        assertFalse(escrow.canDistribute(REPO_ID, ACCOUNT_ID, distributor2));

        assertFalse(escrow.canDistribute(REPO_ID_2, ACCOUNT_ID_2, distributor1));
        assertTrue(escrow.canDistribute(REPO_ID_2, ACCOUNT_ID_2, distributor2));

        // Admin should work for both
        assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, repoAdmin));
        assertTrue(escrow.canDistribute(REPO_ID_2, ACCOUNT_ID_2, repoAdmin));
    }

    function test_distributorManagement_fuzz(uint8 numDistributors) public {
        vm.assume(numDistributors > 0 && numDistributors <= 10); // Reasonable limit for test

        address[] memory distributors = new address[](numDistributors);
        for (uint i = 0; i < numDistributors; i++) {
            distributors[i] = makeAddr(string(abi.encodePacked("fuzzDistributor", i)));
        }

        // Add all distributors
        vm.prank(repoAdmin);
        escrow.addDistributor(REPO_ID, ACCOUNT_ID, distributors);

        // Verify all were added
        for (uint i = 0; i < numDistributors; i++) {
            assertTrue(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributors[i]));
        }

        // Remove all distributors
        vm.prank(repoAdmin);
        escrow.removeDistributor(REPO_ID, ACCOUNT_ID, distributors);

        // Verify all were removed
        for (uint i = 0; i < numDistributors; i++) {
            assertFalse(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributors[i]));
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                                    EVENTS                                  */
    /* -------------------------------------------------------------------------- */

    event RepoAdminChanged(uint256 indexed repoId, address indexed oldAdmin, address indexed newAdmin);
    event AddedDistributor(uint256 indexed repoId, uint256 indexed accountId, address indexed distributor);
    event RemovedDistributor(uint256 indexed repoId, uint256 indexed accountId, address indexed distributor);
} 