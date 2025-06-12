// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "forge-std/Test.sol";
import {MockERC20}  from "solmate/test/utils/mocks/MockERC20.sol";
import {DeployBase} from "../script/Deploy.Base.s.sol";
import {Params}     from "../libraries/Params.sol";
import {Escrow}     from "../src/Escrow.sol";

contract Deploy_Test is Test {
    DeployBase deployer;

    function setUp() public {
        deployer = new DeployBase();
    }

    function test_deploy() public {
        Escrow escrow = deployer.run();

        assertTrue(address(escrow) != address(0),               "Escrow not deployed");
        assertTrue(escrow.isTokenWhitelisted(Params.BASE_USDC), "WETH not whitelisted");

        assertEq  (escrow.owner(),             Params.BASE_OWNER,               "Incorrect owner");
        assertEq  (escrow.signer(),            Params.BASE_SIGNER,              "Incorrect signer");
        assertEq  (escrow.feeRecipient(),      Params.BASE_OWNER,               "Incorrect fee recipient");
        assertEq  (escrow.protocolFeeBps(),    Params.BASE_FEE_BPS,        "Incorrect fee");
        assertEq  (escrow.batchDepositLimit(), Params.BATCH_DEPOSIT_LIMIT, "Incorrect batch deposit limit");
    }
}
