// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

library Errors {
    string internal constant INVALID_ADDRESS              = "Invalid Address";
    string internal constant INVALID_AMOUNT               = "Invalid Amount";
    string internal constant INVALID_TOKEN                = "Invalid Token";
    string internal constant INVALID_CLAIM_PERIOD         = "Invalid Claim Period";
    string internal constant INVALID_DEPOSIT_ID           = "Invalid Deposit ID";
    string internal constant ALREADY_CLAIMED              = "Already Claimed";
    string internal constant STILL_CLAIMABLE              = "Still Claimable";
    string internal constant SIGNATURE_EXPIRED            = "Signature Expired";
    string internal constant INVALID_SIGNATURE            = "Invalid Signature";
    string internal constant NO_CLAIM_PERMISSION          = "No Claim Permission";
    string internal constant TOKEN_ALREADY_WHITELISTED    = "Token Already Whitelisted";
    string internal constant TOKEN_NOT_WHITELISTED        = "Token Not Whitelisted";
    string internal constant REPO_EXISTS                  = "Repo Exists";
    string internal constant REPO_UNKNOWN                 = "Repo Unknown";
    string internal constant NOT_REPO_ADMIN               = "Not Repo Admin";
} 