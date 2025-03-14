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

    address owner = 0x9d8A62f656a8d1615C1294fd71e9CFb3E4855A4F;

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

        wETH.mint(address(this), amount);
        wETH.approve(address(splitContract), amount);

        SplitParams[] memory params = new SplitParams[](1);
        params[0] = SplitParams({
            token:       wETH,
            sender:      bob,
            recipient:   alice,
            amount:      amount,
            claimPeriod: 1 days
        });
        splitContract.split(params);
    }

    function test_setCanClaim() public {
        uint256 privateKey = 0x4646464646464646464646464646464646464646464646464646464646464646;
        address signer = vm.addr(privateKey);

        assertEq(signer, owner);

        bytes32 domainSeparator = splitContract.CLAIM_DOMAIN_SEPARATOR();
        bytes32 CLAIM_TYPEHASH = splitContract.CLAIM_TYPEHASH();

        bytes32 structHash = keccak256(
            abi.encode(
                CLAIM_TYPEHASH,
                owner, // recipient 
                true,  // status
                0      // nonce
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );
    
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        splitContract.setCanClaim(
            owner,
            true,
            v,
            r,
            s
        );

        assertEq(splitContract.canClaim(owner), true);
    }
}