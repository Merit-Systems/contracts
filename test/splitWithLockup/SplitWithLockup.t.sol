// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "forge-std/Test.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {ERC20}     from "solmate/tokens/ERC20.sol";

import {SplitWithLockup, SplitParams} from "../../src/Payments/SplitWithLockup.sol";
import {Params}      from "../../libraries/Params.sol";
import {Deploy}      from "../../script/Deploy.s.sol";
import {Errors}      from "../../libraries/Errors.sol";

contract Base_Test is Test {

    SplitWithLockup splitContract;

    address alice;
    address bob;

    uint256 ownerPrivateKey = 0x4646464646464646464646464646464646464646464646464646464646464646;
    address owner            = vm.addr(ownerPrivateKey);

    MockERC20 wETH = new MockERC20("Wrapped Ether", "wETH", 18);

    function setUp() public {
        splitContract = new SplitWithLockup(owner);

        alice = makeAddr("alice");
        bob   = makeAddr("bob");
    }

    function expectRevert(string memory message) public {
        vm.expectRevert(bytes(message));
    }

    function test_split() public {
        uint amount = 1000000000000000000;
        uint[] memory depositIds = split(amount, alice);
        assertEq(wETH.balanceOf(address(splitContract)), amount);
        assertEq(depositIds.length, 1);
        assertEq(depositIds[0], 0);
    }

    function test_setCanClaim() public {
        setCanClaim(alice, true);
        assertEq(splitContract.canClaim(alice), true);
    }

    function test_claim() public {
        uint[] memory depositIds = split(1000000000000000000, alice);
        (uint8 v, bytes32 r, bytes32 s) = generateSignature(alice, true);
        splitContract.claimWithSignature(depositIds[0], alice, true, v, r, s);
        assertEq(wETH.balanceOf(alice), 1000000000000000000);
    }

    function test_claimTwice() public {
        uint[] memory depositIds = split(1000000000000000000, alice);
        (uint8 v, bytes32 r, bytes32 s) = generateSignature(alice, true);
        splitContract.claimWithSignature(depositIds[0], alice, true, v, r, s);

        uint[] memory depositIds2 = split(1000000000000000000, alice);
        (v, r, s) = generateSignature(alice, true);
        splitContract.claimWithSignature(depositIds2[0], alice, true, v, r, s);
    }

    function test_claim_failAlreadyClaimed() public {
        uint[] memory depositIds = split(1000000000000000000, alice);
        (uint8 v, bytes32 r, bytes32 s) = generateSignature(alice, true);
        splitContract.claimWithSignature(depositIds[0], alice, true, v, r, s);
        expectRevert(Errors.ALREADY_CLAIMED);
        splitContract.claimWithSignature(depositIds[0], alice, true, v, r, s);
    }

    function test_reclaim() public {
        uint[] memory depositIds = split(1000000000000000000, alice);
        vm.warp(block.timestamp + 2 days);
        assertEq(wETH.balanceOf(bob), 0);
        splitContract.reclaim(depositIds[0]);
        assertEq(wETH.balanceOf(bob), 1000000000000000000);
    }

    function test_reclaim_failStillClaimable() public {
        uint[] memory depositIds = split(1000000000000000000, alice);
        expectRevert(Errors.STILL_CLAIMABLE);
        splitContract.reclaim(depositIds[0]);
    }

    function test_reclaim_failAlreadyClaimed() public {
        uint[] memory depositIds = split(1000000000000000000, alice);
        vm.warp(block.timestamp + 2 days);
        splitContract.reclaim(depositIds[0]);
        expectRevert(Errors.ALREADY_CLAIMED);
        splitContract.reclaim(depositIds[0]);
    }

    function test_batchReclaim() public {
        uint[] memory depositIds = split(1000000000000000000, alice);
        vm.warp(block.timestamp + 2 days);
        assertEq(wETH.balanceOf(bob), 0);
        splitContract.batchReclaim(depositIds);
        assertEq(wETH.balanceOf(bob), 1000000000000000000);
    }

    function split(uint amount, address recipient) public returns (uint[] memory depositIds) {
        wETH.mint(address(this), amount);
        wETH.approve(address(splitContract), amount);

        SplitParams[] memory params = new SplitParams[](1);
        params[0] = SplitParams({
            token:       wETH,
            sender:      bob,
            recipient:   recipient,
            amount:      amount,
            claimPeriod: 1 days
        });
        return splitContract.split(params);
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