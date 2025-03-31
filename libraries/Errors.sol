// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

library Errors {
    string internal constant NOT_OWNER                 = "Not Owner";
    string internal constant NOT_SUPPORTED             = "Not Supported";
    string internal constant ALREADY_INITIALIZED       = "Already Initialized";
    string internal constant LENGTH_MISMATCH           = "Length Mismatch";
    string internal constant ZERO_SHARE                = "Zero Share";
    string internal constant NO_TIME_ELAPSED           = "No Time Elapsed";
    string internal constant NO_NEW_MINTED_SHARES      = "No New Minted Shares";
    string internal constant NO_PULL_REQUESTS          = "No Pull Requests";
    string internal constant NO_WEIGHTS                = "No Weights";
    string internal constant NOT_INITIALIZED           = "Not Initialized";
    string internal constant NOT_ACCOUNT_OWNER         = "Not Account Owner";
    string internal constant ALREADY_CLAIMED           = "Already Claimed";
    string internal constant INVALID_PROOF             = "Invalid Proof";
    string internal constant INVALID_ROOT              = "Invalid Root";
    string internal constant NO_CONTRIBUTORS           = "No Contributors";
    string internal constant TOO_MANY_CONTRIBUTORS     = "Too Many Contributors";
    string internal constant TOO_MANY_PULL_REQUESTS    = "Too Many Pull Requests";
    string internal constant NO_PAYMENT_PERMISSION     = "No Payment Permission";
    string internal constant CLAIM_EXPIRED             = "Claim Expired";
    string internal constant STILL_CLAIMABLE           = "Still Claimable";
    string internal constant INVALID_SIGNATURE         = "Invalid Signature";
    string internal constant INVALID_ADDRESS           = "Invalid Address";
    string internal constant INVALID_AMOUNT            = "Invalid Amount";
    string internal constant INVALID_CLAIM_PERIOD      = "Invalid Claim Period";
    string internal constant INVALID_RECIPIENT         = "Invalid Recipient";
    string internal constant TOKEN_NOT_WHITELISTED     = "Token Not Whitelisted";
    string internal constant TOKEN_ALREADY_WHITELISTED = "Token Already Whitelisted";
    string internal constant SIGNATURE_EXPIRED         = "Signature Expired";
    string internal constant INVALID_DEPOSIT_ID        = "Invalid Deposit ID";
    string internal constant INVALID_TOKEN             = "Invalid Token";
    string internal constant INVALID_FEE               = "Invalid Fee";
    string internal constant INVALID_AMOUNT_AFTER_FEE  = "Invalid Amount After Fee";
}
