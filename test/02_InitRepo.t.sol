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
                    escrow.ownerNonce(),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        vm.expectEmit(true, true, true, true);
        emit AdminSet(REPO_ID, ACCOUNT_ID, address(0), repoAdmin);

        escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, deadline, v, r, s);

        // Verify admin was set
        address[] memory retrievedAdmins = escrow.getAllAdmins(REPO_ID, ACCOUNT_ID);
        assertEq(retrievedAdmins.length, 1);
        assertEq(retrievedAdmins[0], repoAdmin);
        assertTrue(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, repoAdmin));
        
        // Verify nonce was incremented
        assertEq(escrow.ownerNonce(), 1);
    }

    function test_initRepo_multipleAdmins() public {
        address admin1 = makeAddr("admin1");
        address admin2 = makeAddr("admin2");
        address admin3 = makeAddr("admin3");
        
        address[] memory admins = new address[](3);
        admins[0] = admin1;
        admins[1] = admin2;
        admins[2] = admin3;
        
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
                    escrow.ownerNonce(),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        // Expect events for all admins
        vm.expectEmit(true, true, true, true);
        emit AdminSet(REPO_ID, ACCOUNT_ID, address(0), admin1);
        vm.expectEmit(true, true, true, true);
        emit AdminSet(REPO_ID, ACCOUNT_ID, address(0), admin2);
        vm.expectEmit(true, true, true, true);
        emit AdminSet(REPO_ID, ACCOUNT_ID, address(0), admin3);

        escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, deadline, v, r, s);

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
                    escrow.ownerNonce(),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        expectRevert(Errors.REPO_ALREADY_INITIALIZED);
        escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, deadline, v, r, s);
    }

    function test_initRepo_revert_emptyAdminsArray() public {
        address[] memory admins = new address[](0); // Empty array
        
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
                    escrow.ownerNonce(),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        expectRevert(Errors.INVALID_AMOUNT);
        escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, deadline, v, r, s);
    }

    function test_initRepo_revert_invalidAddress() public {
        address[] memory admins = new address[](2);
        admins[0] = repoAdmin;
        admins[1] = address(0); // Invalid address
        
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
                    escrow.ownerNonce(),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        expectRevert(Errors.INVALID_ADDRESS);
        escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, deadline, v, r, s);
    }

    function test_initRepo_revert_expiredSignature() public {
        address[] memory admins = new address[](1);
        admins[0] = repoAdmin;
        
        uint256 deadline = block.timestamp - 1; // Expired deadline
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    REPO_ID,
                    ACCOUNT_ID,
                    keccak256(abi.encode(admins)),
                    escrow.ownerNonce(),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        expectRevert(Errors.SIGNATURE_EXPIRED);
        escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, deadline, v, r, s);
    }

    function test_initRepo_revert_invalidSignature() public {
        address[] memory admins = new address[](1);
        admins[0] = repoAdmin;
        
        uint256 deadline = block.timestamp + 1 hours;
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
                    escrow.ownerNonce(),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, digest);

        expectRevert(Errors.INVALID_SIGNATURE);
        escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, deadline, v, r, s);
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
        
        uint256 initialNonce = escrow.ownerNonce();
        
        _initializeRepo(1, 100, admins1);
        assertEq(escrow.ownerNonce(), initialNonce + 1);
        
        _initializeRepo(2, 200, admins2);
        assertEq(escrow.ownerNonce(), initialNonce + 2);
    }

    function test_initRepo_domainSeparator() public {
        // Test that the domain separator is properly used in signature verification
        address[] memory admins = new address[](1);
        admins[0] = repoAdmin;
        
        uint256 deadline = block.timestamp + 1 hours;
        
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
                    escrow.ownerNonce(),
                    deadline
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
                    escrow.ownerNonce(),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, correctDigest);
        (uint8 vWrong, bytes32 rWrong, bytes32 sWrong) = vm.sign(ownerPrivateKey, wrongDigest);
        
        // Correct signature should work
        escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, deadline, v, r, s);
        
        address[] memory admins2 = new address[](1);
        admins2[0] = repoAdmin;
        
        // Wrong signature should fail
        expectRevert(Errors.INVALID_SIGNATURE);
        escrow.initRepo(2, 200, admins2, deadline, vWrong, rWrong, sWrong);
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
                    escrow.ownerNonce(),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        expectRevert(Errors.BATCH_LIMIT_EXCEEDED);
        escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, deadline, v, r, s);
    }

    function test_initRepo_duplicateAdmins() public {
        address admin1 = makeAddr("admin1");
        
        address[] memory admins = new address[](3);
        admins[0] = admin1;
        admins[1] = admin1; // Duplicate
        admins[2] = admin1; // Another duplicate
        
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
                    escrow.ownerNonce(),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        // Only one event should be emitted since EnumerableSet handles duplicates
        vm.expectEmit(true, true, true, true);
        emit AdminSet(REPO_ID, ACCOUNT_ID, address(0), admin1);

        escrow.initRepo(REPO_ID, ACCOUNT_ID, admins, deadline, v, r, s);

        // Verify only one admin is in the set despite duplicates
        address[] memory retrievedAdmins = escrow.getAllAdmins(REPO_ID, ACCOUNT_ID);
        assertEq(retrievedAdmins.length, 1);
        assertEq(retrievedAdmins[0], admin1);
        assertTrue(escrow.getIsAuthorizedAdmin(REPO_ID, ACCOUNT_ID, admin1));
    }

    /* -------------------------------------------------------------------------- */
    /*                                HELPER FUNCTIONS                           */
    /* -------------------------------------------------------------------------- */

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
    /*                                    EVENTS                                  */
    /* -------------------------------------------------------------------------- */

    event AdminSet(uint256 indexed repoId, uint256 indexed accountId, address oldAdmin, address indexed newAdmin);
} 