// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "forge-std/Test.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {SplitWithLockup} from "../../src/Payments/SplitWithLockup.sol";
import {Params}      from "../../libraries/Params.sol";
import {Deploy}      from "../../script/Deploy.s.sol";

contract Base_Test is Test {

    SplitWithLockup splitContract;

    address alice;
    address bob;

    address owner = 0x9d8A62f656a8d1615C1294fd71e9CFb3E4855A4F;

    function setUp() public {
        splitContract = new SplitWithLockup();
        splitContract.transferOwnership(owner);

        alice = makeAddr("alice");
        bob   = makeAddr("bob");
    }

    function expectRevert(string memory message) public {
        vm.expectRevert(bytes(message));
    }

    function test_setCanClaim() public {
        // these signatures are created through the create-signature.js script
        // or simply run 'npm run create-signature'
        uint8   v = 27;
        bytes32 r = 0x27f6768a2eafcaad123b2ad1bdac4fdeb8862793837bc1eddfe2755e3fe5941c;
        bytes32 s = 0x1d40a52adcd6044f7d04fee58b67c9f3fe860dc9f00d6091fbb86474f075794c;

        splitContract.setCanClaim(
            owner,
            true,
            v,
            r,
            s
        );
    }

    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                            MERKLE LOGIC
    //////////////////////////////////////////////////////////////*/
}