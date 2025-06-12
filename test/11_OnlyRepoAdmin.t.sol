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
        
        // Initialize repos with single admin
        address[] memory initialAdmins1 = new address[](1);
        initialAdmins1[0] = repoAdmin;
        _initializeRepo(REPO_ID, ACCOUNT_ID, initialAdmins1);
        
        address[] memory initialAdmins2 = new address[](1);
        initialAdmins2[0] = repoAdmin;
        _initializeRepo(REPO_ID_2, ACCOUNT_ID_2, initialAdmins2);
    }

    function _initializeRepo(uint256 repoId, uint256 accountId, address[] memory admins) internal {
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
    }



    /* -------------------------------------------------------------------------- */
    /*                           ADD DISTRIBUTORS TESTS                           */
    /* -------------------------------------------------------------------------- */

    function test_addDistributors_success() public {
        address[] memory distributors = new address[](1);
        distributors[0] = distributor1;

        assertFalse(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributor1));

        vm.expectEmit(true, true, true, true);
        emit AddedDistributor(REPO_ID, ACCOUNT_ID, distributor1);

        vm.prank(repoAdmin);
        escrow.addDistributors(REPO_ID, ACCOUNT_ID, distributors);

        assertTrue(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributor1));
        assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, distributor1));
    }

    function test_addDistributors_multiple() public {
        address[] memory distributors = new address[](3);
        distributors[0] = distributor1;
        distributors[1] = distributor2;
        distributors[2] = distributor3;

        vm.prank(repoAdmin);
        escrow.addDistributors(REPO_ID, ACCOUNT_ID, distributors);

        assertTrue(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributor1));
        assertTrue(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributor2));
        assertTrue(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributor3));
    }

    function test_addDistributors_alreadyExists() public {
        address[] memory distributors = new address[](1);
        distributors[0] = distributor1;

        // Add distributor first time
        vm.prank(repoAdmin);
        escrow.addDistributors(REPO_ID, ACCOUNT_ID, distributors);

        // Adding again should not emit event (idempotent)
        vm.recordLogs();
        vm.prank(repoAdmin);
        escrow.addDistributors(REPO_ID, ACCOUNT_ID, distributors);
        
        // Should still be authorized
        assertTrue(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributor1));
    }

    function test_addDistributors_adminCanDistribute() public view {
        // Admin should always be able to distribute even without being in distributors list
        assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, repoAdmin));
    }

    function test_addDistributors_separateRepos() public {
        address[] memory distributors = new address[](1);
        distributors[0] = distributor1;

        // Add to first repo
        vm.prank(repoAdmin);
        escrow.addDistributors(REPO_ID, ACCOUNT_ID, distributors);

        // Should only be authorized for first repo
        assertTrue(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributor1));
        assertFalse(escrow.getIsAuthorizedDistributor(REPO_ID_2, ACCOUNT_ID_2, distributor1));
    }

    function test_addDistributors_revert_notRepoAdmin() public {
        address[] memory distributors = new address[](1);
        distributors[0] = distributor1;

        expectRevert(Errors.NOT_REPO_ADMIN);
        vm.prank(unauthorized);
        escrow.addDistributors(REPO_ID, ACCOUNT_ID, distributors);
    }

    function test_addDistributors_revert_batchLimitExceeded() public {
        uint256 batchLimit = escrow.batchLimit();
        address[] memory distributors = new address[](batchLimit + 1);
        
        for (uint i = 0; i < batchLimit + 1; i++) {
            distributors[i] = makeAddr(string(abi.encodePacked("distributor", i)));
        }

        expectRevert(Errors.BATCH_LIMIT_EXCEEDED);
        vm.prank(repoAdmin);
        escrow.addDistributors(REPO_ID, ACCOUNT_ID, distributors);
    }

    function test_addDistributors_revert_invalidAddress() public {
        address[] memory distributors = new address[](2);
        distributors[0] = distributor1;
        distributors[1] = address(0); // Invalid

        expectRevert(Errors.INVALID_ADDRESS);
        vm.prank(repoAdmin);
        escrow.addDistributors(REPO_ID, ACCOUNT_ID, distributors);
    }

    function test_addDistributors_maxBatchLimit() public {
        uint256 batchLimit = escrow.batchLimit();
        address[] memory distributors = new address[](batchLimit);
        
        for (uint i = 0; i < batchLimit; i++) {
            distributors[i] = makeAddr(string(abi.encodePacked("distributor", i)));
        }

        vm.prank(repoAdmin);
        escrow.addDistributors(REPO_ID, ACCOUNT_ID, distributors);

        // All should be authorized
        for (uint i = 0; i < batchLimit; i++) {
            assertTrue(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributors[i]));
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                          REMOVE DISTRIBUTORS TESTS                         */
    /* -------------------------------------------------------------------------- */

    function test_removeDistributors_success() public {
        // First add distributor
        address[] memory distributors = new address[](1);
        distributors[0] = distributor1;

        vm.prank(repoAdmin);
        escrow.addDistributors(REPO_ID, ACCOUNT_ID, distributors);
        assertTrue(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributor1));

        // Then remove
        vm.expectEmit(true, true, true, true);
        emit RemovedDistributor(REPO_ID, ACCOUNT_ID, distributor1);

        vm.prank(repoAdmin);
        escrow.removeDistributors(REPO_ID, ACCOUNT_ID, distributors);

        assertFalse(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributor1));
        assertFalse(escrow.canDistribute(REPO_ID, ACCOUNT_ID, distributor1));
    }

    function test_removeDistributors_multiple() public {
        // Add multiple distributors
        address[] memory distributors = new address[](3);
        distributors[0] = distributor1;
        distributors[1] = distributor2;
        distributors[2] = distributor3;

        vm.prank(repoAdmin);
        escrow.addDistributors(REPO_ID, ACCOUNT_ID, distributors);

        // Remove two of them
        address[] memory toRemove = new address[](2);
        toRemove[0] = distributor1;
        toRemove[1] = distributor3;

        vm.prank(repoAdmin);
        escrow.removeDistributors(REPO_ID, ACCOUNT_ID, toRemove);

        assertFalse(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributor1));
        assertTrue(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributor2)); // Should remain
        assertFalse(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributor3));
    }

    function test_removeDistributors_notExists() public {
        address[] memory distributors = new address[](1);
        distributors[0] = distributor1;

        // Removing non-existent distributor should not emit event (idempotent)
        vm.recordLogs();
        vm.prank(repoAdmin);
        escrow.removeDistributors(REPO_ID, ACCOUNT_ID, distributors);
        
        assertFalse(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributor1));
    }

    function test_removeDistributors_adminStillCanDistribute() public {
        // Even if admin is somehow in distributor list and removed, admin should still be able to distribute
        address[] memory distributors = new address[](1);
        distributors[0] = repoAdmin;

        vm.prank(repoAdmin);
        escrow.addDistributors(REPO_ID, ACCOUNT_ID, distributors);

        vm.prank(repoAdmin);
        escrow.removeDistributors(REPO_ID, ACCOUNT_ID, distributors);

        // Admin should still be able to distribute
        assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, repoAdmin));
    }

    function test_removeDistributors_revert_notRepoAdmin() public {
        address[] memory distributors = new address[](1);
        distributors[0] = distributor1;

        expectRevert(Errors.NOT_REPO_ADMIN);
        vm.prank(unauthorized);
        escrow.removeDistributors(REPO_ID, ACCOUNT_ID, distributors);
    }

    function test_removeDistributors_revert_batchLimitExceeded() public {
        uint256 batchLimit = escrow.batchLimit();
        address[] memory distributors = new address[](batchLimit + 1);
        
        for (uint i = 0; i < batchLimit + 1; i++) {
            distributors[i] = makeAddr(string(abi.encodePacked("distributor", i)));
        }

        expectRevert(Errors.BATCH_LIMIT_EXCEEDED);
        vm.prank(repoAdmin);
        escrow.removeDistributors(REPO_ID, ACCOUNT_ID, distributors);
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
        escrow.addDistributors(REPO_ID, ACCOUNT_ID, distributors);

        assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, distributor1));
        assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, distributor2));

        // Remove one
        address[] memory toRemove = new address[](1);
        toRemove[0] = distributor1;

        vm.prank(repoAdmin);
        escrow.removeDistributors(REPO_ID, ACCOUNT_ID, toRemove);

        assertFalse(escrow.canDistribute(REPO_ID, ACCOUNT_ID, distributor1));
        assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, distributor2));

        // Add back
        vm.prank(repoAdmin);
        escrow.addDistributors(REPO_ID, ACCOUNT_ID, toRemove);

        assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, distributor1));
        assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, distributor2));
    }

    function test_adminTransferAndDistributors() public {
        // Add distributors
        address[] memory distributors = new address[](1);
        distributors[0] = distributor1;

        vm.prank(repoAdmin);
        escrow.addDistributors(REPO_ID, ACCOUNT_ID, distributors);

        // Add new admin and remove old admin
        address[] memory adminsToAdd = new address[](1);
        adminsToAdd[0] = newAdmin;
        vm.prank(repoAdmin);
        escrow.addAdmins(REPO_ID, ACCOUNT_ID, adminsToAdd);

        address[] memory adminsToRemove = new address[](1);
        adminsToRemove[0] = repoAdmin;
        vm.prank(newAdmin);
        escrow.removeAdmins(REPO_ID, ACCOUNT_ID, adminsToRemove);

        // Old admin should not be able to manage distributors
        expectRevert(Errors.NOT_REPO_ADMIN);
        vm.prank(repoAdmin);
        escrow.removeDistributors(REPO_ID, ACCOUNT_ID, distributors);

        // New admin should be able to manage distributors
        vm.prank(newAdmin);
        escrow.removeDistributors(REPO_ID, ACCOUNT_ID, distributors);

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
        escrow.addDistributors(REPO_ID, ACCOUNT_ID, distributors1);

        vm.prank(repoAdmin);
        escrow.addDistributors(REPO_ID_2, ACCOUNT_ID_2, distributors2);

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
        escrow.addDistributors(REPO_ID, ACCOUNT_ID, distributors);

        // Verify all were added
        for (uint i = 0; i < numDistributors; i++) {
            assertTrue(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributors[i]));
        }

        // Remove all distributors
        vm.prank(repoAdmin);
        escrow.removeDistributors(REPO_ID, ACCOUNT_ID, distributors);

        // Verify all were removed
        for (uint i = 0; i < numDistributors; i++) {
            assertFalse(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributors[i]));
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                                    EVENTS                                  */
    /* -------------------------------------------------------------------------- */

    event AdminSet(uint256 indexed repoId, uint256 indexed accountId, address oldAdmin, address indexed newAdmin);
    event RepoAdminChanged(uint256 indexed repoId, address indexed oldAdmin, address indexed newAdmin);
    event AddedDistributor(uint256 indexed repoId, uint256 indexed accountId, address indexed distributor);
    event RemovedDistributor(uint256 indexed repoId, uint256 indexed accountId, address indexed distributor);

    /* -------------------------------------------------------------------------- */
    /*                             ADD ADMINS TESTS                               */
    /* -------------------------------------------------------------------------- */

    function test_addAdmins_success() public {
        address[] memory adminsToAdd = new address[](1);
        adminsToAdd[0] = newAdmin;

        assertFalse(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, newAdmin));

        vm.expectEmit(true, true, true, true);
        emit AdminSet(REPO_ID, ACCOUNT_ID, address(0), newAdmin);

        vm.prank(repoAdmin);
        escrow.addAdmins(REPO_ID, ACCOUNT_ID, adminsToAdd);

        assertTrue(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, newAdmin));
        assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, newAdmin));
        
        // Verify both admins are in the set
        address[] memory allAdmins = escrow.getAllAdmins(REPO_ID, ACCOUNT_ID);
        assertEq(allAdmins.length, 2);
    }

    function test_addAdmins_multiple() public {
        address admin1 = makeAddr("admin1");
        address admin2 = makeAddr("admin2");
        address admin3 = makeAddr("admin3");
        
        address[] memory adminsToAdd = new address[](3);
        adminsToAdd[0] = admin1;
        adminsToAdd[1] = admin2;
        adminsToAdd[2] = admin3;

        vm.expectEmit(true, true, true, true);
        emit AdminSet(REPO_ID, ACCOUNT_ID, address(0), admin1);
        vm.expectEmit(true, true, true, true);
        emit AdminSet(REPO_ID, ACCOUNT_ID, address(0), admin2);
        vm.expectEmit(true, true, true, true);
        emit AdminSet(REPO_ID, ACCOUNT_ID, address(0), admin3);

        vm.prank(repoAdmin);
        escrow.addAdmins(REPO_ID, ACCOUNT_ID, adminsToAdd);

        assertTrue(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, admin1));
        assertTrue(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, admin2));
        assertTrue(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, admin3));
        
        // All should be able to distribute
        assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, admin1));
        assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, admin2));
        assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, admin3));
        
        // Verify all admins are in the set (original + 3 new = 4 total)
        address[] memory allAdmins = escrow.getAllAdmins(REPO_ID, ACCOUNT_ID);
        assertEq(allAdmins.length, 4);
    }

    function test_addAdmins_duplicate() public {
        address[] memory adminsToAdd = new address[](2);
        adminsToAdd[0] = repoAdmin; // Already an admin
        adminsToAdd[1] = newAdmin;

        // Only newAdmin should emit event since repoAdmin is already an admin
        vm.expectEmit(true, true, true, true);
        emit AdminSet(REPO_ID, ACCOUNT_ID, address(0), newAdmin);

        vm.prank(repoAdmin);
        escrow.addAdmins(REPO_ID, ACCOUNT_ID, adminsToAdd);

        assertTrue(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, repoAdmin));
        assertTrue(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, newAdmin));
        
        // Should still be 2 admins (no duplicates)
        address[] memory allAdmins = escrow.getAllAdmins(REPO_ID, ACCOUNT_ID);
        assertEq(allAdmins.length, 2);
    }

    function test_addAdmins_newAdminCanAddMore() public {
        // Add newAdmin
        address[] memory adminsToAdd = new address[](1);
        adminsToAdd[0] = newAdmin;
        vm.prank(repoAdmin);
        escrow.addAdmins(REPO_ID, ACCOUNT_ID, adminsToAdd);

        // newAdmin should be able to add more admins
        address admin3 = makeAddr("admin3");
        address[] memory moreAdmins = new address[](1);
        moreAdmins[0] = admin3;
        
        vm.prank(newAdmin);
        escrow.addAdmins(REPO_ID, ACCOUNT_ID, moreAdmins);

        assertTrue(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, admin3));
    }

    function test_addAdmins_revert_emptyArray() public {
        address[] memory adminsToAdd = new address[](0);

        expectRevert(Errors.INVALID_AMOUNT);
        vm.prank(repoAdmin);
        escrow.addAdmins(REPO_ID, ACCOUNT_ID, adminsToAdd);
    }

    function test_addAdmins_revert_invalidAddress() public {
        address[] memory adminsToAdd = new address[](2);
        adminsToAdd[0] = newAdmin;
        adminsToAdd[1] = address(0); // Invalid

        expectRevert(Errors.INVALID_ADDRESS);
        vm.prank(repoAdmin);
        escrow.addAdmins(REPO_ID, ACCOUNT_ID, adminsToAdd);
    }

    function test_addAdmins_revert_notRepoAdmin() public {
        address[] memory adminsToAdd = new address[](1);
        adminsToAdd[0] = newAdmin;

        expectRevert(Errors.NOT_REPO_ADMIN);
        vm.prank(unauthorized);
        escrow.addAdmins(REPO_ID, ACCOUNT_ID, adminsToAdd);
    }

    function test_addAdmins_revert_batchLimitExceeded() public {
        uint256 batchLimit = escrow.batchLimit();
        address[] memory adminsToAdd = new address[](batchLimit + 1);
        
        for (uint i = 0; i < batchLimit + 1; i++) {
            adminsToAdd[i] = makeAddr(string(abi.encodePacked("admin", i)));
        }

        expectRevert(Errors.BATCH_LIMIT_EXCEEDED);
        vm.prank(repoAdmin);
        escrow.addAdmins(REPO_ID, ACCOUNT_ID, adminsToAdd);
    }

    /* -------------------------------------------------------------------------- */
    /*                            REMOVE ADMINS TESTS                             */
    /* -------------------------------------------------------------------------- */

    function test_removeAdmins_success() public {
        // First add another admin
        address[] memory adminsToAdd = new address[](1);
        adminsToAdd[0] = newAdmin;
        vm.prank(repoAdmin);
        escrow.addAdmins(REPO_ID, ACCOUNT_ID, adminsToAdd);

        // Now remove the original admin
        address[] memory adminsToRemove = new address[](1);
        adminsToRemove[0] = repoAdmin;

        vm.expectEmit(true, true, true, true);
        emit RepoAdminChanged(REPO_ID, repoAdmin, address(0));

        vm.prank(newAdmin);
        escrow.removeAdmins(REPO_ID, ACCOUNT_ID, adminsToRemove);

        assertFalse(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, repoAdmin));
        assertTrue(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, newAdmin));
        assertFalse(escrow.canDistribute(REPO_ID, ACCOUNT_ID, repoAdmin));
        
        // Should be 1 admin left
        address[] memory allAdmins = escrow.getAllAdmins(REPO_ID, ACCOUNT_ID);
        assertEq(allAdmins.length, 1);
        assertEq(allAdmins[0], newAdmin);
    }

    function test_removeAdmins_multiple() public {
        // Add multiple admins
        address admin1 = makeAddr("admin1");
        address admin2 = makeAddr("admin2");
        address admin3 = makeAddr("admin3");
        
        address[] memory adminsToAdd = new address[](3);
        adminsToAdd[0] = admin1;
        adminsToAdd[1] = admin2;
        adminsToAdd[2] = admin3;
        vm.prank(repoAdmin);
        escrow.addAdmins(REPO_ID, ACCOUNT_ID, adminsToAdd);

        // Remove two of them
        address[] memory adminsToRemove = new address[](2);
        adminsToRemove[0] = admin1;
        adminsToRemove[1] = admin3;

        vm.prank(repoAdmin);
        escrow.removeAdmins(REPO_ID, ACCOUNT_ID, adminsToRemove);

        assertFalse(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, admin1));
        assertTrue(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, admin2)); // Should remain
        assertFalse(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, admin3));
        assertTrue(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, repoAdmin)); // Original should remain
        
        // Should be 2 admins left
        address[] memory allAdmins = escrow.getAllAdmins(REPO_ID, ACCOUNT_ID);
        assertEq(allAdmins.length, 2);
    }

    function test_removeAdmins_revert_cannotRemoveAllAdmins() public {
        // Try to remove the only admin
        address[] memory adminsToRemove = new address[](1);
        adminsToRemove[0] = repoAdmin;

        expectRevert(Errors.CANNOT_REMOVE_ALL_ADMINS);
        vm.prank(repoAdmin);
        escrow.removeAdmins(REPO_ID, ACCOUNT_ID, adminsToRemove);
    }

    function test_removeAdmins_revert_cannotRemoveAllAdminsMultiple() public {
        // Add one more admin
        address[] memory adminsToAdd = new address[](1);
        adminsToAdd[0] = newAdmin;
        vm.prank(repoAdmin);
        escrow.addAdmins(REPO_ID, ACCOUNT_ID, adminsToAdd);

        // Try to remove both admins
        address[] memory adminsToRemove = new address[](2);
        adminsToRemove[0] = repoAdmin;
        adminsToRemove[1] = newAdmin;

        expectRevert(Errors.CANNOT_REMOVE_ALL_ADMINS);
        vm.prank(repoAdmin);
        escrow.removeAdmins(REPO_ID, ACCOUNT_ID, adminsToRemove);
    }

    function test_removeAdmins_nonExistentAdmin() public {
        // Add one admin so we can remove without violating the "at least one admin" rule
        address[] memory adminsToAdd = new address[](1);
        adminsToAdd[0] = newAdmin;
        vm.prank(repoAdmin);
        escrow.addAdmins(REPO_ID, ACCOUNT_ID, adminsToAdd);

        // Try to remove non-existent admin (should not emit event)
        address nonExistent = makeAddr("nonExistent");
        address[] memory adminsToRemove = new address[](1);
        adminsToRemove[0] = nonExistent;

        vm.recordLogs();
        vm.prank(repoAdmin);
        escrow.removeAdmins(REPO_ID, ACCOUNT_ID, adminsToRemove);
        
        // Should not affect existing admins
        assertTrue(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, repoAdmin));
        assertTrue(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, newAdmin));
    }

    function test_removeAdmins_revert_emptyArray() public {
        address[] memory adminsToRemove = new address[](0);

        expectRevert(Errors.INVALID_AMOUNT);
        vm.prank(repoAdmin);
        escrow.removeAdmins(REPO_ID, ACCOUNT_ID, adminsToRemove);
    }

    function test_removeAdmins_revert_notRepoAdmin() public {
        address[] memory adminsToRemove = new address[](1);
        adminsToRemove[0] = repoAdmin;

        expectRevert(Errors.NOT_REPO_ADMIN);
        vm.prank(unauthorized);
        escrow.removeAdmins(REPO_ID, ACCOUNT_ID, adminsToRemove);
    }

    function test_removeAdmins_revert_batchLimitExceeded() public {
        uint256 batchLimit = escrow.batchLimit();
        address[] memory adminsToRemove = new address[](batchLimit + 1);
        
        for (uint i = 0; i < batchLimit + 1; i++) {
            adminsToRemove[i] = makeAddr(string(abi.encodePacked("admin", i)));
        }

        expectRevert(Errors.BATCH_LIMIT_EXCEEDED);
        vm.prank(repoAdmin);
        escrow.removeAdmins(REPO_ID, ACCOUNT_ID, adminsToRemove);
    }
} 