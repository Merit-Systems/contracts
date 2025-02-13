// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

library Errors {
    string internal constant NOT_OWNER            = "Not Owner";
    string internal constant NOT_SUPPORTED        = "Not Supported";
    string internal constant ALREADY_INITIALIZED  = "Already Initialized";
    string internal constant LENGTH_MISMATCH      = "Length Mismatch";
    string internal constant ZERO_SHARE           = "Zero Share";
    string internal constant NO_TIME_ELAPSED      = "No Time Elapsed";
    string internal constant NO_NEW_MINTED_SHARES = "No New Minted Shares";
    string internal constant NO_PULL_REQUESTS     = "No Pull Requests";
    string internal constant NO_WEIGHTS           = "No Weights";
    string internal constant NOT_INITIALIZED      = "Not Initialized";
    string internal constant NOT_ACCOUNT          = "Not Account";
    string internal constant ALREADY_CLAIMED      = "Already Claimed";
    string internal constant INVALID_PROOF        = "Invalid Proof";
    string internal constant INVALID_ROOT         = "Invalid Root";
}