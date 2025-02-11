// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import {ERC4626} from "solmate/tokens/ERC4626.sol";
import {ERC20}   from "solmate/tokens/ERC20.sol";

import {Owners} from "./Owners.sol";

contract Vault is ERC4626 {

    constructor(
        uint ownerId, 
        ERC20 _asset,
        string memory _name,
        string memory _symbol
    ) ERC4626(_asset, _name, _symbol) {}

    function totalAssets() public override view returns (uint256) {
        return asset.balanceOf(address(this));
    }

}