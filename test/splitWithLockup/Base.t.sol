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
        splitContract = new SplitWithLockup(owner);
        splitContract.transferOwnership(owner);

        alice = makeAddr("alice");
        bob   = makeAddr("bob");
    }

    function expectRevert(string memory message) public {
        vm.expectRevert(bytes(message));
    }

    function test_signature() public {
        console.log("chainId", block.chainid);
        console.log("splitContract", address(splitContract));
        // these signatures are created through the signer-eip712 repo
        // uint8   v = 27;
        // bytes32 r = 0x27f6768a2eafcaad123b2ad1bdac4fdeb8862793837bc1eddfe2755e3fe5941c;
        // bytes32 s = 0x1d40a52adcd6044f7d04fee58b67c9f3fe860dc9f00d6091fbb86474f075794c;

        uint8   v = 27;
        bytes32 r = 0xfc80a6fd7f4c3ec22de3d25ff4f2d8a2cdf4e7263241bfb7588ba25eb4df601e;
        bytes32 s = 0x71c27aa9a159de9fef417ae13f6301d37771d098f03a223bde832cda0c64c168;

        splitContract.setCanClaim(
            // owner,
            0x99ecA80b4Ebf8fDACe6627BEcb75EF1e620E6956,
            true,
            v,
            r,
            s
        );
    }
}