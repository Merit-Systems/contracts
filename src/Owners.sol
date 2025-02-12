// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import {ERC721} from "solmate/tokens/ERC721.sol";
import {Owned}  from "solmate/auth/Owned.sol";

contract Owners is ERC721, Owned {

    constructor() ERC721("Repo Owners", "RO") Owned(msg.sender) {

    }

    function mint(address to) public onlyOwner returns (uint) {
        _mint(to, 99); // TODO: use er721 enumerable
        return 99;
    }

    function tokenURI(uint256 id) public pure override returns (string memory) {
        return string(abi.encodePacked("https://api.merit.systems/owner/", id));
    }

}