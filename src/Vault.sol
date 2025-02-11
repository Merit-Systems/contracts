// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import {ERC20}             from "solmate/tokens/ERC20.sol";
import {SafeTransferLib}   from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {Oracle} from "./Oracle.sol";
import {Owners} from "./Owners.sol";
import {Errors} from "../libraries/Errors.sol";

contract Vault {
    using FixedPointMathLib for uint;
    using SafeTransferLib   for ERC20;

    event Transfer(address indexed from, address indexed to, uint amount);
    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint assets,
        uint shares
    );

    string public name;
    string public symbol;
    uint8  public immutable decimals;
    Owners public immutable owners;
    uint   public immutable ownerId;
    ERC20  public immutable asset;
    Oracle public immutable oracle;

    uint public totalSupply;
    mapping(address => uint) public balanceOf;

    struct PullRequest {
        address owner;
        uint    score;
        uint    deadline;
    }

    modifier onlyVaultOwner() {
        require(msg.sender == owners.ownerOf(ownerId), Errors.NOT_OWNER);
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        Owners        _owners,
        uint          _ownerId, 
        ERC20         _asset, 
        address       _admin,
        PullRequest[] memory _pullRequests
    ) {
        name     = _name;
        symbol   = _symbol;
        decimals = _asset.decimals();
        owners   = _owners;
        ownerId  = _ownerId;
        asset    = _asset;
        oracle   = new Oracle(_admin, address(this)); 

        mint(_pullRequests);
    }

    // only way to create new shares
    function mint(PullRequest[] memory pullRequests) public onlyVaultOwner {
        uint len = pullRequests.length;
        for (uint i = 0; i < len; ++i) {
            _mint(pullRequests[i].owner, pullRequests[i].score);
        }
    }

    // TODO: check for freeze
    function redeem(
        uint shares,
        address receiver,
        address owner
    ) public virtual returns (uint assets) {
        require(msg.sender == owner, Errors.NOT_OWNER);

        uint supply = totalSupply; 

        assets = supply == 0 ? shares : shares.mulDivDown(
            asset.balanceOf(address(this)), 
            supply
        );

        require(assets != 0);
        _burn(owner, shares);
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        asset.safeTransfer(receiver, assets);
        oracle.updateClaimed(msg.sender, assets);
    }

    function convertToAssets(uint shares) public view virtual returns (uint) {
        uint supply = totalSupply; 
        return supply == 0 ? shares : shares.mulDivDown(
            asset.balanceOf(address(this)),
            supply
        );
    }

    // @audit from Solmate ERC20
    function _mint(address to, uint amount) internal virtual {
        totalSupply += amount;
        unchecked { balanceOf[to] += amount; }
        emit Transfer(address(0), to, amount);
    }

    // @audit from Solmate ERC20
    function _burn(address from, uint amount) internal virtual {
        balanceOf[from] -= amount;
        unchecked { totalSupply -= amount; }
        emit Transfer(from, address(0), amount);
    }
}