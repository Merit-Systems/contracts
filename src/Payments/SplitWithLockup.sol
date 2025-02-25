// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20}           from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

contract SplitWithLockup {
    using SafeTransferLib for ERC20;

    struct Deposit {
        uint    amount;
        ERC20   token;
        address recipient;
        address sender;
        uint    claimDeadline;
        bool    claimed;
    }

    uint public depositCount;
    mapping(uint => Deposit) public deposits;

    struct SplitParams {
        address recipient;
        uint    value;
        bool    canTransferNow;
        uint    claimPeriod;
        address sender;
    }

    function split(
        ERC20 token,
        SplitParams[] calldata params
    ) external {
        for (uint256 i = 0; i < params.length; i++) {
            if (params[i].canTransferNow) {
                token.safeTransferFrom(msg.sender, params[i].recipient, params[i].value);
            } else {
                token.safeTransferFrom(msg.sender, address(this), params[i].value);

                deposits[depositCount++] = Deposit({
                    amount:        params[i].value,
                    token:         token,
                    recipient:     params[i].recipient,
                    sender:        params[i].sender,
                    claimDeadline: block.timestamp + params[i].claimPeriod,
                    claimed:       false
                });

                depositCount++;
            }
        }
    }

    function claim(uint depositId) external {
        Deposit storage deposit = deposits[depositId];

        require(!deposit.claimed);
        require(block.timestamp <= deposit.claimDeadline);

        deposit.claimed = true;
        deposit.token.safeTransfer(deposit.recipient, deposit.amount);
    }

    function reclaim(uint depositId) external {
        Deposit storage deposit = deposits[depositId];

        require(!deposit.claimed);
        require(block.timestamp > deposit.claimDeadline);

        deposit.claimed = true;
        deposit.token.safeTransfer(deposit.sender, deposit.amount);
    }
}
