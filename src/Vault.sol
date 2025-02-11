// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import {ERC4626} from "solmate/tokens/ERC4626.sol";
import {ERC20}   from "solmate/tokens/ERC20.sol";

import {Owners} from "./Owners.sol";
import {Errors} from "../libraries/Errors.sol";

contract Vault is ERC4626 {

    Owners public immutable owners;
    uint   public immutable ownerId;

    struct PullRequest {
        address owner;
        uint    score;
        uint    deadline;
    }

    modifier onlyOwner() {
        require(msg.sender == owners.ownerOf(ownerId), Errors.NOT_OWNER);
        _;
    }

    constructor(
        Owners        _owners,
        uint          _ownerId, 
        ERC20         _asset,
        string memory _name,
        string memory _symbol
    ) ERC4626(_asset, _name, _symbol) {
        owners  = _owners;
        ownerId = _ownerId;
    }

    // only way to create new shares
    function mint(PullRequest[] calldata pullRequests) public onlyOwner {
        uint len = pullRequests.length;
        for (uint i = 0; i < len; ++i) {
            _mint(pullRequests[i].owner, pullRequests[i].score);
        }
    }

    function totalAssets() public override view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                             NOT_SUPPORTED
    //////////////////////////////////////////////////////////////*/
    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        revert(Errors.NOT_SUPPORTED);
    }
    function mint(uint256 assets, address receiver) public override returns (uint256 shares) {
        revert(Errors.NOT_SUPPORTED);
    }
}