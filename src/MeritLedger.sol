// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {MerkleProof}              from "openzeppelin/utils/cryptography/MerkleProof.sol";
import {ERC721, ERC721Enumerable} from "openzeppelin/token/ERC721/extensions/ERC721Enumerable.sol";
import {ERC20}                    from "solmate/tokens/ERC20.sol";
import {SafeTransferLib}          from "solmate/utils/SafeTransferLib.sol";
import {Owned}                    from "solmate/auth/Owned.sol";

import {Errors} from "libraries/Errors.sol";

contract MeritLedger is ERC721Enumerable, Owned {
    using SafeTransferLib for ERC20;

    event Initialized         (uint repoId, address owner, address[] contributors, uint[] shares, uint dilutionRate);
    event Updated             (uint repoId, PullRequest[] pullRequests);
    event Claimed             (uint repoId, uint index, address account, uint amount, bytes32 merkleRoot);
    event MerkleRootSet       (uint repoId, bytes32 merkleRoot, bool isSet);
    event DilutionRateSet     (uint repoId, uint dilutionRate);
    event PaymentPermissionSet(address user, bool allowed);

    uint constant MAX_NUMBER_OF_INITIAL_CONTRIBUTORS     = 100;
    uint constant MAX_NUMBER_OF_PULL_REQUESTS_PER_UPDATE = 100;

    struct PullRequest {
        address contributor;
        uint    weight;
    }

    struct MeritRepo {
        uint                     totalShares;
        mapping(address => uint) shares;
        address[]                contributors;
        uint                     dilutionRate; // in basis points, e.g. 500 = 5% annual dilution
        uint                     lastSnapshot; 
        bool                     initialized;
        uint                     ownerId;
        mapping(bytes32 => bool) merkleRoots;

        // index => (merkleRoot => claimed)
        mapping(uint => mapping(bytes32 => bool)) claimed;
    }

    ERC20 public paymentToken;

    mapping(address => bool) public canReceivePayment;

    mapping(uint => MeritRepo) public repos;

    modifier onlyRepoOwner(uint repoId) {
        require(repos[repoId].initialized,                    Errors.NOT_INITIALIZED);
        require(msg.sender == ownerOf(repos[repoId].ownerId), Errors.NOT_OWNER);
        _;
    }

    constructor(ERC20 _paymentToken) 
        Owned (msg.sender)
        ERC721("Merit Repositories", "MR") 
    {
        paymentToken = _paymentToken;
    }

    function init(
        uint               repoId,
        address            owner,
        address[] calldata contributors,
        uint   [] calldata shares,
        uint               dilutionRate
    )
        external
        onlyOwner
    {
        MeritRepo storage repo = repos[repoId];
        require(!repo.initialized,                                         Errors.ALREADY_INITIALIZED);
        require(contributors.length == shares.length,                      Errors.LENGTH_MISMATCH);
        require(contributors.length > 0,                                   Errors.NO_CONTRIBUTORS);
        require(contributors.length <= MAX_NUMBER_OF_INITIAL_CONTRIBUTORS, Errors.TOO_MANY_CONTRIBUTORS);

        uint totalShares;
        uint totalContributors = contributors.length;
        for (uint i = 0; i < totalContributors; ++i) {
            address contributor = contributors[i];
            uint    share       = shares[i];
            require(share > 0, Errors.ZERO_SHARE);

            repo.shares[contributor] = share;
            repo.contributors.push(contributor);
            totalShares += share;
        }

        uint ownerId = totalSupply();
        _mint(owner, ownerId);

        repo.ownerId      = ownerId;
        repo.dilutionRate = dilutionRate;
        repo.lastSnapshot = block.timestamp;
        repo.totalShares  = totalShares;
        repo.initialized  = true;

        emit Initialized(repoId, owner, contributors, shares, dilutionRate);
    }

    function update(
        uint repoId,
        PullRequest[] calldata pullRequests
    )
        external
        onlyRepoOwner(repoId)
    {
        uint lenPullRequests = pullRequests.length;
        require(lenPullRequests > 0,                                       Errors.NO_PULL_REQUESTS);
        require(lenPullRequests <= MAX_NUMBER_OF_PULL_REQUESTS_PER_UPDATE, Errors.TOO_MANY_PULL_REQUESTS);
        MeritRepo storage repo = repos[repoId];

        uint elapsed = block.timestamp - repo.lastSnapshot;
        require(elapsed > 0, Errors.NO_TIME_ELAPSED);

        uint yearsScaled       = (elapsed * 1e18) / 365 days;
        uint inflationFraction = (repo.dilutionRate * yearsScaled) / 10000; // e.g. 0.05 in 1e18 form
        uint mintedForPRs      = (repo.totalShares * inflationFraction) / 1e18;

        uint sumWeights;
        for (uint i = 0; i < lenPullRequests; ++i) { sumWeights += pullRequests[i].weight; }
        require(sumWeights > 0, Errors.NO_WEIGHTS);

        for (uint i = 0; i < lenPullRequests; ++i) {
            uint newShares = (mintedForPRs * pullRequests[i].weight) / sumWeights;
            repo.shares[pullRequests[i].contributor] += newShares;
            repo.totalShares += newShares;
        }

        repo.lastSnapshot = block.timestamp;

        emit Updated(repoId, pullRequests);
    }

    function claim(
        uint               repoId,
        uint               index,
        address            account,
        uint               amount,
        bytes32[] calldata merkleProof,
        bytes32            merkleRoot
    ) external {
        MeritRepo storage repo = repos[repoId];
        require(msg.sender == account,            Errors.NOT_ACCOUNT_OWNER);
        require(repo.merkleRoots[merkleRoot],     Errors.INVALID_ROOT);
        require(canReceivePayment[account],       Errors.NO_PAYMENT_PERMISSION);
        require(!repo.claimed[index][merkleRoot], Errors.ALREADY_CLAIMED);
        bytes32 leaf = keccak256(abi.encodePacked(index, account, amount));
        require(MerkleProof.verify(merkleProof, merkleRoot, leaf), Errors.INVALID_PROOF);
        repo.claimed[index][merkleRoot] = true;
        paymentToken.safeTransfer(account, amount);
        emit Claimed(repoId, index, account, amount, merkleRoot);
    }

    /*//////////////////////////////////////////////////////////////
                            SETTERS
    //////////////////////////////////////////////////////////////*/
    function setMerkleRoot(uint repoId, bytes32 merkleRoot, bool isSet)
        external 
        onlyRepoOwner(repoId)
    {
        repos[repoId].merkleRoots[merkleRoot] = isSet;
        emit MerkleRootSet(repoId, merkleRoot, isSet);
    }

    function setDilutionRate(uint repoId, uint dilutionRate) 
        external 
        onlyRepoOwner(repoId) 
    {
        repos[repoId].dilutionRate = dilutionRate;
        emit DilutionRateSet(repoId, dilutionRate);
    }

    function setPaymentPermission(address user, bool allowed) external onlyOwner {
        canReceivePayment[user] = allowed;
        emit PaymentPermissionSet(user, allowed);
    }
}