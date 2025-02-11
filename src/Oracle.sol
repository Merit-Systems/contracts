// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

contract Oracle {

    address public immutable admin;
    address public immutable vault;

    mapping(address => uint) public unlocked;
    mapping(address => uint) public claimed;

    constructor(address _admin, address _vault) {
        admin = _admin;
        vault = _vault;
    }

    // called by us
    function updateUnlocked(address to, uint newAmount) public {
        require(msg.sender == admin);
        unlocked[to] += newAmount;
    }

    // called by vault
    function updateClaimed(address to, uint newAmount) public {
        require(msg.sender == vault);
        claimed[to] += newAmount;
    }
}