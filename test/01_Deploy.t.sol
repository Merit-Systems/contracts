// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "./00_Escrow.t.sol";
import "../script/Deploy.Base.s.sol";

contract Deploy_Test is Base_Test {
    
    address testOwner;
    address testSigner;
    address testToken1;
    address testToken2;

    uint256 testOwnerPrivateKey = 0x1111111111111111111111111111111111111111111111111111111111111111;
    uint256 testSignerPrivateKey = 0x2222222222222222222222222222222222222222222222222222222222222222;
    
    function setUp() public override {
        // Don't call super.setUp() as we want to test deployment ourselves
        testOwner = vm.addr(testOwnerPrivateKey);
        testSigner = vm.addr(testSignerPrivateKey);
        testToken1 = makeAddr("testToken1");
        testToken2 = makeAddr("testToken2");
        
        alice = makeAddr("alice");
        bob = makeAddr("bob");
    }

    /* -------------------------------------------------------------------------- */
    /*                             DEPLOYMENT TESTS                              */
    /* -------------------------------------------------------------------------- */

    function test_deploy_success_usingScript() public {
        // Use the actual deployment script
        DeployBase deployScript = new DeployBase();
        
        // The deployment script will emit these events for the BASE_USDC token
        vm.expectEmit(true, false, false, false);
        emit WhitelistedToken(Params.BASE_USDC);

        Escrow deployedEscrow = deployScript.run();

        // Verify initial state matches the parameters in Deploy.Base.s.sol
        assertEq(deployedEscrow.owner(), Params.BASE_OWNER);
        assertEq(deployedEscrow.signer(), Params.BASE_SIGNER);
        assertEq(deployedEscrow.feeRecipient(), Params.BASE_OWNER);
        assertEq(deployedEscrow.feeOnClaim(), Params.BASE_FEE_ON_CLAIM_BPS);
        assertEq(deployedEscrow.feeOnFund(), Params.BASE_FEE_ON_FUND_BPS);
        assertEq(deployedEscrow.batchLimit(), Params.BATCH_LIMIT);
        assertEq(deployedEscrow.repoSetAdminNonce(0, 0), 0);
        assertEq(deployedEscrow.batchCount(), 0);
        assertEq(deployedEscrow.distributionCount(), 0);

        // Verify BASE_USDC was whitelisted
        assertTrue(deployedEscrow.isTokenWhitelisted(Params.BASE_USDC));
        
        address[] memory whitelistedTokens = deployedEscrow.getAllWhitelistedTokens();
        assertEq(whitelistedTokens.length, 1);
        assertEq(whitelistedTokens[0], Params.BASE_USDC);
    }

    function test_deploy_success() public {
        address[] memory initialWhitelist = new address[](2);
        initialWhitelist[0] = testToken1;
        initialWhitelist[1] = testToken2;
        
        uint256 feeBps = 250; // 2.5%
        uint256 batchLimit = 100;

        vm.expectEmit(true, false, false, false);
        emit WhitelistedToken(testToken1);
        
        vm.expectEmit(true, false, false, false);
        emit WhitelistedToken(testToken2);

        Escrow deployedEscrow = new Escrow(
            testOwner,
            testSigner,
            initialWhitelist,
            feeBps,
            batchLimit
        );

        // Verify initial state
        assertEq(deployedEscrow.owner(), testOwner);
        assertEq(deployedEscrow.signer(), testSigner);
        assertEq(deployedEscrow.feeRecipient(), testOwner);
        assertEq(deployedEscrow.feeOnClaim(), feeBps);
        assertEq(deployedEscrow.feeOnFund(), Params.BASE_FEE_ON_FUND_BPS);
        assertEq(deployedEscrow.batchLimit(), batchLimit);
        assertEq(deployedEscrow.repoSetAdminNonce(0, 0), 0);
        assertEq(deployedEscrow.batchCount(), 0);
        assertEq(deployedEscrow.distributionCount(), 0);

        // Verify tokens were whitelisted
        assertTrue(deployedEscrow.isTokenWhitelisted(testToken1));
        assertTrue(deployedEscrow.isTokenWhitelisted(testToken2));
        
        address[] memory whitelistedTokens = deployedEscrow.getAllWhitelistedTokens();
        assertEq(whitelistedTokens.length, 2);
        assertEq(whitelistedTokens[0], testToken1);
        assertEq(whitelistedTokens[1], testToken2);
    }

    function test_deploy_emptyWhitelist() public {
        address[] memory initialWhitelist = new address[](0);
        uint256 feeBps = 0;
        uint256 batchLimit = 50;

        Escrow deployedEscrow = new Escrow(
            testOwner,
            testSigner,
            initialWhitelist,
            feeBps,
            batchLimit
        );

        // Verify empty whitelist
        address[] memory whitelistedTokens = deployedEscrow.getAllWhitelistedTokens();
        assertEq(whitelistedTokens.length, 0);
        assertFalse(deployedEscrow.isTokenWhitelisted(testToken1));
    }

    function test_deploy_maxFeeBps() public {
        address[] memory initialWhitelist = new address[](0);
        uint256 maxFeeBps = 1000; // 10% - maximum allowed
        uint256 batchLimit = 1;

        Escrow deployedEscrow = new Escrow(
            testOwner,
            testSigner,
            initialWhitelist,
            maxFeeBps,
            batchLimit
        );

        assertEq(deployedEscrow.feeOnClaim(), maxFeeBps);
    }

    function test_deploy_revert_invalidFeeBps() public {
        address[] memory initialWhitelist = new address[](0);
        uint256 invalidFeeBps = 1001; // Above MAX_FEE_BPS
        uint256 batchLimit = 100;

        expectRevert(Errors.INVALID_FEE);
        new Escrow(
            testOwner,
            testSigner,
            initialWhitelist,
            invalidFeeBps,
            batchLimit
        );
    }

    function test_deploy_sameOwnerAndSigner() public {
        address[] memory initialWhitelist = new address[](1);
        initialWhitelist[0] = testToken1;
        
        Escrow deployedEscrow = new Escrow(
            testOwner,
            testOwner, // Same as owner
            initialWhitelist,
            250,
            100
        );

        assertEq(deployedEscrow.owner(), testOwner);
        assertEq(deployedEscrow.signer(), testOwner);
        assertEq(deployedEscrow.feeRecipient(), testOwner);
    }

    function test_deploy_zeroBatchLimit() public {
        address[] memory initialWhitelist = new address[](0);
        
        Escrow deployedEscrow = new Escrow(
            testOwner,
            testSigner,
            initialWhitelist,
            0,
            0 // Zero batch limit
        );

        assertEq(deployedEscrow.batchLimit(), 0);
    }

    function test_deploy_largeBatchLimit() public {
        address[] memory initialWhitelist = new address[](0);
        uint256 largeBatchLimit = type(uint256).max;
        
        Escrow deployedEscrow = new Escrow(
            testOwner,
            testSigner,
            initialWhitelist,
            0,
            largeBatchLimit
        );

        assertEq(deployedEscrow.batchLimit(), largeBatchLimit);
    }

    function test_deploy_manyWhitelistedTokens() public {
        // Create array with many tokens
        address[] memory initialWhitelist = new address[](50);
        for (uint i = 0; i < 50; i++) {
            initialWhitelist[i] = address(uint160(i + 1));
        }
        
        Escrow deployedEscrow = new Escrow(
            testOwner,
            testSigner,
            initialWhitelist,
            500,
            100
        );

        // Verify all tokens were whitelisted
        address[] memory whitelistedTokens = deployedEscrow.getAllWhitelistedTokens();
        assertEq(whitelistedTokens.length, 50);
        
        for (uint i = 0; i < 50; i++) {
            assertTrue(deployedEscrow.isTokenWhitelisted(address(uint160(i + 1))));
        }
    }

    function test_deploy_duplicateTokensInWhitelist() public {
        // Test with duplicate tokens (should revert)
        address[] memory initialWhitelist = new address[](3);
        initialWhitelist[0] = testToken1;
        initialWhitelist[1] = testToken2;
        initialWhitelist[2] = testToken1; // Duplicate
        
        expectRevert(Errors.TOKEN_ALREADY_WHITELISTED);
        new Escrow(
            testOwner,
            testSigner,
            initialWhitelist,
            250,
            100
        );
    }

    function test_deploy_domainSeparator() public {
        address[] memory initialWhitelist = new address[](0);
        
        Escrow deployedEscrow = new Escrow(
            testOwner,
            testSigner,
            initialWhitelist,
            250,
            100
        );

        bytes32 domainSeparator = deployedEscrow.DOMAIN_SEPARATOR();
        
        // Domain separator should be deterministically computed
        bytes32 expectedDomainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Escrow")),
                keccak256(bytes("1")),
                block.chainid,
                address(deployedEscrow)
            )
        );
        
        assertEq(domainSeparator, expectedDomainSeparator);
    }

    function test_deploy_constantsSetCorrectly() public {
        address[] memory initialWhitelist = new address[](0);
        
        Escrow deployedEscrow = new Escrow(
            testOwner,
            testSigner,
            initialWhitelist,
            250,
            100
        );

        // Verify constants
        assertEq(deployedEscrow.MAX_FEE(), 1000);
        
        // Verify type hashes
        bytes32 expectedSetAdminTypehash = keccak256(
            "SetAdmin(uint256 repoId,uint256 instanceId,address[] admins,uint256 nonce,uint256 signatureDeadline)"
        );
        bytes32 expectedClaimTypehash = keccak256(
            "Claim(uint256[] distributionIds,address recipient,uint256 nonce,uint256 signatureDeadline)"
        );
        
        assertEq(deployedEscrow.SET_ADMIN_TYPEHASH(), expectedSetAdminTypehash);
        assertEq(deployedEscrow.CLAIM_TYPEHASH(), expectedClaimTypehash);
    }

    function test_deploy_fuzz_validParameters(
        address _owner,
        address _signer,
        uint16 _feeBps,
        uint128 _batchLimit
    ) public {
        vm.assume(_owner != address(0));
        vm.assume(_signer != address(0));
        vm.assume(_feeBps <= 1000); // MAX_FEE_BPS
        
        address[] memory initialWhitelist = new address[](0);
        
        Escrow deployedEscrow = new Escrow(
            _owner,
            _signer,
            initialWhitelist,
            _feeBps,
            _batchLimit
        );

        assertEq(deployedEscrow.owner(), _owner);
        assertEq(deployedEscrow.signer(), _signer);
        assertEq(deployedEscrow.feeRecipient(), _owner);
        assertEq(deployedEscrow.feeOnClaim(), _feeBps);
        assertEq(deployedEscrow.batchLimit(), _batchLimit);
    }

    function test_deploy_fuzz_invalidFeeBps(uint256 _feeBps) public {
        vm.assume(_feeBps > 1000); // Above MAX_FEE_BPS
        
        address[] memory initialWhitelist = new address[](0);
        
        expectRevert(Errors.INVALID_FEE);
        new Escrow(
            testOwner,
            testSigner,
            initialWhitelist,
            _feeBps,
            100
        );
    }

    function test_deploy_zeroAddresses() public {
        address[] memory initialWhitelist = new address[](0);
        
        // Zero owner should be allowed (Owned contract doesn't check)
        Escrow deployedEscrow1 = new Escrow(
            address(0),
            testSigner,
            initialWhitelist,
            250,
            100
        );
        assertEq(deployedEscrow1.owner(), address(0));
        
        // Zero signer should be allowed
        Escrow deployedEscrow2 = new Escrow(
            testOwner,
            address(0),
            initialWhitelist,
            250,
            100
        );
        assertEq(deployedEscrow2.signer(), address(0));
        
        // Both zero should be allowed
        Escrow deployedEscrow3 = new Escrow(
            address(0),
            address(0),
            initialWhitelist,
            250,
            100
        );
        assertEq(deployedEscrow3.owner(), address(0));
        assertEq(deployedEscrow3.signer(), address(0));
    }

    function test_deploy_withRealERC20() public {
        // Deploy with actual ERC20 token from base test
        wETH = new MockERC20("Wrapped Ether", "wETH", 18);
        
        address[] memory initialWhitelist = new address[](1);
        initialWhitelist[0] = address(wETH);
        
        Escrow deployedEscrow = new Escrow(
            testOwner,
            testSigner,
            initialWhitelist,
            250,
            100
        );

        assertTrue(deployedEscrow.isTokenWhitelisted(address(wETH)));
        
        // Test that the token functions work
        assertEq(wETH.name(), "Wrapped Ether");
        assertEq(wETH.symbol(), "wETH");
        assertEq(wETH.decimals(), 18);
    }

    function test_deploy_chainIdHandling() public {
        address[] memory initialWhitelist = new address[](0);
        
        // Use a fixed, known chain ID for test determinism
        uint256 testChainId = 31337; // Anvil default
        vm.chainId(testChainId);
        
        Escrow deployedEscrow = new Escrow(
            testOwner,
            testSigner,
            initialWhitelist,
            250,
            100
        );
        
        // Get domain separator on initial chain
        bytes32 domainSeparator1 = deployedEscrow.DOMAIN_SEPARATOR();
        
        // Verify it matches the expected computation for initial chain
        bytes32 expectedOriginal = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Escrow")),
                keccak256(bytes("1")),
                testChainId,
                address(deployedEscrow)
            )
        );
        assertEq(domainSeparator1, expectedOriginal);
        
        // Change chain ID to a different value
        vm.chainId(999);
        
        bytes32 domainSeparator2 = deployedEscrow.DOMAIN_SEPARATOR();
        
        // Should be different and match expected for new chain
        bytes32 expectedNewChain = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Escrow")),
                keccak256(bytes("1")),
                999,
                address(deployedEscrow)
            )
        );
        assertEq(domainSeparator2, expectedNewChain);
        assertTrue(domainSeparator1 != domainSeparator2);
        
        // Reset chain ID back to original
        vm.chainId(testChainId);
        
        bytes32 domainSeparator3 = deployedEscrow.DOMAIN_SEPARATOR();
        
        // Should match original (uses cached INITIAL_DOMAIN_SEPARATOR) 
        assertEq(domainSeparator3, domainSeparator1);
        assertEq(domainSeparator3, expectedOriginal);
    }

    /* -------------------------------------------------------------------------- */
    /*                                    EVENTS                                  */
    /* -------------------------------------------------------------------------- */

    event WhitelistedToken(address indexed token);
}
