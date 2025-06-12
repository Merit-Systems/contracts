// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

library Errors {
    string internal constant NOT_OWNER                    = "Not Owner";
    string internal constant ALREADY_CLAIMED              = "Already Claimed";
    string internal constant NO_CLAIM_PERMISSION          = "No Payment Permission";
    string internal constant CLAIM_EXPIRED                = "Claim Expired";
    string internal constant STILL_CLAIMABLE              = "Still Claimable";
    string internal constant INVALID_SIGNATURE            = "Invalid Signature";
    string internal constant INVALID_ADDRESS              = "Invalid Address";
    string internal constant INVALID_AMOUNT               = "Invalid Amount";
    string internal constant INVALID_CLAIM_PERIOD         = "Invalid Claim Period";
    string internal constant INVALID_RECIPIENT            = "Invalid Recipient";
    string internal constant TOKEN_NOT_WHITELISTED        = "Token Not Whitelisted";
    string internal constant TOKEN_ALREADY_WHITELISTED    = "Token Already Whitelisted";
    string internal constant SIGNATURE_EXPIRED            = "Signature Expired";
    string internal constant INVALID_DEPOSIT_ID           = "Invalid Deposit ID";
    string internal constant INVALID_TOKEN                = "Invalid Token";
    string internal constant INVALID_FEE                  = "Invalid Fee";
    string internal constant INVALID_AMOUNT_AFTER_FEE     = "Invalid Amount After Fee";
    string internal constant INVALID_BATCH_DEPOSIT_LIMIT  = "Invalid Batch Deposit Limit";
    string internal constant BATCH_DEPOSIT_LIMIT_EXCEEDED = "Batch Deposit Limit Exceeded";
    string internal constant EMPTY_BATCH                  = "Empty Batch";
}
