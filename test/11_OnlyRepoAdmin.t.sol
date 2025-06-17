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
        
        // Initialize second repo with a different admin to test isolation
        address[] memory initialAdmins2 = new address[](1);
        initialAdmins2[0] = newAdmin; // Different admin for isolation testing
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
                    escrow.signerNonce(),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            ownerPrivateKey,
            digest
        );
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

        vm.prank(newAdmin); // newAdmin is admin of REPO_ID_2
        escrow.addDistributors(REPO_ID_2, ACCOUNT_ID_2, distributors2);

        // Each distributor should only work for their repo
        assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, distributor1));
        assertFalse(escrow.canDistribute(REPO_ID, ACCOUNT_ID, distributor2));

        assertFalse(escrow.canDistribute(REPO_ID_2, ACCOUNT_ID_2, distributor1));
        assertTrue(escrow.canDistribute(REPO_ID_2, ACCOUNT_ID_2, distributor2));

        // Each admin should work for their respective repo
        assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, repoAdmin));
        assertFalse(escrow.canDistribute(REPO_ID_2, ACCOUNT_ID_2, repoAdmin)); // repoAdmin is not admin of REPO_ID_2
        
        assertFalse(escrow.canDistribute(REPO_ID, ACCOUNT_ID, newAdmin)); // newAdmin is not admin of REPO_ID
        assertTrue(escrow.canDistribute(REPO_ID_2, ACCOUNT_ID_2, newAdmin));
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

    event AddedAdmin(uint256 indexed repoId, uint256 indexed accountId, address oldAdmin, address indexed newAdmin);
    event RemovedAdmin(uint256 indexed repoId, uint256 indexed accountId, address indexed oldAdmin);
    event AddedDistributor(uint256 indexed repoId, uint256 indexed accountId, address indexed distributor);
    event RemovedDistributor(uint256 indexed repoId, uint256 indexed accountId, address indexed distributor);

    /* -------------------------------------------------------------------------- */
    /*                             ADD ADMINS TESTS                               */
    /* -------------------------------------------------------------------------- */

    function test_addAdmins_success() public {
        address testAdmin = makeAddr("testAdmin"); // Use a different admin since newAdmin is already admin of REPO_ID_2
        address[] memory adminsToAdd = new address[](1);
        adminsToAdd[0] = testAdmin;

        assertFalse(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, testAdmin));

        vm.expectEmit(true, true, true, true);
        emit AddedAdmin(REPO_ID, ACCOUNT_ID, address(0), testAdmin);

        vm.prank(repoAdmin);
        escrow.addAdmins(REPO_ID, ACCOUNT_ID, adminsToAdd);

        assertTrue(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, testAdmin));
        assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, testAdmin));
        
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
        emit AddedAdmin(REPO_ID, ACCOUNT_ID, address(0), admin1);
        vm.expectEmit(true, true, true, true);
        emit AddedAdmin(REPO_ID, ACCOUNT_ID, address(0), admin2);
        vm.expectEmit(true, true, true, true);
        emit AddedAdmin(REPO_ID, ACCOUNT_ID, address(0), admin3);

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
        adminsToAdd[1] = makeAddr("anotherAdmin"); // Use a different admin since newAdmin is already admin of REPO_ID_2

        // Only the new admin should emit event since repoAdmin is already an admin
        vm.expectEmit(true, true, true, true);
        emit AddedAdmin(REPO_ID, ACCOUNT_ID, address(0), makeAddr("anotherAdmin"));

        vm.prank(repoAdmin);
        escrow.addAdmins(REPO_ID, ACCOUNT_ID, adminsToAdd);

        assertTrue(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, repoAdmin));
        assertTrue(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, makeAddr("anotherAdmin")));
        
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
        emit RemovedAdmin(REPO_ID, ACCOUNT_ID, repoAdmin);

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

    /* -------------------------------------------------------------------------- */
    /*                            EDGE CASE TESTS                                 */
    /* -------------------------------------------------------------------------- */

    function test_addAdmins_duplicateInSameCall() public {
        address[] memory adminsToAdd = new address[](3);
        adminsToAdd[0] = newAdmin;
        adminsToAdd[1] = makeAddr("admin2");
        adminsToAdd[2] = newAdmin; // Duplicate

        // Should only emit event once for newAdmin
        vm.expectEmit(true, true, true, true);
        emit AddedAdmin(REPO_ID, ACCOUNT_ID, address(0), newAdmin);
        vm.expectEmit(true, true, true, true);
        emit AddedAdmin(REPO_ID, ACCOUNT_ID, address(0), makeAddr("admin2"));

        vm.prank(repoAdmin);
        escrow.addAdmins(REPO_ID, ACCOUNT_ID, adminsToAdd);

        assertTrue(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, newAdmin));
        assertTrue(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, makeAddr("admin2")));
        
        // Should be 3 total admins (original + 2 unique new ones)
        address[] memory allAdmins = escrow.getAllAdmins(REPO_ID, ACCOUNT_ID);
        assertEq(allAdmins.length, 3);
    }

    function test_addDistributors_duplicateInSameCall() public {
        address[] memory distributors = new address[](3);
        distributors[0] = distributor1;
        distributors[1] = distributor2;
        distributors[2] = distributor1; // Duplicate

        vm.prank(repoAdmin);
        escrow.addDistributors(REPO_ID, ACCOUNT_ID, distributors);

        assertTrue(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributor1));
        assertTrue(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributor2));
        
        // Should only have 2 unique distributors
        address[] memory allDistributors = escrow.getAllDistributors(REPO_ID, ACCOUNT_ID);
        assertEq(allDistributors.length, 2);
    }

    function test_removeAdmins_partialRemoval() public {
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

        // Try to remove some existing and some non-existing
        address[] memory adminsToRemove = new address[](3);
        adminsToRemove[0] = admin1; // Exists
        adminsToRemove[1] = makeAddr("nonExistent"); // Doesn't exist
        adminsToRemove[2] = admin3; // Exists

        vm.prank(repoAdmin);
        escrow.removeAdmins(REPO_ID, ACCOUNT_ID, adminsToRemove);

        // Only existing admins should be removed
        assertFalse(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, admin1));
        assertTrue(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, admin2)); // Should remain
        assertFalse(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, admin3));
    }

    function test_removeDistributors_partialRemoval() public {
        // Add multiple distributors
        address[] memory distributors = new address[](3);
        distributors[0] = distributor1;
        distributors[1] = distributor2;
        distributors[2] = distributor3;
        vm.prank(repoAdmin);
        escrow.addDistributors(REPO_ID, ACCOUNT_ID, distributors);

        // Try to remove some existing and some non-existing
        address[] memory toRemove = new address[](3);
        toRemove[0] = distributor1; // Exists
        toRemove[1] = makeAddr("nonExistent"); // Doesn't exist
        toRemove[2] = distributor3; // Exists

        vm.prank(repoAdmin);
        escrow.removeDistributors(REPO_ID, ACCOUNT_ID, toRemove);

        // Only existing distributors should be removed
        assertFalse(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributor1));
        assertTrue(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributor2)); // Should remain
        assertFalse(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributor3));
    }

    function test_adminManagement_nonExistentRepo() public {
        uint256 nonExistentRepoId = 999;
        uint256 nonExistentAccountId = 999;
        
        address[] memory adminsToAdd = new address[](1);
        adminsToAdd[0] = newAdmin;

        // Should revert because caller is not admin of non-existent repo
        expectRevert(Errors.NOT_REPO_ADMIN);
        vm.prank(repoAdmin);
        escrow.addAdmins(nonExistentRepoId, nonExistentAccountId, adminsToAdd);
    }

    function test_distributorManagement_nonExistentRepo() public {
        uint256 nonExistentRepoId = 999;
        uint256 nonExistentAccountId = 999;
        
        address[] memory distributors = new address[](1);
        distributors[0] = distributor1;

        // Should revert because caller is not admin of non-existent repo
        expectRevert(Errors.NOT_REPO_ADMIN);
        vm.prank(repoAdmin);
        escrow.addDistributors(nonExistentRepoId, nonExistentAccountId, distributors);
    }

    function test_adminManagement_crossRepoIsolation() public {
        // Admin of REPO_ID should not be able to manage REPO_ID_2 unless explicitly added
        address[] memory adminsToAdd = new address[](1);
        adminsToAdd[0] = newAdmin;

        // This should fail because repoAdmin is not admin of REPO_ID_2
        expectRevert(Errors.NOT_REPO_ADMIN);
        vm.prank(repoAdmin);
        escrow.addAdmins(REPO_ID_2, ACCOUNT_ID_2, adminsToAdd);

        // But should work for REPO_ID
        vm.prank(repoAdmin);
        escrow.addAdmins(REPO_ID, ACCOUNT_ID, adminsToAdd);
        assertTrue(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, newAdmin));
    }

    function test_distributorManagement_crossRepoIsolation() public {
        // Admin of REPO_ID should not be able to manage distributors of REPO_ID_2
        address[] memory distributors = new address[](1);
        distributors[0] = distributor1;

        // This should fail because repoAdmin is not admin of REPO_ID_2
        expectRevert(Errors.NOT_REPO_ADMIN);
        vm.prank(repoAdmin);
        escrow.addDistributors(REPO_ID_2, ACCOUNT_ID_2, distributors);

        // But should work for REPO_ID
        vm.prank(repoAdmin);
        escrow.addDistributors(REPO_ID, ACCOUNT_ID, distributors);
        assertTrue(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributor1));
    }

    function test_adminManagement_emptyArrays() public {
        address[] memory emptyArray = new address[](0);

        expectRevert(Errors.INVALID_AMOUNT);
        vm.prank(repoAdmin);
        escrow.addAdmins(REPO_ID, ACCOUNT_ID, emptyArray);

        expectRevert(Errors.INVALID_AMOUNT);
        vm.prank(repoAdmin);
        escrow.removeAdmins(REPO_ID, ACCOUNT_ID, emptyArray);
    }

    function test_distributorManagement_emptyArrays() public {
        address[] memory emptyArray = new address[](0);

        // addDistributors allows empty arrays (no-op)
        vm.prank(repoAdmin);
        escrow.addDistributors(REPO_ID, ACCOUNT_ID, emptyArray);

        // removeDistributors allows empty arrays (no-op)
        vm.prank(repoAdmin);
        escrow.removeDistributors(REPO_ID, ACCOUNT_ID, emptyArray);
    }

    function test_adminManagement_maxBatchSize() public {
        uint256 batchLimit = escrow.batchLimit();
        address[] memory adminsToAdd = new address[](batchLimit);
        
        for (uint i = 0; i < batchLimit; i++) {
            adminsToAdd[i] = makeAddr(string(abi.encodePacked("batchAdmin", i)));
        }

        vm.prank(repoAdmin);
        escrow.addAdmins(REPO_ID, ACCOUNT_ID, adminsToAdd);

        // All should be added
        for (uint i = 0; i < batchLimit; i++) {
            assertTrue(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, adminsToAdd[i]));
        }

        // Total should be original + batch limit
        address[] memory allAdmins = escrow.getAllAdmins(REPO_ID, ACCOUNT_ID);
        assertEq(allAdmins.length, 1 + batchLimit);
    }

    function test_distributorManagement_maxBatchSize() public {
        uint256 batchLimit = escrow.batchLimit();
        address[] memory distributors = new address[](batchLimit);
        
        for (uint i = 0; i < batchLimit; i++) {
            distributors[i] = makeAddr(string(abi.encodePacked("batchDistributor", i)));
        }

        vm.prank(repoAdmin);
        escrow.addDistributors(REPO_ID, ACCOUNT_ID, distributors);

        // All should be added
        for (uint i = 0; i < batchLimit; i++) {
            assertTrue(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributors[i]));
        }

        address[] memory allDistributors = escrow.getAllDistributors(REPO_ID, ACCOUNT_ID);
        assertEq(allDistributors.length, batchLimit);
    }

    function test_adminManagement_gasOptimization() public {
        // Test gas usage for different batch sizes
        address[] memory singleAdmin = new address[](1);
        singleAdmin[0] = makeAddr("singleAdmin");

        address[] memory multipleAdmins = new address[](5);
        for (uint i = 0; i < 5; i++) {
            multipleAdmins[i] = makeAddr(string(abi.encodePacked("multiAdmin", i)));
        }

        // Single admin addition
        uint256 gasBefore = gasleft();
        vm.prank(repoAdmin);
        escrow.addAdmins(REPO_ID, ACCOUNT_ID, singleAdmin);
        uint256 gasUsedSingle = gasBefore - gasleft();

        // Multiple admin addition
        gasBefore = gasleft();
        vm.prank(repoAdmin);
        escrow.addAdmins(REPO_ID, ACCOUNT_ID, multipleAdmins);
        uint256 gasUsedMultiple = gasBefore - gasleft();

        // Multiple should be more efficient per admin than individual calls
        assertTrue(gasUsedMultiple < gasUsedSingle * 5);
    }

    function test_distributorManagement_gasOptimization() public {
        // Test gas usage for different batch sizes
        address[] memory singleDistributor = new address[](1);
        singleDistributor[0] = makeAddr("singleDistributor");

        address[] memory multipleDistributors = new address[](5);
        for (uint i = 0; i < 5; i++) {
            multipleDistributors[i] = makeAddr(string(abi.encodePacked("multiDistributor", i)));
        }

        // Single distributor addition
        uint256 gasBefore = gasleft();
        vm.prank(repoAdmin);
        escrow.addDistributors(REPO_ID, ACCOUNT_ID, singleDistributor);
        uint256 gasUsedSingle = gasBefore - gasleft();

        // Multiple distributor addition
        gasBefore = gasleft();
        vm.prank(repoAdmin);
        escrow.addDistributors(REPO_ID, ACCOUNT_ID, multipleDistributors);
        uint256 gasUsedMultiple = gasBefore - gasleft();

        // Multiple should be more efficient per distributor than individual calls
        assertTrue(gasUsedMultiple < gasUsedSingle * 5);
    }

    function test_adminAndDistributorInteraction() public {
        // Test that admin and distributor roles work together correctly
        
        // Add distributor
        address[] memory distributors = new address[](1);
        distributors[0] = distributor1;
        vm.prank(repoAdmin);
        escrow.addDistributors(REPO_ID, ACCOUNT_ID, distributors);

        // Add new admin
        address[] memory adminsToAdd = new address[](1);
        adminsToAdd[0] = newAdmin;
        vm.prank(repoAdmin);
        escrow.addAdmins(REPO_ID, ACCOUNT_ID, adminsToAdd);

        // New admin should be able to manage distributors
        address[] memory moreDistributors = new address[](1);
        moreDistributors[0] = distributor2;
        vm.prank(newAdmin);
        escrow.addDistributors(REPO_ID, ACCOUNT_ID, moreDistributors);

        // Both distributors should be authorized
        assertTrue(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributor1));
        assertTrue(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributor2));

        // Both admins should be able to distribute
        assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, repoAdmin));
        assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, newAdmin));

        // Distributors should be able to distribute but not manage other distributors
        assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, distributor1));
        assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, distributor2));
    }

    function test_adminRemoval_lastAdminProtection() public {
        // Add multiple admins
        address admin1 = makeAddr("admin1");
        address admin2 = makeAddr("admin2");
        
        address[] memory adminsToAdd = new address[](2);
        adminsToAdd[0] = admin1;
        adminsToAdd[1] = admin2;
        vm.prank(repoAdmin);
        escrow.addAdmins(REPO_ID, ACCOUNT_ID, adminsToAdd);

        // Now we have 3 admins total (repoAdmin + admin1 + admin2)
        address[] memory allAdmins = escrow.getAllAdmins(REPO_ID, ACCOUNT_ID);
        assertEq(allAdmins.length, 3);

        // Should be able to remove 2 admins (leaving 1)
        address[] memory adminsToRemove = new address[](2);
        adminsToRemove[0] = admin1;
        adminsToRemove[1] = admin2;
        vm.prank(repoAdmin);
        escrow.removeAdmins(REPO_ID, ACCOUNT_ID, adminsToRemove);

        // Should have 1 admin left
        allAdmins = escrow.getAllAdmins(REPO_ID, ACCOUNT_ID);
        assertEq(allAdmins.length, 1);
        assertEq(allAdmins[0], repoAdmin);

        // Now trying to remove the last admin should fail
        address[] memory lastAdmin = new address[](1);
        lastAdmin[0] = repoAdmin;
        expectRevert(Errors.CANNOT_REMOVE_ALL_ADMINS);
        vm.prank(repoAdmin);
        escrow.removeAdmins(REPO_ID, ACCOUNT_ID, lastAdmin);
    }

    function test_adminRemoval_exactCountProtection() public {
        // Test the exact boundary condition for admin removal protection
        
        // Add exactly one more admin
        address[] memory adminsToAdd = new address[](1);
        adminsToAdd[0] = newAdmin;
        vm.prank(repoAdmin);
        escrow.addAdmins(REPO_ID, ACCOUNT_ID, adminsToAdd);

        // Now we have exactly 2 admins
        address[] memory allAdmins = escrow.getAllAdmins(REPO_ID, ACCOUNT_ID);
        assertEq(allAdmins.length, 2);

        // Should be able to remove 1 admin (leaving 1)
        address[] memory adminsToRemove = new address[](1);
        adminsToRemove[0] = repoAdmin;
        vm.prank(newAdmin);
        escrow.removeAdmins(REPO_ID, ACCOUNT_ID, adminsToRemove);

        // Should have 1 admin left
        allAdmins = escrow.getAllAdmins(REPO_ID, ACCOUNT_ID);
        assertEq(allAdmins.length, 1);
        assertEq(allAdmins[0], newAdmin);

        // Now trying to remove the last admin should fail
        address[] memory lastAdmin = new address[](1);
        lastAdmin[0] = newAdmin;
        expectRevert(Errors.CANNOT_REMOVE_ALL_ADMINS);
        vm.prank(newAdmin);
        escrow.removeAdmins(REPO_ID, ACCOUNT_ID, lastAdmin);
    }

    /* -------------------------------------------------------------------------- */
    /*                                FUZZ TESTS                                  */
    /* -------------------------------------------------------------------------- */

    function test_addAdmins_fuzz_batchSizes(uint8 numAdmins) public {
        vm.assume(numAdmins > 0 && numAdmins <= 50); // Reasonable limit
        
        address[] memory adminsToAdd = new address[](numAdmins);
        for (uint i = 0; i < numAdmins; i++) {
            adminsToAdd[i] = makeAddr(string(abi.encodePacked("fuzzAdmin", i)));
        }
        
        vm.prank(repoAdmin);
        escrow.addAdmins(REPO_ID, ACCOUNT_ID, adminsToAdd);
        
        // Verify all admins were added
        for (uint i = 0; i < numAdmins; i++) {
            assertTrue(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, adminsToAdd[i]));
        }
        
        // Total should be original + new admins
        address[] memory allAdmins = escrow.getAllAdmins(REPO_ID, ACCOUNT_ID);
        assertEq(allAdmins.length, 1 + numAdmins);
    }

    function test_addDistributors_fuzz_batchSizes(uint8 numDistributors) public {
        vm.assume(numDistributors > 0 && numDistributors <= 50); // Reasonable limit
        
        address[] memory distributorsToAdd = new address[](numDistributors);
        for (uint i = 0; i < numDistributors; i++) {
            distributorsToAdd[i] = makeAddr(string(abi.encodePacked("fuzzDistributor", i)));
        }
        
        vm.prank(repoAdmin);
        escrow.addDistributors(REPO_ID, ACCOUNT_ID, distributorsToAdd);
        
        // Verify all distributors were added
        for (uint i = 0; i < numDistributors; i++) {
            assertTrue(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributorsToAdd[i]));
        }
        
        address[] memory allDistributors = escrow.getAllDistributors(REPO_ID, ACCOUNT_ID);
        assertEq(allDistributors.length, numDistributors);
    }

    function test_removeAdmins_fuzz_partialRemoval(uint8 numAdmins, uint8 numToRemove) public {
        vm.assume(numAdmins > 1 && numAdmins <= 20); // Need at least 2 to avoid "cannot remove all" error
        vm.assume(numToRemove > 0 && numToRemove < numAdmins); // Remove some but not all
        
        // Add admins
        address[] memory adminsToAdd = new address[](numAdmins);
        for (uint i = 0; i < numAdmins; i++) {
            adminsToAdd[i] = makeAddr(string(abi.encodePacked("fuzzAdmin", i)));
        }
        vm.prank(repoAdmin);
        escrow.addAdmins(REPO_ID, ACCOUNT_ID, adminsToAdd);
        
        // Remove some admins
        address[] memory adminsToRemove = new address[](numToRemove);
        for (uint i = 0; i < numToRemove; i++) {
            adminsToRemove[i] = adminsToAdd[i];
        }
        vm.prank(repoAdmin);
        escrow.removeAdmins(REPO_ID, ACCOUNT_ID, adminsToRemove);
        
        // Verify removed admins are no longer authorized
        for (uint i = 0; i < numToRemove; i++) {
            assertFalse(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, adminsToRemove[i]));
        }
        
        // Verify remaining admins are still authorized
        for (uint i = numToRemove; i < numAdmins; i++) {
            assertTrue(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, adminsToAdd[i]));
        }
        
        // Original admin should still be there
        assertTrue(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, repoAdmin));
        
        // Total count should be correct
        address[] memory allAdmins = escrow.getAllAdmins(REPO_ID, ACCOUNT_ID);
        assertEq(allAdmins.length, 1 + numAdmins - numToRemove);
    }

    function test_removeDistributors_fuzz_partialRemoval(uint8 numDistributors, uint8 numToRemove) public {
        vm.assume(numDistributors > 0 && numDistributors <= 20);
        vm.assume(numToRemove > 0 && numToRemove <= numDistributors);
        
        // Add distributors
        address[] memory distributorsToAdd = new address[](numDistributors);
        for (uint i = 0; i < numDistributors; i++) {
            distributorsToAdd[i] = makeAddr(string(abi.encodePacked("fuzzDistributor", i)));
        }
        vm.prank(repoAdmin);
        escrow.addDistributors(REPO_ID, ACCOUNT_ID, distributorsToAdd);
        
        // Remove some distributors
        address[] memory distributorsToRemove = new address[](numToRemove);
        for (uint i = 0; i < numToRemove; i++) {
            distributorsToRemove[i] = distributorsToAdd[i];
        }
        vm.prank(repoAdmin);
        escrow.removeDistributors(REPO_ID, ACCOUNT_ID, distributorsToRemove);
        
        // Verify removed distributors are no longer authorized
        for (uint i = 0; i < numToRemove; i++) {
            assertFalse(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributorsToRemove[i]));
        }
        
        // Verify remaining distributors are still authorized
        for (uint i = numToRemove; i < numDistributors; i++) {
            assertTrue(escrow.getIsAuthorizedDistributor(REPO_ID, ACCOUNT_ID, distributorsToAdd[i]));
        }
        
        // Total count should be correct
        address[] memory allDistributors = escrow.getAllDistributors(REPO_ID, ACCOUNT_ID);
        assertEq(allDistributors.length, numDistributors - numToRemove);
    }

    function test_adminManagement_fuzz_crossRepo(uint256 repoId, uint256 accountId, uint8 numAdmins) public {
        vm.assume(repoId != REPO_ID || accountId != ACCOUNT_ID); // Different from setup repo
        vm.assume(repoId <= type(uint128).max && accountId <= type(uint128).max);
        vm.assume(numAdmins > 0 && numAdmins <= 10);
        
        address initialAdmin = makeAddr("initialAdmin");
        
        // Initialize new repo
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    repoId,
                    accountId,
                    keccak256(abi.encode(_singleAddressArray(initialAdmin))),
                    escrow.signerNonce(),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        escrow.initRepo(repoId, accountId, _singleAddressArray(initialAdmin), deadline, v, r, s);
        
        // Add admins to new repo
        address[] memory adminsToAdd = new address[](numAdmins);
        for (uint i = 0; i < numAdmins; i++) {
            adminsToAdd[i] = makeAddr(string(abi.encodePacked("crossRepoAdmin", i)));
        }
        
        vm.prank(initialAdmin);
        escrow.addAdmins(repoId, accountId, adminsToAdd);
        
        // Verify admins were added to the correct repo
        for (uint i = 0; i < numAdmins; i++) {
            assertTrue(escrow.getIsAuthorizedAdmin(repoId, accountId, adminsToAdd[i]));
            // Should NOT be admin of original repo
            assertFalse(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, adminsToAdd[i]));
        }
        
        // Original repo admin should NOT be admin of new repo
        assertFalse(escrow.getIsAuthorizedAdmin(repoId, accountId, repoAdmin));
    }

    function test_distributorManagement_fuzz_lifecycle(uint8 addCount, uint8 removeCount) public {
        vm.assume(addCount > 0 && addCount <= 15);
        vm.assume(removeCount > 0 && removeCount <= addCount);
        
        // Add distributors
        address[] memory distributorsToAdd = new address[](addCount);
        for (uint i = 0; i < addCount; i++) {
            distributorsToAdd[i] = makeAddr(string(abi.encodePacked("lifecycleDistributor", i)));
        }
        vm.prank(repoAdmin);
        escrow.addDistributors(REPO_ID, ACCOUNT_ID, distributorsToAdd);
        
        // Verify all were added
        assertEq(escrow.getAllDistributors(REPO_ID, ACCOUNT_ID).length, addCount);
        
        // Remove some distributors
        address[] memory distributorsToRemove = new address[](removeCount);
        for (uint i = 0; i < removeCount; i++) {
            distributorsToRemove[i] = distributorsToAdd[i];
        }
        vm.prank(repoAdmin);
        escrow.removeDistributors(REPO_ID, ACCOUNT_ID, distributorsToRemove);
        
        // Verify final count
        assertEq(escrow.getAllDistributors(REPO_ID, ACCOUNT_ID).length, addCount - removeCount);
        
        // Verify can distribute status
        for (uint i = 0; i < removeCount; i++) {
            assertFalse(escrow.canDistribute(REPO_ID, ACCOUNT_ID, distributorsToRemove[i]));
        }
        for (uint i = removeCount; i < addCount; i++) {
            assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, distributorsToAdd[i]));
        }
        
        // Admin should still be able to distribute
        assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, repoAdmin));
    }

    function _singleAddressArray(address addr) internal pure returns (address[] memory) {
        address[] memory arr = new address[](1);
        arr[0] = addr;
        return arr;
    }
} 