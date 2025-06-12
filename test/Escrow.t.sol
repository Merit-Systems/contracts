// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "forge-std/Test.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {ERC20}     from "solmate/tokens/ERC20.sol";

import {Escrow}        from "../src/Escrow.sol";
import {Deploy}        from "../script/Deploy.Core.s.sol";
import {Errors}        from "../libraries/Errors.sol";
import {Params}        from "../libraries/Params.sol";

contract Base_Test is Test {

    Escrow escrow;

    address alice;
    address bob;

    uint256 ownerPrivateKey = 0x4646464646464646464646464646464646464646464646464646464646464646;
    address owner           = vm.addr(ownerPrivateKey);

    MockERC20 wETH = new MockERC20("Wrapped Ether", "wETH", 18);

    function setUp() public {
        address[] memory initialWhitelistedTokens = new address[](1);
        initialWhitelistedTokens[0] = address(wETH);
        escrow = new Deploy().deploy(
            owner,
            owner,
            initialWhitelistedTokens,
            250,
            Params.BATCH_LIMIT
        );

        alice = makeAddr("alice");
        bob   = makeAddr("bob");
    }

    function expectRevert(string memory message) public {
        vm.expectRevert(bytes(message));
    }

    function test_deploy() public view {
        assertEq(escrow.owner(),        owner);
        assertEq(escrow.signer(),       owner);
        assertEq(escrow.fee(),          250);
        assertEq(escrow.batchLimit(),   Params.BATCH_LIMIT);
        assertEq(escrow.feeRecipient(), owner);
        
        // Check constants
        assertEq(escrow.MAX_FEE_BPS(), 1000);
        
        // Check whitelist functionality
        assertTrue(escrow.isTokenWhitelisted(address(wETH)));
        assertFalse(escrow.isTokenWhitelisted(address(0)));
        
        address[] memory whitelistedTokens = escrow.getAllWhitelistedTokens();
        assertEq(whitelistedTokens.length, 1);
        assertEq(whitelistedTokens[0], address(wETH));
        
        // Check domain separator is set
        assertTrue(escrow.DOMAIN_SEPARATOR() != bytes32(0));
    }
}