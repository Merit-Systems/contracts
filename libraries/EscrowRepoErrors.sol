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
    string internal constant ARRAY_LENGTH_MISMATCH        = "Array Length Mismatch";
    string internal constant RECIPIENT_ALREADY_SET        = "Recipient Already Set";
    string internal constant REPO_ALREADY_EXISTS          = "Repo Already Exists";
    string internal constant RECIPIENT_NOT_SET            = "Recipient Not Set";
    string internal constant INVALID_FEE_BPS              = "Invalid Fee BPS";
    string internal constant INSUFFICIENT_POOL_BALANCE    = "Insufficient Pool Balance";
    string internal constant INVALID_CLAIM_ID             = "Invalid Claim ID";
    string internal constant CLAIM_DEADLINE_PASSED        = "Claim Deadline Passed";
    string internal constant REPO_HAS_DEPOSITS            = "Repo Has Deposits";
    string internal constant DEPOSITOR_ALREADY_AUTHORIZED = "Depositor Already Authorized";
    string internal constant DEPOSITOR_NOT_AUTHORIZED     = "Depositor Not Authorized";
} 