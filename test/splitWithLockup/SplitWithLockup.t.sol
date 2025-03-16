// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "forge-std/Test.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {ERC20}     from "solmate/tokens/ERC20.sol";

import {SplitWithLockup, DepositParams} from "../../src/Payments/SplitWithLockup.sol";
import {Params}      from "../../libraries/Params.sol";
import {Deploy}      from "../../script/Deploy.s.sol";
import {Errors}      from "../../libraries/Errors.sol";
import {DeploySplitWithLockup} from "../../script/Deploy.SplitWithLockup.sol";

contract Base_Test is Test {

    SplitWithLockup splitContract;

    address alice;
    address bob;

    uint256 ownerPrivateKey = 0x4646464646464646464646464646464646464646464646464646464646464646;
    address owner            = vm.addr(ownerPrivateKey);

    MockERC20 wETH = new MockERC20("Wrapped Ether", "wETH", 18);

    function setUp() public {
        address[] memory initialWhitelistedTokens = new address[](1);
        initialWhitelistedTokens[0] = address(wETH);
        splitContract = new DeploySplitWithLockup().run(owner, initialWhitelistedTokens);

        alice = makeAddr("alice");
        bob   = makeAddr("bob");
    }

    function expectRevert(string memory message) public {
        vm.expectRevert(bytes(message));
    }

    function test_deposit() public {
        uint amount = 1000000000000000000;
        uint depositId = deposit(amount, alice);
        assertEq(wETH.balanceOf(address(splitContract)), amount);
        assertEq(depositId, 0);
    }

    function test_setCanClaim() public {
        setCanClaim(alice, true);
        assertEq(splitContract.canClaim(alice), true);
    }

    function test_claim() public {
        uint depositId = deposit(1000000000000000000, alice);
        (uint8 v, bytes32 r, bytes32 s) = generateSignature(alice, true);
        splitContract.claim(depositId, alice, true, v, r, s);
        assertEq(wETH.balanceOf(alice), 1000000000000000000);
    }

    function test_claimTwice() public {
        uint depositId = deposit(1000000000000000000, alice);
        (uint8 v, bytes32 r, bytes32 s) = generateSignature(alice, true);
        splitContract.claim(depositId, alice, true, v, r, s);

        uint depositId2 = deposit(1000000000000000000, alice);
        (v, r, s) = generateSignature(alice, true);
        splitContract.claim(depositId2, alice, true, v, r, s);
    }

    function test_claim_failAlreadyClaimed() public {
        uint depositId = deposit(1000000000000000000, alice);
        (uint8 v, bytes32 r, bytes32 s) = generateSignature(alice, true);
        splitContract.claim(depositId, alice, true, v, r, s);
        expectRevert(Errors.ALREADY_CLAIMED);
        splitContract.claim(depositId, alice, true, v, r, s);
    }

    function test_reclaim() public {
        uint depositId = deposit(1000000000000000000, alice);
        vm.warp(block.timestamp + 2 days);
        assertEq(wETH.balanceOf(bob), 0);
        splitContract.reclaim(depositId);
        assertEq(wETH.balanceOf(bob), 1000000000000000000);
    }

    function test_reclaim_failStillClaimable() public {
        uint depositId = deposit(1000000000000000000, alice);
        expectRevert(Errors.STILL_CLAIMABLE);
        splitContract.reclaim(depositId);
    }

    function test_reclaim_failAlreadyClaimed() public {
        uint depositId = deposit(1000000000000000000, alice);
        vm.warp(block.timestamp + 2 days);
        splitContract.reclaim(depositId);
        expectRevert(Errors.ALREADY_CLAIMED);
        splitContract.reclaim(depositId);
    }

    function test_batchReclaim() public {
        uint[] memory depositIds = new uint[](1);
        depositIds[0] = deposit(1000000000000000000, alice);
        vm.warp(block.timestamp + 2 days);
        assertEq(wETH.balanceOf(bob), 0);
        splitContract.batchReclaim(depositIds);
        assertEq(wETH.balanceOf(bob), 1000000000000000000);
    }

    function deposit(uint amount, address recipient) public returns (uint depositId) {
        wETH.mint(address(this), amount);
        wETH.approve(address(splitContract), amount);

        DepositParams[] memory params = new DepositParams[](1);
        params[0] = DepositParams({
            token:       wETH,
            sender:      bob,
            recipient:   recipient,
            amount:      amount,
            claimPeriod: 1 days
        });
        return splitContract.deposit(params[0]);
    }

    function setCanClaim(address recipient, bool status) public {
        bytes32 structHash = keccak256(
            abi.encode(
                splitContract.CLAIM_TYPEHASH(),
                recipient, 
                status,  
                0
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", splitContract.CLAIM_DOMAIN_SEPARATOR(), structHash)
        );
    
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        splitContract.setCanClaim(
            recipient,
            status,
            v,
            r,
            s
        );
    }

    function generateSignature(address recipient, bool status) public view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 structHash = keccak256(
            abi.encode(
                splitContract.CLAIM_TYPEHASH(),
                recipient,
                status,
                splitContract.recipientNonces(recipient)
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", splitContract.CLAIM_DOMAIN_SEPARATOR(), structHash)
        );
    
        (v, r, s) = vm.sign(ownerPrivateKey, digest);
    }
}