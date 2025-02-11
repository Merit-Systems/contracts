// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import {Owned} from "solmate/auth/Owned.sol";

contract Oracle is Owned {

    mapping(address => uint) public unlocked;

    constructor() Owned(msg.sender) {}

    function unlock(address to, uint amount) public onlyOwner {
        unlocked[to] = amount;
    }
}