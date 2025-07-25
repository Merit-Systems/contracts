// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

library Errors {
    string internal constant INVALID_ADDRESS              = "Invalid Address";
    string internal constant INVALID_AMOUNT               = "Invalid Amount";
    string internal constant INVALID_TOKEN                = "Invalid Token";
    string internal constant INVALID_CLAIM_PERIOD         = "Invalid Claim Period";
    string internal constant INVALID_DISTRIBUTION_ID      = "Invalid Distribution ID";
    string internal constant ALREADY_CLAIMED              = "Already Claimed";
    string internal constant STILL_CLAIMABLE              = "Still Claimable";
    string internal constant SIGNATURE_EXPIRED            = "Signature Expired";
    string internal constant INVALID_SIGNATURE            = "Invalid Signature";
    string internal constant NO_CLAIM_PERMISSION          = "No Claim Permission";
    string internal constant TOKEN_ALREADY_WHITELISTED    = "Token Already Whitelisted";
    string internal constant TOKEN_NOT_WHITELISTED        = "Token Not Whitelisted";
    string internal constant NO_ADMIN_SET                 = "No Admin Set";
    string internal constant NOT_REPO_ADMIN               = "Not Repo Admin";
    string internal constant ARRAY_LENGTH_MISMATCH        = "Array Length Mismatch";
    string internal constant RECIPIENT_ALREADY_SET        = "Recipient Already Set";
    string internal constant RECIPIENT_NOT_SET            = "Recipient Not Set";
    string internal constant INVALID_FEE                  = "Invalid Fee";
    string internal constant INSUFFICIENT_BALANCE         = "Insufficient Balance";
    string internal constant INVALID_CLAIM_ID             = "Invalid Claim ID";
    string internal constant CLAIM_DEADLINE_PASSED        = "Claim Deadline Passed";
    string internal constant REPO_HAS_DISTRIBUTIONS       = "Repo Has Distributions";
    string internal constant DISTRIBUTOR_ALREADY_AUTHORIZED = "Distributor Already Authorized";
    string internal constant DISTRIBUTOR_NOT_AUTHORIZED     = "Distributor Not Authorized";
    string internal constant INVALID_RECIPIENT              = "Invalid Recipient";
    string internal constant NOT_REPO_DISTRIBUTION          = "Not Repo Distribution";
    string internal constant NOT_DIRECT_DISTRIBUTION        = "Not Direct Distribution";
    string internal constant NOT_ORIGINAL_PAYER             = "Not Original Payer";
    string internal constant NOT_AUTHORIZED_DISTRIBUTOR     = "Not Authorized Distributor";
    string internal constant NOT_REPO_ADMIN_OR_DISTRIBUTOR  = "Not Repo Admin Or Distributor";
    string internal constant REPO_ALREADY_INITIALIZED       = "Repo Already Initialized";
    string internal constant BATCH_LIMIT_EXCEEDED           = "Batch Limit Exceeded";
    string internal constant CANNOT_REMOVE_ALL_ADMINS       = "Cannot Remove All Admins";
    string internal constant DISTRIBUTION_NOT_FROM_REPO     = "Distribution Not From Repo";
    string internal constant EMPTY_ARRAY                    = "Empty Array";
    string internal constant INSUFFICIENT_FUNDS             = "Insufficient Funds";
} 