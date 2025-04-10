// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "forge-std/Test.sol";

import {MockERC20}         from "solmate/test/utils/mocks/MockERC20.sol";
import {ERC20}             from "solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {Escrow}        from "../src/Escrow.sol";
import {DepositParams} from "../interface/IEscrow.sol";
import {Params}        from "../libraries/Params.sol";
import {Deploy}        from "../script/Deploy.s.sol";
import {Errors}        from "../libraries/Errors.sol";

contract Base_Test is Test {
    using FixedPointMathLib for uint256;

    Escrow escrow;

    address alice;
    address bob;

    uint256 ownerPrivateKey = 0x4646464646464646464646464646464646464646464646464646464646464646;
    address owner           = vm.addr(ownerPrivateKey);

    MockERC20 wETH = new MockERC20("Wrapped Ether", "wETH", 18);

    function setUp() public {
        address[] memory initialWhitelistedTokens = new address[](1);
        initialWhitelistedTokens[0] = address(wETH);
        escrow = new Deploy().deploy(owner, initialWhitelistedTokens, Params.BASE_FEE_BPS);

        alice = makeAddr("alice");
        bob   = makeAddr("bob");
    }

    function expectRevert(string memory message) public {
        vm.expectRevert(bytes(message));
    }

    function test_deposit() public {
        uint amount = 1000000000000000000;
        uint depositId = deposit(amount, alice);
        assertEq(wETH.balanceOf(address(escrow)), 997500000000000000);
        assertEq(depositId, 0);
    }

     function test_fuzz_deposit(uint amount) public {
        vm.assume(amount > 1e6 && amount < 1e32);
        uint depositId = deposit(amount, alice);
        assertEq(wETH.balanceOf(address(escrow)), amount - (amount.mulDivDown(Params.BASE_FEE_BPS, 10_000)));
        assertEq(depositId, 0);
    }

    function test_deposit_1_USDC() public {
        uint amount = 1e6;
        uint depositId = deposit(amount, alice);
        assertEq(wETH.balanceOf(address(escrow)), 997500);
        assertEq(depositId, 0);
    }

    function test_claim() public {
        uint depositId = deposit(1000000000000000000, alice);
        (uint8 v, bytes32 r, bytes32 s) = generateSignature(alice, true);
        escrow.claim(depositId, alice, true, 1 days, v, r, s);
        assertEq(wETH.balanceOf(alice), 997500000000000000);
    }

    function test_reclaim() public {
        uint depositId = deposit(1000000000000000000, alice);
        vm.warp(block.timestamp + 2 days);
        assertEq(wETH.balanceOf(bob), 0);
        escrow.reclaim(depositId);
        assertEq(wETH.balanceOf(bob), 997500000000000000);
    }

    function test_batchReclaim() public {
        uint[] memory depositIds = new uint[](1);
        depositIds[0] = deposit(1000000000000000000, alice);
        vm.warp(block.timestamp + 2 days);
        assertEq(wETH.balanceOf(bob), 0);
        escrow.batchReclaim(depositIds);
        assertEq(wETH.balanceOf(bob), 997500000000000000);
    }

    function deposit(uint amount, address recipient) public returns (uint depositId) {
        wETH.mint(address(this), amount);
        wETH.approve(address(escrow), amount);

        DepositParams[] memory params = new DepositParams[](1);
        params[0] = DepositParams({
            token:       wETH,
            sender:      bob,
            recipient:   recipient,
            amount:      amount,
            claimPeriod: 1 days
        });
        return escrow.deposit(params[0]);
    }

    function generateSignature(address recipient, bool status) public view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 structHash = keccak256(
            abi.encode(
                escrow.CLAIM_TYPEHASH(),
                recipient,
                status,
                escrow.recipientNonces(recipient),
                1 days
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", escrow.CLAIM_DOMAIN_SEPARATOR(), structHash)
        );
    
        (v, r, s) = vm.sign(ownerPrivateKey, digest);
    }
}