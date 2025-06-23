// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "./00_Escrow.t.sol";

contract InitRepo_Test is Base_Test {
    
    uint256 constant REPO_ID = 1;
    uint256 constant ACCOUNT_ID = 100;

    address repoAdmin;

    uint256 adminPrivateKey = 0x1111111111111111111111111111111111111111111111111111111111111111;
    
    function setUp() public override {
        super.setUp();
        
        repoAdmin = vm.addr(adminPrivateKey);
    }

    /* -------------------------------------------------------------------------- */
    /*                               INIT REPO TESTS                             */
    /* -------------------------------------------------------------------------- */

    function test_initRepo_success() public {
        address[] memory admins = new address[](1);
        admins[0] = repoAdmin;
        
        uint256 signatureDeadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    REPO_ID,
                    ACCOUNT_ID,
                    keccak256(abi.encode(admins)),
                    escrow.getRepoSetAdminNonce(REPO_ID, ACCOUNT_ID),
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        vm.expectEmit(true, true, true, true);
        emit AddedAdmin(REPO_ID, ACCOUNT_ID, address(0), repoAdmin);
        vm.expectEmit(true, true, false, true);
        emit InitializedRepo(REPO_ID, ACCOUNT_ID, admins);

        escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, signatureDeadline, v, r, s);

        // Verify admin was set
        address[] memory retrievedAdmins = escrow.getAllAdmins(REPO_ID, ACCOUNT_ID);
        assertEq(retrievedAdmins.length, 1);
        assertEq(retrievedAdmins[0], repoAdmin);
        assertTrue(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, repoAdmin));
        
        // Verify nonce was incremented
        assertEq(escrow.getRepoSetAdminNonce(REPO_ID, ACCOUNT_ID), 1);
    }

    function test_initRepo_multipleAdmins() public {
        address admin1 = makeAddr("admin1");
        address admin2 = makeAddr("admin2");
        address admin3 = makeAddr("admin3");
        
        address[] memory admins = new address[](3);
        admins[0] = admin1;
        admins[1] = admin2;
        admins[2] = admin3;
        
        uint256 signatureDeadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    REPO_ID,
                    ACCOUNT_ID,
                    keccak256(abi.encode(admins)),
                    escrow.getRepoSetAdminNonce(REPO_ID, ACCOUNT_ID),
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        // Expect events for all admins
        vm.expectEmit(true, true, true, true);
        emit AddedAdmin(REPO_ID, ACCOUNT_ID, address(0), admin1);
        vm.expectEmit(true, true, true, true);
        emit AddedAdmin(REPO_ID, ACCOUNT_ID, address(0), admin2);
        vm.expectEmit(true, true, true, true);
        emit AddedAdmin(REPO_ID, ACCOUNT_ID, address(0), admin3);
        vm.expectEmit(true, true, false, true);
        emit InitializedRepo(REPO_ID, ACCOUNT_ID, admins);

        escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, signatureDeadline, v, r, s);

        // Verify all admins were set
        address[] memory retrievedAdmins = escrow.getAllAdmins(REPO_ID, ACCOUNT_ID);
        assertEq(retrievedAdmins.length, 3);
        
        // Check each admin is authorized
        assertTrue(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, admin1));
        assertTrue(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, admin2));
        assertTrue(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, admin3));
        
        // Check canDistribute works for all admins
        assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, admin1));
        assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, admin2));
        assertTrue(escrow.canDistribute(REPO_ID, ACCOUNT_ID, admin3));
    }

    function test_initRepo_revert_alreadyInitialized() public {
        // First initialization
        address[] memory admins = new address[](1);
        admins[0] = repoAdmin;
        _initializeRepo(REPO_ID, ACCOUNT_ID, admins);

        // Try to initialize again
        uint256 signatureDeadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    REPO_ID,
                    ACCOUNT_ID,
                    keccak256(abi.encode(admins)),
                    escrow.getRepoSetAdminNonce(REPO_ID, ACCOUNT_ID),
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        expectRevert(Errors.REPO_ALREADY_INITIALIZED);
        escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, signatureDeadline, v, r, s);
    }

    function test_initRepo_revert_emptyAdminsArray() public {
        address[] memory admins = new address[](0); // Empty array
        
        uint256 signatureDeadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    REPO_ID,
                    ACCOUNT_ID,
                    keccak256(abi.encode(admins)),
                    escrow.getRepoSetAdminNonce(REPO_ID, ACCOUNT_ID),
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        expectRevert(Errors.INVALID_AMOUNT);
        escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, signatureDeadline, v, r, s);
    }

    function test_initRepo_revert_invalidAddress() public {
        address[] memory admins = new address[](2);
        admins[0] = repoAdmin;
        admins[1] = address(0); // Invalid address
        
        uint256 signatureDeadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    REPO_ID,
                    ACCOUNT_ID,
                    keccak256(abi.encode(admins)),
                    escrow.getRepoSetAdminNonce(REPO_ID, ACCOUNT_ID),
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        expectRevert(Errors.INVALID_ADDRESS);
        escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, signatureDeadline, v, r, s);
    }

    function test_initRepo_revert_expiredSignature() public {
        address[] memory admins = new address[](1);
        admins[0] = repoAdmin;
        
        uint256 signatureDeadline = block.timestamp - 1; // Expired deadline
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    REPO_ID,
                    ACCOUNT_ID,
                    keccak256(abi.encode(admins)),
                    escrow.getRepoSetAdminNonce(REPO_ID, ACCOUNT_ID),
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        expectRevert(Errors.SIGNATURE_EXPIRED);
        escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, signatureDeadline, v, r, s);
    }

    function test_initRepo_revert_invalidSignature() public {
        address[] memory admins = new address[](1);
        admins[0] = repoAdmin;
        
        uint256 signatureDeadline = block.timestamp + 1 hours;
        uint256 wrongPrivateKey = 0x2222222222222222222222222222222222222222222222222222222222222222;
        
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    REPO_ID,
                    ACCOUNT_ID,
                    keccak256(abi.encode(admins)),
                    escrow.getRepoSetAdminNonce(REPO_ID, ACCOUNT_ID),
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, digest);

        expectRevert(Errors.INVALID_SIGNATURE);
        escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, signatureDeadline, v, r, s);
    }

    function test_initRepo_differentReposAndAccounts() public {
        address admin1 = makeAddr("admin1");
        address admin2 = makeAddr("admin2");
        address admin3 = makeAddr("admin3");

        address[] memory admins1 = new address[](1);
        admins1[0] = admin1;
        address[] memory admins2 = new address[](1);
        admins2[0] = admin2;
        address[] memory admins3 = new address[](1);
        admins3[0] = admin3;

        // Initialize different repo/account combinations
        _initializeRepo(1, 100, admins1);
        _initializeRepo(1, 200, admins2);  // Same repo, different account
        _initializeRepo(2, 100, admins3);  // Different repo, same account

        // Verify all admins were set correctly
        assertTrue(escrow.getIsAuthorizedAdmin(1, 100, admin1));
        assertTrue(escrow.getIsAuthorizedAdmin(1, 200, admin2));
        assertTrue(escrow.getIsAuthorizedAdmin(2, 100, admin3));
    }

    function test_initRepo_fuzz_repoAndAccountIds(uint256 repoId, uint256 accountId) public {
        vm.assume(repoId != 0 && accountId != 0); // Avoid potential edge cases
        vm.assume(repoId < type(uint128).max && accountId < type(uint128).max); // Reasonable bounds
        
        address admin = makeAddr("fuzzAdmin");
        address[] memory admins = new address[](1);
        admins[0] = admin;
        
        _initializeRepo(repoId, accountId, admins);
        
        assertTrue(escrow.getIsAuthorizedAdmin(repoId, accountId, admin));
    }

    function test_initRepo_nonceIncrement() public {
        address admin1 = makeAddr("admin1");
        address admin2 = makeAddr("admin2");
        
        address[] memory admins1 = new address[](1);
        admins1[0] = admin1;
        address[] memory admins2 = new address[](1);
        admins2[0] = admin2;
        
        // With per-repo nonces, each repo/instance pair has its own nonce counter
        uint256 initialNonce1100 = escrow.getRepoSetAdminNonce(1, 100);
        uint256 initialNonce2200 = escrow.getRepoSetAdminNonce(2, 200);
        
        _initializeRepo(1, 100, admins1);
        assertEq(escrow.getRepoSetAdminNonce(1, 100), initialNonce1100 + 1);
        
        _initializeRepo(2, 200, admins2);
        assertEq(escrow.getRepoSetAdminNonce(2, 200), initialNonce2200 + 1);
    }

    function test_initRepo_domainSeparator() public {
        // Test that the domain separator is properly used in signature verification
        address[] memory admins = new address[](1);
        admins[0] = repoAdmin;
        
        uint256 signatureDeadline = block.timestamp + 1 hours;
        
        // Create digest with correct domain separator
        bytes32 correctDigest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    REPO_ID,
                    ACCOUNT_ID,
                    keccak256(abi.encode(admins)),
                    escrow.getRepoSetAdminNonce(REPO_ID, ACCOUNT_ID),
                    signatureDeadline
                ))
            )
        );
        
        // Create digest with wrong domain separator
        bytes32 wrongDomainSeparator = keccak256("wrong domain");
        bytes32 wrongDigest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                wrongDomainSeparator,
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    REPO_ID,
                    ACCOUNT_ID,
                    keccak256(abi.encode(admins)),
                    escrow.getRepoSetAdminNonce(REPO_ID, ACCOUNT_ID),
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, correctDigest);
        (uint8 vWrong, bytes32 rWrong, bytes32 sWrong) = vm.sign(ownerPrivateKey, wrongDigest);
        
        // Correct signature should work
        escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, signatureDeadline, v, r, s);
        
        address[] memory admins2 = new address[](1);
        admins2[0] = repoAdmin;
        
        // Wrong signature should fail
        expectRevert(Errors.INVALID_SIGNATURE);
        escrow.initRepo(2, 200, admins2, signatureDeadline, vWrong, rWrong, sWrong);
    }

    function test_initRepo_zeroRepoAndAccountIds() public {
        address admin = makeAddr("zeroAdmin");
        
        address[] memory admins = new address[](1);
        admins[0] = admin;
        
        // Test that repo ID and account ID of 0 are allowed
        _initializeRepo(0, 0, admins);
        assertTrue(escrow.getIsAuthorizedAdmin(0, 0, admin));
        
        _initializeRepo(0, 1, admins);
        assertTrue(escrow.getIsAuthorizedAdmin(0, 1, admin));
        
        _initializeRepo(1, 0, admins);
        assertTrue(escrow.getIsAuthorizedAdmin(1, 0, admin));
    }

    function test_initRepo_maxValues() public {
        address admin = makeAddr("maxAdmin");
        uint256 maxUint = type(uint256).max;
        
        address[] memory admins = new address[](1);
        admins[0] = admin;
        
        // Test with maximum uint256 values
        _initializeRepo(maxUint, maxUint, admins);
        assertTrue(escrow.getIsAuthorizedAdmin(maxUint, maxUint, admin));
    }

    function test_initRepo_revert_batchLimitExceeded() public {
        uint256 batchLimit = escrow.batchLimit();
        address[] memory admins = new address[](batchLimit + 1);
        
        // Fill array with valid addresses
        for (uint i = 0; i < batchLimit + 1; i++) {
            admins[i] = address(uint160(i + 1));
        }
        
        uint256 signatureDeadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    REPO_ID,
                    ACCOUNT_ID,
                    keccak256(abi.encode(admins)),
                    escrow.getRepoSetAdminNonce(REPO_ID, ACCOUNT_ID),
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        expectRevert(Errors.BATCH_LIMIT_EXCEEDED);
        escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, signatureDeadline, v, r, s);
    }

    function test_initRepo_duplicateAdmins() public {
        address admin1 = makeAddr("admin1");
        
        address[] memory admins = new address[](3);
        admins[0] = admin1;
        admins[1] = admin1; // Duplicate
        admins[2] = admin1; // Another duplicate
        
        uint256 signatureDeadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    REPO_ID,
                    ACCOUNT_ID,
                    keccak256(abi.encode(admins)),
                    escrow.getRepoSetAdminNonce(REPO_ID, ACCOUNT_ID),
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        // Only one event should be emitted since EnumerableSet handles duplicates
        vm.expectEmit(true, true, true, true);
        emit AddedAdmin(REPO_ID, ACCOUNT_ID, address(0), admin1);
        vm.expectEmit(true, true, false, true);
        emit InitializedRepo(REPO_ID, ACCOUNT_ID, admins);

        escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, signatureDeadline, v, r, s);

        // Verify only one admin is in the set despite duplicates
        address[] memory retrievedAdmins = escrow.getAllAdmins(REPO_ID, ACCOUNT_ID);
        assertEq(retrievedAdmins.length, 1);
        assertEq(retrievedAdmins[0], admin1);
        assertTrue(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, admin1));
    }

    /* -------------------------------------------------------------------------- */
    /*                        SIGNATURE VALIDATION EDGE CASES                     */
    /* -------------------------------------------------------------------------- */

    function test_initRepo_signature_wrongNonce() public {
        address[] memory admins = new address[](1);
        admins[0] = repoAdmin;
        
        uint256 signatureDeadline = block.timestamp + 1 hours;
        
        // Create signature with wrong nonce
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    REPO_ID,
                    ACCOUNT_ID,
                    keccak256(abi.encode(admins)),
                    escrow.getRepoSetAdminNonce(REPO_ID, ACCOUNT_ID) + 1, // Wrong nonce
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        expectRevert(Errors.INVALID_SIGNATURE);
        escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, signatureDeadline, v, r, s);
    }

    function test_initRepo_signature_wrongRepoId() public {
        address[] memory admins = new address[](1);
        admins[0] = repoAdmin;
        
        uint256 signatureDeadline = block.timestamp + 1 hours;
        
        // Create signature with wrong repo ID
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    REPO_ID + 1, // Wrong repo ID
                    ACCOUNT_ID,
                    keccak256(abi.encode(admins)),
                    escrow.getRepoSetAdminNonce(REPO_ID, ACCOUNT_ID),
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        expectRevert(Errors.INVALID_SIGNATURE);
        escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, signatureDeadline, v, r, s);
    }

    function test_initRepo_signature_wrongAccountId() public {
        address[] memory admins = new address[](1);
        admins[0] = repoAdmin;
        
        uint256 signatureDeadline = block.timestamp + 1 hours;
        
        // Create signature with wrong account ID
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    REPO_ID,
                    ACCOUNT_ID + 1, // Wrong account ID
                    keccak256(abi.encode(admins)),
                    escrow.getRepoSetAdminNonce(REPO_ID, ACCOUNT_ID),
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        expectRevert(Errors.INVALID_SIGNATURE);
        escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, signatureDeadline, v, r, s);
    }

    function test_initRepo_signature_wrongAdmins() public {
        address[] memory admins = new address[](1);
        admins[0] = repoAdmin;
        
        address[] memory wrongAdmins = new address[](1);
        wrongAdmins[0] = makeAddr("wrongAdmin");
        
        uint256 signatureDeadline = block.timestamp + 1 hours;
        
        // Create signature with wrong admins array
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    REPO_ID,
                    ACCOUNT_ID,
                    keccak256(abi.encode(wrongAdmins)), // Wrong admins
                    escrow.getRepoSetAdminNonce(REPO_ID, ACCOUNT_ID),
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        expectRevert(Errors.INVALID_SIGNATURE);
        escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, signatureDeadline, v, r, s);
    }

    function test_initRepo_signature_wrongDeadline() public {
        address[] memory admins = new address[](1);
        admins[0] = repoAdmin;
        
        uint256 signatureDeadline = block.timestamp + 1 hours;
        uint256 wrongDeadline = signatureDeadline + 1 hours;
        
        // Create signature with wrong deadline
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    REPO_ID,
                    ACCOUNT_ID,
                    keccak256(abi.encode(admins)),
                    escrow.getRepoSetAdminNonce(REPO_ID, ACCOUNT_ID),
                    wrongDeadline // Wrong deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        expectRevert(Errors.INVALID_SIGNATURE);
        escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, signatureDeadline, v, r, s);
    }

    function test_initRepo_signature_wrongTypehash() public {
        address[] memory admins = new address[](1);
        admins[0] = repoAdmin;
        
        uint256 signatureDeadline = block.timestamp + 1 hours;
        bytes32 wrongTypehash = keccak256("WrongTypehash(uint repoId,uint accountId,address[] admins,uint nonce,uint deadline)");
        
        // Create signature with wrong typehash
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    wrongTypehash, // Wrong typehash
                    REPO_ID,
                    ACCOUNT_ID,
                    keccak256(abi.encode(admins)),
                    escrow.getRepoSetAdminNonce(REPO_ID, ACCOUNT_ID),
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        expectRevert(Errors.INVALID_SIGNATURE);
        escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, signatureDeadline, v, r, s);
    }

    function test_initRepo_signature_malformedSignature() public {
        address[] memory admins = new address[](1);
        admins[0] = repoAdmin;
        
        uint256 signatureDeadline = block.timestamp + 1 hours;
        
        // Use malformed signature components
        uint8 v = 27;
        bytes32 r = bytes32(0);
        bytes32 s = bytes32(0);

        vm.expectRevert(); // Expect any revert, not specific error message
        escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, signatureDeadline, v, r, s);
    }

    function test_initRepo_signature_invalidRecoveryId() public {
        address[] memory admins = new address[](1);
        admins[0] = repoAdmin;
        
        uint256 signatureDeadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    REPO_ID,
                    ACCOUNT_ID,
                    keccak256(abi.encode(admins)),
                    escrow.getRepoSetAdminNonce(REPO_ID, ACCOUNT_ID),
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        
        // Modify v to invalid value
        uint8 invalidV = v == 27 ? 26 : 29; // Invalid recovery ID

        vm.expectRevert(); // Expect any revert, not specific error message
        escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, signatureDeadline, invalidV, r, s);
    }

    function test_initRepo_signature_replayAttack() public {
        address[] memory admins1 = new address[](1);
        admins1[0] = makeAddr("admin1");
        
        address[] memory admins2 = new address[](1);
        admins2[0] = makeAddr("admin2");
        
        uint256 signatureDeadline = block.timestamp + 1 hours;
        
        // Create signature for first repo
        bytes32 digest1 = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    REPO_ID,
                    ACCOUNT_ID,
                    keccak256(abi.encode(admins1)),
                    escrow.getRepoSetAdminNonce(REPO_ID, ACCOUNT_ID),
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(ownerPrivateKey, digest1);
        
        // Initialize first repo
        escrow.initRepo(REPO_ID, ACCOUNT_ID, admins1, signatureDeadline, v1, r1, s1);
        
        // Try to reuse signature for second repo (should fail due to nonce increment)
        expectRevert(Errors.INVALID_SIGNATURE);
        escrow.initRepo(REPO_ID + 1, ACCOUNT_ID + 1, admins2, signatureDeadline, v1, r1, s1);
        
        // Proper second initialization should work
        bytes32 digest2 = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    REPO_ID + 1,
                    ACCOUNT_ID + 1,
                    keccak256(abi.encode(admins2)),
                    escrow.getRepoSetAdminNonce(REPO_ID + 1, ACCOUNT_ID + 1),
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(ownerPrivateKey, digest2);
        escrow.initRepo(REPO_ID + 1, ACCOUNT_ID + 1, admins2, signatureDeadline, v2, r2, s2);
    }

    /* -------------------------------------------------------------------------- */
    /*                          INTEGRATION TESTS                                 */
    /* -------------------------------------------------------------------------- */

    function test_initRepo_integration_afterSignerChange() public {
        uint256 newSignerPrivateKey = 0x3333333333333333333333333333333333333333333333333333333333333333;
        address newSigner = vm.addr(newSignerPrivateKey);
        
        // Change signer (only owner can do this)
        vm.prank(owner);
        escrow.setSigner(newSigner);
        
        address[] memory admins = new address[](1);
        admins[0] = repoAdmin;
        
        uint256 signatureDeadline = block.timestamp + 1 hours;
        
        // Old signer signature should fail
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    REPO_ID,
                    ACCOUNT_ID,
                    keccak256(abi.encode(admins)),
                    escrow.getRepoSetAdminNonce(REPO_ID, ACCOUNT_ID),
                    signatureDeadline
                ))
            )
        );
        
        (uint8 vOld, bytes32 rOld, bytes32 sOld) = vm.sign(ownerPrivateKey, digest);
        expectRevert(Errors.INVALID_SIGNATURE);
        escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, signatureDeadline, vOld, rOld, sOld);
        
        // New signer signature should work
        (uint8 vNew, bytes32 rNew, bytes32 sNew) = vm.sign(newSignerPrivateKey, digest);
        escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, signatureDeadline, vNew, rNew, sNew);
        
        assertTrue(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, repoAdmin));
    }

    function test_initRepo_integration_maxBatchLimit() public {
        uint256 batchLimit = escrow.batchLimit();
        address[] memory admins = new address[](batchLimit);
        
        // Fill with valid addresses
        for (uint i = 0; i < batchLimit; i++) {
            admins[i] = address(uint160(i + 1));
        }
        
        _initializeRepo(REPO_ID, ACCOUNT_ID, admins);
        
        // Verify all admins were added
        address[] memory retrievedAdmins = escrow.getAllAdmins(REPO_ID, ACCOUNT_ID);
        assertEq(retrievedAdmins.length, batchLimit);
        
        for (uint i = 0; i < batchLimit; i++) {
            assertTrue(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, admins[i]));
        }
    }

    function test_initRepo_integration_gasOptimization() public {
        // Test gas usage for different admin array sizes
        address[] memory singleAdmin = new address[](1);
        singleAdmin[0] = makeAddr("singleAdmin");
        
        address[] memory multipleAdmins = new address[](10);
        for (uint i = 0; i < 10; i++) {
            multipleAdmins[i] = makeAddr(string(abi.encodePacked("admin", i)));
        }
        
        // Single admin initialization
        uint256 gasBefore = gasleft();
        _initializeRepo(1, 100, singleAdmin);
        uint256 gasUsedSingle = gasBefore - gasleft();
        
        // Multiple admin initialization
        gasBefore = gasleft();
        _initializeRepo(2, 200, multipleAdmins);
        uint256 gasUsedMultiple = gasBefore - gasleft();
        
        // Multiple should be more efficient per admin than individual calls
        assertTrue(gasUsedMultiple < gasUsedSingle * 10);
    }

    /* -------------------------------------------------------------------------- */
    /*                                FUZZ TESTS                                  */
    /* -------------------------------------------------------------------------- */

    function test_initRepo_fuzz_adminCount(uint8 adminCount) public {
        vm.assume(adminCount > 0 && adminCount <= 50); // Reasonable bounds
        
        address[] memory admins = new address[](adminCount);
        for (uint i = 0; i < adminCount; i++) {
            admins[i] = address(uint160(i + 1));
        }
        
        _initializeRepo(REPO_ID, ACCOUNT_ID, admins);
        
        // Verify all admins were added
        address[] memory retrievedAdmins = escrow.getAllAdmins(REPO_ID, ACCOUNT_ID);
        assertEq(retrievedAdmins.length, adminCount);
        
        for (uint i = 0; i < adminCount; i++) {
            assertTrue(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, admins[i]));
        }
    }

    function test_initRepo_fuzz_deadline(uint256 timeOffset) public {
        vm.assume(timeOffset > 0 && timeOffset <= 365 days); // Reasonable future deadline
        
        address[] memory admins = new address[](1);
        admins[0] = repoAdmin;
        
        uint256 signatureDeadline = block.timestamp + timeOffset;
        
        uint256 signatureDeadline_param = signatureDeadline;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    REPO_ID,
                    ACCOUNT_ID,
                    keccak256(abi.encode(admins)),
                    escrow.getRepoSetAdminNonce(REPO_ID, ACCOUNT_ID),
                    signatureDeadline_param
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, signatureDeadline_param, v, r, s);
        
        assertTrue(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, repoAdmin));
    }

    /* -------------------------------------------------------------------------- */
    /*                                HELPER FUNCTIONS                           */
    /* -------------------------------------------------------------------------- */

    function _initializeRepo(uint256 repoId, uint256 accountId, address[] memory admins) internal {
        uint256 signatureDeadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    repoId,
                    accountId,
                    keccak256(abi.encode(admins)),
                    escrow.getRepoSetAdminNonce(repoId, accountId),
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        escrow.initRepo(repoId, accountId, admins, signatureDeadline, v, r, s);
    }

    function test_getAccountExists() public {
        // Test non-existent account
        assertFalse(escrow.getAccountExists(123, 456));
        
        // Initialize an account
        address[] memory admins = new address[](1);
        admins[0] = repoAdmin;
        _initializeRepo(123, 456, admins);
        
        // Test existing account
        assertTrue(escrow.getAccountExists(123, 456));
        
        // Test different account that doesn't exist
        assertFalse(escrow.getAccountExists(123, 457));
        assertFalse(escrow.getAccountExists(124, 456));
    }

    function test_initRepo_fuzz_signatures(uint256 wrongNonce, uint256 wrongDeadline) public {
        vm.assume(wrongNonce != escrow.getRepoSetAdminNonce(REPO_ID, ACCOUNT_ID));
        vm.assume(wrongDeadline != block.timestamp + 1 hours);
        vm.assume(wrongDeadline > block.timestamp); // Must be future timestamp
        
        address[] memory admins = new address[](1);
        admins[0] = repoAdmin;
        uint256 repoId = 999;
        uint256 accountId = 999;
        
        // Test with wrong nonce
        bytes32 digestWrongNonce = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    repoId,
                    accountId,
                    keccak256(abi.encode(admins)),
                    wrongNonce,
                    block.timestamp + 1 hours
                ))
            )
        );
        
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(ownerPrivateKey, digestWrongNonce);
        expectRevert(Errors.INVALID_SIGNATURE);
        escrow.initRepo(repoId, accountId, admins, block.timestamp + 1 hours, v1, r1, s1);
        
        // Test with wrong deadline in signature
        bytes32 digestWrongDeadline = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    repoId,
                    accountId,
                    keccak256(abi.encode(admins)),
                    escrow.getRepoSetAdminNonce(REPO_ID, ACCOUNT_ID),
                    wrongDeadline
                ))
            )
        );
        
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(ownerPrivateKey, digestWrongDeadline);
        expectRevert(Errors.INVALID_SIGNATURE);
        escrow.initRepo(repoId, accountId, admins, block.timestamp + 1 hours, v2, r2, s2);
    }

    function test_initRepo_fuzz_batchLimits(uint8 numAdmins) public {
        vm.assume(numAdmins > 0);
        uint256 batchLimit = escrow.batchLimit();
        
        address[] memory admins = new address[](numAdmins);
        for (uint i = 0; i < numAdmins; i++) {
            admins[i] = makeAddr(string(abi.encodePacked("batchAdmin", i)));
        }
        
        uint256 repoId = 888;
        uint256 accountId = 888;
        uint256 signatureDeadline = block.timestamp + 1 hours;
        
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    repoId,
                    accountId,
                    keccak256(abi.encode(admins)),
                    escrow.getRepoSetAdminNonce(REPO_ID, ACCOUNT_ID),
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        
        if (numAdmins <= batchLimit) {
            // Should succeed if within batch limit
            escrow.initRepo(repoId, accountId, admins, signatureDeadline, v, r, s);
            
            // Verify all admins were added
            for (uint i = 0; i < numAdmins; i++) {
                assertTrue(escrow.getIsAuthorizedAdmin(repoId, accountId, admins[i]));
            }
            
            address[] memory allAdmins = escrow.getAllAdmins(repoId, accountId);
            assertEq(allAdmins.length, numAdmins);
        } else {
            // Should fail if exceeds batch limit
            expectRevert(Errors.BATCH_LIMIT_EXCEEDED);
            escrow.initRepo(repoId, accountId, admins, signatureDeadline, v, r, s);
        }
    }

    function test_initRepo_fuzz_timeDeadlines(uint32 timeOffset) public {
        vm.assume(timeOffset > 0 && timeOffset <= 365 days);
        
        address[] memory admins = new address[](1);
        admins[0] = repoAdmin;
        uint256 repoId = 777;
        uint256 accountId = 777;
        uint256 signatureDeadline = block.timestamp + timeOffset;
        
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    repoId,
                    accountId,
                    keccak256(abi.encode(admins)),
                    escrow.getRepoSetAdminNonce(REPO_ID, ACCOUNT_ID),
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        
        // Should work with any reasonable future deadline
        escrow.initRepo(repoId, accountId, admins, signatureDeadline, v, r, s);
        assertTrue(escrow.getIsAuthorizedAdmin(repoId, accountId, repoAdmin));
        assertTrue(escrow.getAccountExists(repoId, accountId));
    }

    /* -------------------------------------------------------------------------- */
    /*                          ADVANCED FUZZ TESTS                               */
    /* -------------------------------------------------------------------------- */

    /// @dev Fuzz test for initialization with various admin configurations
    function testFuzz_initRepo_adminConfigurations(uint8 numAdmins, uint256[50] memory /*adminSeeds*/, uint256 repoId, uint256 accountId) public {
        uint256 batchLimit = escrow.batchLimit();
        numAdmins = uint8(bound(numAdmins, 1, batchLimit > 50 ? 50 : batchLimit));
        repoId = bound(repoId, 1, type(uint32).max);
        accountId = bound(accountId, 1, type(uint32).max);
        
        // Generate unique admin addresses more reliably
        address[] memory admins = new address[](numAdmins);
        for (uint256 i = 0; i < numAdmins; i++) {
            // Use a more reliable method to generate unique addresses
            admins[i] = makeAddr(string(abi.encodePacked("fuzzAdmin", i, repoId, accountId)));
        }
        
        uint256 signatureDeadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    repoId,
                    accountId,
                    keccak256(abi.encode(admins)),
                    escrow.getRepoSetAdminNonce(repoId, accountId),
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        escrow.initRepo(repoId, accountId, admins, signatureDeadline, v, r, s);
        
        // Verify repo was initialized correctly
        assertTrue(escrow.getAccountExists(repoId, accountId));
        
        // Verify all admins were added
        address[] memory retrievedAdmins = escrow.getAllAdmins(repoId, accountId);
        assertEq(retrievedAdmins.length, numAdmins, "Admin count mismatch");
        
        // Verify each admin is authorized
        for (uint256 i = 0; i < numAdmins; i++) {
            assertTrue(escrow.getIsAuthorizedAdmin(repoId, accountId, admins[i]), "Admin not authorized");
        }
    }

    /// @dev Fuzz test for signature timing edge cases
    function testFuzz_initRepo_signatureTimingEdgeCases(
        uint256 signatureTime,
        uint32 validity
    ) public {
        signatureTime = bound(signatureTime, block.timestamp, block.timestamp + 365 days);
        validity = uint32(bound(validity, 1 minutes, 30 days));
        
        address[] memory admins = new address[](1);
        admins[0] = repoAdmin;
        
        // Set time to signature time
        vm.warp(signatureTime);
        
        uint256 signatureDeadline = signatureTime + validity;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    REPO_ID,
                    ACCOUNT_ID,
                    keccak256(abi.encode(admins)),
                    escrow.getRepoSetAdminNonce(REPO_ID, ACCOUNT_ID),
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        
        // Try to initialize at different times relative to deadline
        uint256 attemptTime = bound(signatureTime, signatureTime, signatureDeadline);
        vm.warp(attemptTime);
        
        if (attemptTime <= signatureDeadline) {
            // Should succeed
            escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, signatureDeadline, v, r, s);
            assertTrue(escrow.getAccountExists(REPO_ID, ACCOUNT_ID));
        } else {
            // Should fail with expired signature
            expectRevert(Errors.SIGNATURE_EXPIRED);
            escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, signatureDeadline, v, r, s);
        }
    }

    /// @dev Test EIP-712 signature malleability and edge cases
    function testFuzz_initRepo_signatureMalleability(
        uint256 privateKeySeed,
        bool flipV,
        bool flipR,
        bool flipS
    ) public {
        // Properly bound to Secp256k1 curve order - 1
        privateKeySeed = bound(privateKeySeed, 1, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364140);
        uint256 wrongPrivateKey = privateKeySeed;
        
        address[] memory admins = new address[](1);
        admins[0] = repoAdmin;
        
        uint256 signatureDeadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    REPO_ID,
                    ACCOUNT_ID,
                    keccak256(abi.encode(admins)),
                    escrow.getRepoSetAdminNonce(REPO_ID, ACCOUNT_ID),
                    signatureDeadline
                ))
            )
        );
        
        // Create signature with wrong key or manipulated values
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, digest);
        
        if (flipV) v = v == 27 ? 28 : 27;
        if (flipR) r = bytes32(uint256(r) ^ 1);
        if (flipS) s = bytes32(uint256(s) ^ 1);
        
        // Should fail with invalid signature (unless we got lucky with the wrong key being owner)
        if (vm.addr(wrongPrivateKey) != owner || flipV || flipR || flipS) {
            vm.expectRevert(); // Expect any revert (could be ECDSA error or INVALID_SIGNATURE)
            escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, signatureDeadline, v, r, s);
        }
    }

    /// @dev Test initialization with extreme repo and account IDs
    function testFuzz_initRepo_extremeIds(uint256 repoId, uint256 accountId) public {
        repoId = bound(repoId, 1, type(uint256).max);
        accountId = bound(accountId, 1, type(uint256).max);
        
        address[] memory admins = new address[](1);
        admins[0] = repoAdmin;
        
        uint256 signatureDeadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    repoId,
                    accountId,
                    keccak256(abi.encode(admins)),
                    escrow.getRepoSetAdminNonce(repoId, accountId),
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        escrow.initRepo(repoId, accountId, admins, signatureDeadline, v, r, s);
        
        // Should work with any valid uint256 values
        assertTrue(escrow.getAccountExists(repoId, accountId));
        assertTrue(escrow.getIsAuthorizedAdmin(repoId, accountId, repoAdmin));
    }

    /// @dev Test nonce increment behavior under various conditions
    function test_initRepo_nonceIncrementConsistency() public {
        // With per-repo nonces, each repo/instance pair has its own nonce counter
        uint256 initialNonce11 = escrow.getRepoSetAdminNonce(1, 1);
        uint256 initialNonce12 = escrow.getRepoSetAdminNonce(1, 2);
        
        // Initialize first repo (1,1)
        address[] memory admins1 = new address[](1);
        admins1[0] = repoAdmin;
        _initializeRepo(1, 1, admins1);
        assertEq(escrow.getRepoSetAdminNonce(1, 1), initialNonce11 + 1);
        
        // Initialize second repo (1,2) - this should have its own nonce counter
        address[] memory admins2 = new address[](1);
        admins2[0] = repoAdmin;
        _initializeRepo(1, 2, admins2);
        assertEq(escrow.getRepoSetAdminNonce(1, 2), initialNonce12 + 1);
        
        // Try to initialize repo (1,3) with wrong nonce (should fail)
        // Use nonce 5 which is wrong for a fresh repo
        address[] memory admins = new address[](1);
        admins[0] = repoAdmin;
        
        uint256 signatureDeadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    1,
                    3,
                    keccak256(abi.encode(admins)),
                    5, // Wrong nonce - should be 0 for fresh repo (1,3)
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        expectRevert(Errors.INVALID_SIGNATURE);
        escrow.initRepo(1, 3, admins, signatureDeadline, v, r, s);
    }

    /// @dev Test maximum batch limit edge cases
    function test_initRepo_maxBatchLimitEdgeCases() public {
        uint256 batchLimit = escrow.batchLimit();
        
        // Test with exactly batch limit admins
        address[] memory maxAdmins = new address[](batchLimit);
        for (uint256 i = 0; i < batchLimit; i++) {
            maxAdmins[i] = makeAddr(string(abi.encodePacked("admin", i)));
        }
        
        uint256 signatureDeadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    REPO_ID,
                    ACCOUNT_ID,
                    keccak256(abi.encode(maxAdmins)),
                    escrow.getRepoSetAdminNonce(REPO_ID, ACCOUNT_ID),
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        escrow.initRepo(REPO_ID, ACCOUNT_ID, maxAdmins, signatureDeadline, v, r, s);
        
        // Should succeed with max admins
        assertTrue(escrow.getAccountExists(REPO_ID, ACCOUNT_ID));
        address[] memory retrievedAdmins = escrow.getAllAdmins(REPO_ID, ACCOUNT_ID);
        assertEq(retrievedAdmins.length, batchLimit);
        
        // Test exceeding batch limit should fail
        address[] memory tooManyAdmins = new address[](batchLimit + 1);
        for (uint256 i = 0; i < batchLimit + 1; i++) {
            tooManyAdmins[i] = makeAddr(string(abi.encodePacked("admin2", i)));
        }
        
        bytes32 digest2 = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    2,
                    ACCOUNT_ID,
                    keccak256(abi.encode(tooManyAdmins)),
                    escrow.getRepoSetAdminNonce(REPO_ID, ACCOUNT_ID),
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(ownerPrivateKey, digest2);
        expectRevert(Errors.BATCH_LIMIT_EXCEEDED);
        escrow.initRepo(2, ACCOUNT_ID, tooManyAdmins, signatureDeadline, v2, r2, s2);
    }

    /* -------------------------------------------------------------------------- */
    /*                          INITIALIZED REPO EVENT TESTS                     */
    /* -------------------------------------------------------------------------- */

    function test_initRepo_emitsInitializedRepoEvent_singleAdmin() public {
        address[] memory admins = new address[](1);
        admins[0] = repoAdmin;
        
        uint256 signatureDeadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    REPO_ID,
                    ACCOUNT_ID,
                    keccak256(abi.encode(admins)),
                    escrow.getRepoSetAdminNonce(REPO_ID, ACCOUNT_ID),
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        // Expect InitializedRepo event to be emitted
        vm.expectEmit(true, true, false, true);
        emit InitializedRepo(REPO_ID, ACCOUNT_ID, admins);

        escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, signatureDeadline, v, r, s);
    }

    function test_initRepo_emitsInitializedRepoEvent_multipleAdmins() public {
        address admin1 = makeAddr("admin1");
        address admin2 = makeAddr("admin2");
        address admin3 = makeAddr("admin3");
        
        address[] memory admins = new address[](3);
        admins[0] = admin1;
        admins[1] = admin2;
        admins[2] = admin3;
        
        uint256 signatureDeadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    REPO_ID,
                    ACCOUNT_ID,
                    keccak256(abi.encode(admins)),
                    escrow.getRepoSetAdminNonce(REPO_ID, ACCOUNT_ID),
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        // Expect InitializedRepo event to be emitted with all admins
        vm.expectEmit(true, true, false, true);
        emit InitializedRepo(REPO_ID, ACCOUNT_ID, admins);

        escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, signatureDeadline, v, r, s);
    }

    function test_initRepo_emitsInitializedRepoEvent_differentRepoIds() public {
        address admin1 = makeAddr("admin1");
        address admin2 = makeAddr("admin2");
        
        address[] memory admins1 = new address[](1);
        admins1[0] = admin1;
        address[] memory admins2 = new address[](1);
        admins2[0] = admin2;

        // Test first repo
        uint256 signatureDeadline1 = block.timestamp + 1 hours;
        bytes32 digest1 = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    1,
                    100,
                    keccak256(abi.encode(admins1)),
                    escrow.getRepoSetAdminNonce(1, 100),
                    signatureDeadline1
                ))
            )
        );
        
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(ownerPrivateKey, digest1);

        vm.expectEmit(true, true, false, true);
        emit InitializedRepo(1, 100, admins1);
        escrow.initRepo(1, 100, admins1, signatureDeadline1, v1, r1, s1);

        // Test second repo
        uint256 signatureDeadline2 = block.timestamp + 1 hours;
        bytes32 digest2 = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    2,
                    200,
                    keccak256(abi.encode(admins2)),
                    escrow.getRepoSetAdminNonce(2, 200),
                    signatureDeadline2
                ))
            )
        );
        
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(ownerPrivateKey, digest2);

        vm.expectEmit(true, true, false, true);
        emit InitializedRepo(2, 200, admins2);
        escrow.initRepo(2, 200, admins2, signatureDeadline2, v2, r2, s2);
    }

    function test_initRepo_emitsInitializedRepoEvent_maximumAdmins() public {
        uint256 batchLimit = escrow.batchLimit();
        address[] memory admins = new address[](batchLimit);
        
        // Create maximum number of admins
        for (uint256 i = 0; i < batchLimit; i++) {
            admins[i] = makeAddr(string(abi.encodePacked("maxAdmin", i)));
        }
        
        uint256 signatureDeadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    REPO_ID,
                    ACCOUNT_ID,
                    keccak256(abi.encode(admins)),
                    escrow.getRepoSetAdminNonce(REPO_ID, ACCOUNT_ID),
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        // Expect InitializedRepo event with max admins
        vm.expectEmit(true, true, false, true);
        emit InitializedRepo(REPO_ID, ACCOUNT_ID, admins);

        escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, signatureDeadline, v, r, s);
    }

    function test_initRepo_emitsInitializedRepoEvent_fuzzRepoAndAccountIds(
        uint256 repoId, 
        uint256 accountId
    ) public {
        vm.assume(repoId != 0 && accountId != 0);
        vm.assume(repoId < type(uint128).max && accountId < type(uint128).max);
        
        address admin = makeAddr("fuzzAdmin");
        address[] memory admins = new address[](1);
        admins[0] = admin;
        
        uint256 signatureDeadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    repoId,
                    accountId,
                    keccak256(abi.encode(admins)),
                    escrow.getRepoSetAdminNonce(repoId, accountId),
                    signatureDeadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        // Expect InitializedRepo event with fuzzed IDs
        vm.expectEmit(true, true, false, true);
        emit InitializedRepo(repoId, accountId, admins);

        escrow.initRepo(repoId, accountId, admins, signatureDeadline, v, r, s);
    }

    /* -------------------------------------------------------------------------- */
    /*                           REPO SET ADMIN NONCE TESTS                       */
    /* -------------------------------------------------------------------------- */

    function test_repoSetAdminNonce_initialValues() public {
        // Fresh repos should have nonce 0
        assertEq(escrow.getRepoSetAdminNonce(1, 1), 0);
        assertEq(escrow.getRepoSetAdminNonce(1, 2), 0);
        assertEq(escrow.getRepoSetAdminNonce(2, 1), 0);
        assertEq(escrow.getRepoSetAdminNonce(999, 999), 0);
        assertEq(escrow.getRepoSetAdminNonce(type(uint256).max, type(uint256).max), 0);
    }

    function test_repoSetAdminNonce_incrementsAfterInitRepo() public {
        address[] memory admins = new address[](1);
        admins[0] = repoAdmin;

        // Check initial nonce
        assertEq(escrow.getRepoSetAdminNonce(1, 1), 0);

        // Initialize repo
        _initializeRepo(1, 1, admins);

        // Nonce should increment
        assertEq(escrow.getRepoSetAdminNonce(1, 1), 1);
    }

    function test_repoSetAdminNonce_independentCounters() public {
        address[] memory admins = new address[](1);
        admins[0] = repoAdmin;

        // Initialize different repo/instance combinations
        _initializeRepo(1, 1, admins);
        _initializeRepo(1, 2, admins);
        _initializeRepo(2, 1, admins);
        _initializeRepo(2, 2, admins);

        // Each should have independent nonce counter
        assertEq(escrow.getRepoSetAdminNonce(1, 1), 1);
        assertEq(escrow.getRepoSetAdminNonce(1, 2), 1);
        assertEq(escrow.getRepoSetAdminNonce(2, 1), 1);
        assertEq(escrow.getRepoSetAdminNonce(2, 2), 1);

        // Uninitialized repos should still be 0
        assertEq(escrow.getRepoSetAdminNonce(3, 1), 0);
        assertEq(escrow.getRepoSetAdminNonce(1, 3), 0);
    }

    function test_repoSetAdminNonce_multipleInitializations() public {
        address[] memory admins1 = new address[](1);
        admins1[0] = repoAdmin;
        address[] memory admins2 = new address[](1);
        admins2[0] = makeAddr("admin2");
        address[] memory admins3 = new address[](1);
        admins3[0] = makeAddr("admin3");

        uint256 repoId = 5;
        uint256 instanceId = 10;

        // Initialize same repo multiple times (should fail after first)
        _initializeRepo(repoId, instanceId, admins1);
        assertEq(escrow.getRepoSetAdminNonce(repoId, instanceId), 1);

        // Second initialization should fail but nonce shouldn't change
        // Create signature with current nonce for already initialized repo
        uint256 signatureDeadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    repoId,
                    instanceId,
                    keccak256(abi.encode(admins2)),
                    escrow.getRepoSetAdminNonce(repoId, instanceId), // Current nonce
                    signatureDeadline
                ))
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        
        expectRevert(Errors.REPO_ALREADY_INITIALIZED);
        escrow.initRepo(repoId, instanceId, admins2, signatureDeadline, v, r, s);
        assertEq(escrow.getRepoSetAdminNonce(repoId, instanceId), 1);

        // Initialize different instances of same repo
        _initializeRepo(repoId, instanceId + 1, admins2);
        _initializeRepo(repoId, instanceId + 2, admins3);

        // Check nonces
        assertEq(escrow.getRepoSetAdminNonce(repoId, instanceId), 1);
        assertEq(escrow.getRepoSetAdminNonce(repoId, instanceId + 1), 1);
        assertEq(escrow.getRepoSetAdminNonce(repoId, instanceId + 2), 1);
    }

    function test_repoSetAdminNonce_wrongNonceFailsSignature() public {
        address[] memory admins = new address[](1);
        admins[0] = repoAdmin;

        uint256 repoId = 7;
        uint256 instanceId = 8;

        // Try to initialize with wrong nonce (should be 0, but use 1)
        uint256 signatureDeadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    repoId,
                    instanceId,
                    keccak256(abi.encode(admins)),
                    1, // Wrong nonce - should be 0
                    signatureDeadline
                ))
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        expectRevert(Errors.INVALID_SIGNATURE);
        escrow.initRepo(repoId, instanceId, admins, signatureDeadline, v, r, s);

        // Nonce should remain 0
        assertEq(escrow.getRepoSetAdminNonce(repoId, instanceId), 0);
    }

    function test_repoSetAdminNonce_replayAttackPrevention() public {
        address[] memory admins1 = new address[](1);
        admins1[0] = repoAdmin;
        address[] memory admins2 = new address[](1);  
        admins2[0] = makeAddr("admin2");

        uint256 repoId = 100;

        // Initialize repo (1, 100)
        _initializeRepo(repoId, 100, admins1);
        assertEq(escrow.getRepoSetAdminNonce(repoId, 100), 1);

        // Try to use the same signature for different instance (should fail)
        uint256 signatureDeadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    repoId,
                    100, // Same instance
                    keccak256(abi.encode(admins1)),
                    0, // Old nonce (was incremented to 1)
                    signatureDeadline
                ))
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        // Should fail - repo already initialized
        expectRevert(Errors.REPO_ALREADY_INITIALIZED);
        escrow.initRepo(repoId, 100, admins1, signatureDeadline, v, r, s);

        // Try to replay for different instance - should also fail due to wrong nonce
        expectRevert(Errors.INVALID_SIGNATURE);
        escrow.initRepo(repoId, 101, admins2, signatureDeadline, v, r, s);
    }

    function test_repoSetAdminNonce_crossRepoIsolation() public {
        address[] memory admins = new address[](1);
        admins[0] = repoAdmin;

        // Initialize repo (5, 5)
        _initializeRepo(5, 5, admins);
        assertEq(escrow.getRepoSetAdminNonce(5, 5), 1);

        // Try to use repo (5,5)'s nonce for repo (6,6) - should fail
        uint256 signatureDeadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    6,
                    6,
                    keccak256(abi.encode(admins)),
                    1, // Using nonce from different repo
                    signatureDeadline
                ))
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        expectRevert(Errors.INVALID_SIGNATURE);
        escrow.initRepo(6, 6, admins, signatureDeadline, v, r, s);

        // Repo (6,6) should still have nonce 0
        assertEq(escrow.getRepoSetAdminNonce(6, 6), 0);
    }

    function test_repoSetAdminNonce_extremeValues() public {
        address[] memory admins = new address[](1);
        admins[0] = repoAdmin;

        // Test with maximum values
        uint256 maxRepoId = type(uint256).max;
        uint256 maxInstanceId = type(uint256).max;

        assertEq(escrow.getRepoSetAdminNonce(maxRepoId, maxInstanceId), 0);

        _initializeRepo(maxRepoId, maxInstanceId, admins);
        assertEq(escrow.getRepoSetAdminNonce(maxRepoId, maxInstanceId), 1);

        // Test with zero values
        assertEq(escrow.getRepoSetAdminNonce(0, 0), 0);
        _initializeRepo(0, 0, admins);
        assertEq(escrow.getRepoSetAdminNonce(0, 0), 1);

        // Test with mixed extreme values
        assertEq(escrow.getRepoSetAdminNonce(0, maxInstanceId), 0);
        assertEq(escrow.getRepoSetAdminNonce(maxRepoId, 0), 0);

        _initializeRepo(0, maxInstanceId, admins);
        _initializeRepo(maxRepoId, 0, admins);

        assertEq(escrow.getRepoSetAdminNonce(0, maxInstanceId), 1);
        assertEq(escrow.getRepoSetAdminNonce(maxRepoId, 0), 1);
    }

    function test_repoSetAdminNonce_fuzzSequentialInits(uint256 numRepos) public {
        vm.assume(numRepos > 0 && numRepos <= 10); // Reasonable limit

        address[] memory admins = new address[](1);
        admins[0] = repoAdmin;

        // Initialize sequential repos
        for (uint256 i = 0; i < numRepos; i++) {
            uint256 repoId = 1000 + i;
            uint256 instanceId = 2000 + i;
            
            // Check initial nonce
            assertEq(escrow.getRepoSetAdminNonce(repoId, instanceId), 0);
            
            // Initialize repo
            _initializeRepo(repoId, instanceId, admins);
            
            // Check nonce incremented
            assertEq(escrow.getRepoSetAdminNonce(repoId, instanceId), 1);
        }

        // Verify all nonces are still correct
        for (uint256 i = 0; i < numRepos; i++) {
            uint256 repoId = 1000 + i;
            uint256 instanceId = 2000 + i;
            assertEq(escrow.getRepoSetAdminNonce(repoId, instanceId), 1);
        }
    }

    function test_repoSetAdminNonce_fuzzCrossContamination(
        uint256 repoId1, 
        uint256 instanceId1,
        uint256 repoId2, 
        uint256 instanceId2
    ) public {
        // Ensure different repo/instance combinations
        vm.assume(repoId1 != repoId2 || instanceId1 != instanceId2);
        vm.assume(repoId1 <= type(uint128).max && instanceId1 <= type(uint128).max);
        vm.assume(repoId2 <= type(uint128).max && instanceId2 <= type(uint128).max);

        address[] memory admins = new address[](1);
        admins[0] = repoAdmin;

        // Both should start at 0
        assertEq(escrow.getRepoSetAdminNonce(repoId1, instanceId1), 0);
        assertEq(escrow.getRepoSetAdminNonce(repoId2, instanceId2), 0);

        // Initialize first repo
        _initializeRepo(repoId1, instanceId1, admins);

        // First repo nonce should be 1, second should still be 0
        assertEq(escrow.getRepoSetAdminNonce(repoId1, instanceId1), 1);
        assertEq(escrow.getRepoSetAdminNonce(repoId2, instanceId2), 0);

        // Initialize second repo
        _initializeRepo(repoId2, instanceId2, admins);

        // Both should now be 1, independently
        assertEq(escrow.getRepoSetAdminNonce(repoId1, instanceId1), 1);
        assertEq(escrow.getRepoSetAdminNonce(repoId2, instanceId2), 1);
    }

    function test_repoSetAdminNonce_getterConsistency() public {
        address[] memory admins = new address[](1);
        admins[0] = repoAdmin;

        uint256 repoId = 42;
        uint256 instanceId = 24;

        // Test getter before and after initialization
        uint256 nonceBefore = escrow.getRepoSetAdminNonce(repoId, instanceId);
        assertEq(nonceBefore, 0);

        _initializeRepo(repoId, instanceId, admins);

        uint256 nonceAfter = escrow.getRepoSetAdminNonce(repoId, instanceId);
        assertEq(nonceAfter, 1);
        assertEq(nonceAfter, nonceBefore + 1);
    }

    function test_repoSetAdminNonce_signatureValidationIntegration() public {
        address[] memory admins = new address[](1);
        admins[0] = repoAdmin;

        uint256 repoId = 99;
        uint256 instanceId = 88;

        // Get current nonce and create valid signature
        uint256 currentNonce = escrow.getRepoSetAdminNonce(repoId, instanceId);
        assertEq(currentNonce, 0);

        uint256 signatureDeadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    repoId,
                    instanceId,
                    keccak256(abi.encode(admins)),
                    currentNonce, // Correct nonce
                    signatureDeadline
                ))
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        // Should succeed
        escrow.initRepo(repoId, instanceId, admins, signatureDeadline, v, r, s);

        // Nonce should be incremented
        assertEq(escrow.getRepoSetAdminNonce(repoId, instanceId), 1);

        // Using the same signature again should fail (repo already initialized)
        expectRevert(Errors.REPO_ALREADY_INITIALIZED);
        escrow.initRepo(repoId, instanceId, admins, signatureDeadline, v, r, s);
    }

    /* -------------------------------------------------------------------------- */
    /*                                    EVENTS                                  */
    /* -------------------------------------------------------------------------- */

    event AddedAdmin(uint256 indexed repoId, uint256 indexed accountId, address oldAdmin, address indexed newAdmin);
    event InitializedRepo(uint256 indexed repoId, uint256 indexed accountId, address[] admins);
} 