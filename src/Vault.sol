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

    uint public baseTotalSupply;
    mapping(address => uint) public baseBalanceOf;

    // cumulative index that grows over time
    uint public inflationIndex = 1e18; // starts at 1.0
    uint public lastInflationUpdate;
    uint public inflationRate = 1e18; // fraction/second, e.g. 1e18 => 0% per second

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
        uint          _initialInflationRate,
        PullRequest[] memory _pullRequests
    ) {
        name     = _name;
        symbol   = _symbol;
        decimals = _asset.decimals();
        owners   = _owners;
        ownerId  = _ownerId;
        asset    = _asset;
        oracle   = new Oracle(_admin, address(this)); 

        inflationRate       = _initialInflationRate;
        lastInflationUpdate = block.timestamp;

        mint(_pullRequests);
    }

    function setInflationRate(uint newRate) external onlyVaultOwner {
        _applyInflation();
        inflationRate = newRate;
    }

    function _applyInflation() internal {
        uint current = block.timestamp;
        uint elapsed = current - lastInflationUpdate;
        if (elapsed == 0) return; // no time, no change

        lastInflationUpdate = current;

        if (inflationRate == 0) {
            // no growth in index
            return; 
        }

        // factor = 1e18 + (inflationRate * elapsed)
        // example: if inflationRate = 1e9 => ~0.1% per second, etc.
        // newIndex = oldIndex * (1e18 + rate * elapsed) / 1e18
        uint oldIndex  = inflationIndex;
        uint factor    = 1e18 + (inflationRate * elapsed);
        inflationIndex = oldIndex.mulDivDown(factor, 1e18);
    }

    function mint(PullRequest[] memory pullRequests) public onlyVaultOwner {
        _applyInflation();
        uint len = pullRequests.length;
        for (uint i = 0; i < len; ++i) {
            _mint(pullRequests[i].owner, pullRequests[i].score);
        }
    }

    function redeem(
        uint sharesInRebasedUnits,  // user sees "rebased" shares
        address receiver,
        address owner
    ) public returns (uint assets) {
        _applyInflation();
        require(msg.sender == owner, Errors.NOT_OWNER);

        uint baseShares = sharesInRebasedUnits.mulDivDown(1e18, inflationIndex);

        uint supplyBase = baseTotalSupply; 
        if (supplyBase == 0) {
            // If no supply, you can't really redeem anything, or we do 1:1
            // for demonstration we handle the zero-supply edge:
            assets = sharesInRebasedUnits; 
        } else {
            uint vaultBalance = asset.balanceOf(address(this));
            assets = baseShares.mulDivDown(vaultBalance, supplyBase);
        }
        require(assets != 0, "ZERO_ASSETS");

        _burn(owner, baseShares);

        oracle.updateClaimed(msg.sender, assets);
        asset.safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner, assets, sharesInRebasedUnits);
    }

    function totalSupply() public view returns (uint) {
        return baseTotalSupply.mulDivDown(inflationIndex, 1e18);
    }

    function balanceOf(address account) public view returns (uint) {
        return baseBalanceOf[account].mulDivDown(inflationIndex, 1e18);
    }

    // optional utility
    function convertToAssets(uint sharesInRebasedUnits) public view returns (uint) {
        uint supplyBase = baseTotalSupply;
        if (supplyBase == 0) return sharesInRebasedUnits; 

        // Convert rebased shares back to base, then compute fraction.
        uint baseShares = sharesInRebasedUnits.mulDivDown(1e18, inflationIndex);
        return baseShares.mulDivDown(asset.balanceOf(address(this)), supplyBase);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/
    function _mint(address to, uint amountBase) internal {
        baseTotalSupply += amountBase;
        unchecked { baseBalanceOf[to] += amountBase; }
        emit Transfer(address(0), to, amountBase);
    }

    function _burn(address from, uint amountBase) internal {
        baseBalanceOf[from] -= amountBase;
        unchecked { baseTotalSupply -= amountBase; }
        emit Transfer(from, address(0), amountBase);
    }
}
