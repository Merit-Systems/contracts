// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {Owners} from "./Owners.sol";
import {Vault} from "./Vault.sol";

contract VaultFactory {

    Owners public owners;

    constructor(Owners _owners) {
        owners = _owners;
    }

    // function createVault(address owner, ERC20 asset) public returns (Vault vault) {
    //     uint _owner = owners.mint(owner, 2);
    //     return new Vault(owners, _owner, asset, "", "");
    // }
}