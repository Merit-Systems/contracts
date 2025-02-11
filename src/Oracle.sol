// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import {Owned} from "solmate/auth/Owned.sol";

contract Oracle is Owned {

    constructor() Owned(msg.sender) {}

}