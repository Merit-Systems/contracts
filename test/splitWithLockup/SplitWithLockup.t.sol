// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "forge-std/Test.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {ERC20}     from "solmate/tokens/ERC20.sol";

import {SplitWithLockup, SplitParams} from "../../src/Payments/SplitWithLockup.sol";
import {Params}      from "../../libraries/Params.sol";
import {Deploy}      from "../../script/Deploy.s.sol";

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
}