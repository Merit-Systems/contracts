// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "forge-std/Test.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {MeritLedger} from "src/MeritLedger.sol";
import {Params}      from "libraries/Params.sol";
import {Deploy}      from "../script/Deploy.s.sol";

contract Base_Test is Test {

    MeritLedger ledger;
    MockERC20   usdc;

    address alice;
    address bob;

    function setUp() public {
        usdc   = new MockERC20("USDC", "USDC", 6);
        ledger = new MeritLedger(usdc);
        ledger.transferOwnership(Params.OWNER);

        alice = makeAddr("alice");
        bob   = makeAddr("bob");
    }

    function expectRevert(string memory message) public {
        vm.expectRevert(bytes(message));
    }

    function init() internal returns (uint) {
        uint repoId = 0;

        address[] memory contributors = new address[](2);
        contributors[0] = alice;
        contributors[1] = bob;

        uint   [] memory shares       = new uint   [](2);
        shares[0] = 100e18;
        shares[1] = 200e18;

        uint dilutionRate = 1_000;

        vm.prank(Params.OWNER);
        ledger.init(repoId, alice, contributors, shares, dilutionRate);
        return repoId;
    }

    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier _init() {
        init();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            MERKLE LOGIC
    //////////////////////////////////////////////////////////////*/
    function getSingleLeafRootAndProof(
        uint index,
        address account,
        uint amount
    )
        internal
        pure
        returns (bytes32 root, bytes32[] memory proof)
    {
        root = keccak256(abi.encodePacked(index, account, amount));
        proof = new bytes32[](0); // empty proof for single-leaf tree
    }
}