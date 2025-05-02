// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

library Params {
    bytes32 constant SALT = 0xc710b407f46823cbbdbde6d344b8992c3062012fa3e11e4cea5ddb5bdb0000c4;
    uint    constant BATCH_DEPOSIT_LIMIT = 500;

    /*//////////////////////////////////////////////////////////////
                                  BASE
    //////////////////////////////////////////////////////////////*/
    address constant BASE_OWNER   = 0x7163a6C74a3caB2A364F9aDD054bf83E50A1d8Bc;
    address constant BASE_SIGNER  = 0x7F26a8d1A94bD7c1Db651306f503430dF37E9037;
    address constant BASE_USDC    = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    uint    constant BASE_FEE_BPS = 250;

    /*//////////////////////////////////////////////////////////////
                                SEPOLIA
    //////////////////////////////////////////////////////////////*/
    address constant SEPOLIA_OWNER        = 0x9d8A62f656a8d1615C1294fd71e9CFb3E4855A4F;
    address constant SEPOLIA_SIGNER       = 0x9d8A62f656a8d1615C1294fd71e9CFb3E4855A4F;
    address constant SEPOLIA_WETH         = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
    address constant SEPOLIA_USDC         = 0x947982FbF3bce76a2ea27797f992d388F7AdD44E;
    address constant SEPOLIA_TESTER       = 0x99ecA80b4Ebf8fDACe6627BEcb75EF1e620E6956;
    address constant SEPOLIA_TESTER_JSON  = 0x5C87eA705eE49a96532F45f5db606A5f5fEF9780;
    address constant SEPOLIA_TESTER_SHAFU = 0x39053B170bBD9580d0b86e8317c685aEFB65f1ec;
    uint    constant SEPOLIA_FEE_BPS      = 0;

    /*//////////////////////////////////////////////////////////////
                              BASE SEPOLIA
    //////////////////////////////////////////////////////////////*/
    address constant BASESEPOLIA_OWNER        = 0x9d8A62f656a8d1615C1294fd71e9CFb3E4855A4F;
    address constant BASESEPOLIA_SIGNER       = 0x9d8A62f656a8d1615C1294fd71e9CFb3E4855A4F;
    address constant BASESEPOLIA_WETH         = 0x4200000000000000000000000000000000000006;
    address constant BASESEPOLIA_USDC         = 0x081827b8C3Aa05287b5aA2bC3051fbE638F33152;
    address constant BASESEPOLIA_TESTER       = 0x5C87eA705eE49a96532F45f5db606A5f5fEF9780;
    address constant BASESEPOLIA_TESTER_SHAFU = 0x39053B170bBD9580d0b86e8317c685aEFB65f1ec;
    address constant BASESEPOLIA_TESTER_JSON  = 0x5C87eA705eE49a96532F45f5db606A5f5fEF9780;
    uint    constant BASESEPOLIA_FEE_BPS      = 0;
}
