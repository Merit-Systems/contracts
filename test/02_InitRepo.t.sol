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
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    REPO_ID,
                    ACCOUNT_ID,
                    repoAdmin,
                    escrow.ownerNonce(),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        vm.expectEmit(true, true, true, true);
        emit AdminSet(REPO_ID, ACCOUNT_ID, address(0), repoAdmin);

        escrow.initRepo(REPO_ID, ACCOUNT_ID, repoAdmin, deadline, v, r, s);

        // Verify admin was set
        assertEq(escrow.getAccountAdmin(REPO_ID, ACCOUNT_ID), repoAdmin);
        
        // Verify nonce was incremented
        assertEq(escrow.ownerNonce(), 1);
    }

    function test_initRepo_revert_alreadyInitialized() public {
        // First initialization
        _initializeRepo(REPO_ID, ACCOUNT_ID, repoAdmin);

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
                    repoAdmin,
                    escrow.ownerNonce(),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        expectRevert(Errors.REPO_ALREADY_INITIALIZED);
        escrow.initRepo(REPO_ID, ACCOUNT_ID, repoAdmin, deadline, v, r, s);
    }

    function test_initRepo_revert_invalidAddress() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    REPO_ID,
                    ACCOUNT_ID,
                    address(0), // Invalid address
                    escrow.ownerNonce(),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        expectRevert(Errors.INVALID_ADDRESS);
        escrow.initRepo(REPO_ID, ACCOUNT_ID, address(0), deadline, v, r, s);
    }

    function test_initRepo_revert_expiredSignature() public {
        uint256 deadline = block.timestamp - 1; // Expired deadline
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                escrow.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    escrow.SET_ADMIN_TYPEHASH(),
                    REPO_ID,
                    ACCOUNT_ID,
                    repoAdmin,
                    escrow.ownerNonce(),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        expectRevert(Errors.SIGNATURE_EXPIRED);
        escrow.initRepo(REPO_ID, ACCOUNT_ID, repoAdmin, deadline, v, r, s);
    }

    function test_initRepo_revert_invalidSignature() public {
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
                    repoAdmin,
                    escrow.ownerNonce(),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, digest);

        expectRevert(Errors.INVALID_SIGNATURE);
        escrow.initRepo(REPO_ID, ACCOUNT_ID, repoAdmin, deadline, v, r, s);
    }

    function test_initRepo_differentReposAndAccounts() public {
        address admin1 = makeAddr("admin1");
        address admin2 = makeAddr("admin2");
        address admin3 = makeAddr("admin3");

        // Initialize different repo/account combinations
        _initializeRepo(1, 100, admin1);
        _initializeRepo(1, 200, admin2);  // Same repo, different account
        _initializeRepo(2, 100, admin3);  // Different repo, same account

        // Verify all admins were set correctly
        assertEq(escrow.getAccountAdmin(1, 100), admin1);
        assertEq(escrow.getAccountAdmin(1, 200), admin2);
        assertEq(escrow.getAccountAdmin(2, 100), admin3);
    }

    function test_initRepo_fuzz_repoAndAccountIds(uint256 repoId, uint256 accountId) public {
        vm.assume(repoId != 0 && accountId != 0); // Avoid potential edge cases
        vm.assume(repoId < type(uint128).max && accountId < type(uint128).max); // Reasonable bounds
        
        address admin = makeAddr("fuzzAdmin");
        _initializeRepo(repoId, accountId, admin);
        
        assertEq(escrow.getAccountAdmin(repoId, accountId), admin);
    }

    function test_initRepo_nonceIncrement() public {
        address admin1 = makeAddr("admin1");
        address admin2 = makeAddr("admin2");
        
        uint256 initialNonce = escrow.ownerNonce();
        
        _initializeRepo(1, 100, admin1);
        assertEq(escrow.ownerNonce(), initialNonce + 1);
        
        _initializeRepo(2, 200, admin2);
        assertEq(escrow.ownerNonce(), initialNonce + 2);
    }

    function test_initRepo_domainSeparator() public {
        // Test that the domain separator is properly used in signature verification
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
                    repoAdmin,
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
                    repoAdmin,
                    escrow.ownerNonce(),
                    deadline
                ))
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, correctDigest);
        (uint8 vWrong, bytes32 rWrong, bytes32 sWrong) = vm.sign(ownerPrivateKey, wrongDigest);
        
        // Correct signature should work
        escrow.initRepo(REPO_ID, ACCOUNT_ID, repoAdmin, deadline, v, r, s);
        
        // Wrong signature should fail
        expectRevert(Errors.INVALID_SIGNATURE);
        escrow.initRepo(2, 200, repoAdmin, deadline, vWrong, rWrong, sWrong);
    }

    function test_initRepo_zeroRepoAndAccountIds() public {
        address admin = makeAddr("zeroAdmin");
        
        // Test that repo ID and account ID of 0 are allowed
        _initializeRepo(0, 0, admin);
        assertEq(escrow.getAccountAdmin(0, 0), admin);
        
        _initializeRepo(0, 1, admin);
        assertEq(escrow.getAccountAdmin(0, 1), admin);
        
        _initializeRepo(1, 0, admin);
        assertEq(escrow.getAccountAdmin(1, 0), admin);
    }

    function test_initRepo_maxValues() public {
        address admin = makeAddr("maxAdmin");
        uint256 maxUint = type(uint256).max;
        
        // Test with maximum uint256 values
        _initializeRepo(maxUint, maxUint, admin);
        assertEq(escrow.getAccountAdmin(maxUint, maxUint), admin);
    }

    /* -------------------------------------------------------------------------- */
    /*                                HELPER FUNCTIONS                           */
    /* -------------------------------------------------------------------------- */

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
    /*                                    EVENTS                                  */
    /* -------------------------------------------------------------------------- */

    event AdminSet(uint256 indexed repoId, uint256 indexed accountId, address oldAdmin, address indexed newAdmin);
} 