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

    struct MeritRepo {
        uint                     totalShares;
        mapping(address => uint) shares;
        address[]                contributors;
        uint                     inflationRate;    // in basis points, e.g. 500 = 5% annual inflation
        uint                     lastSnapshotTime; 
        bool                     initialized;
        uint                     ownerId;
        bytes32                  paymentMerkleRoot;
        mapping(uint => bool)    claimed;
        uint                     newSharesPerUpdate;
    }

    struct PullRequest {
        address contributor;
        uint    weight;
    }

    ERC20 public paymentToken;

    mapping(uint => MeritRepo) public repos;

    modifier onlyRepoOwner(uint repoId) {
        require(repos[repoId].initialized);
        require(msg.sender == ownerOf(repos[repoId].ownerId));
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
        uint               inflationRate
    )
        external
        onlyOwner
    {
        MeritRepo storage repo = repos[repoId];
        require(!repo.initialized,                    Errors.ALREADY_INITIALIZED);
        require(contributors.length == shares.length, Errors.LENGTH_MISMATCH);

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

        repo.ownerId          = ownerId;
        repo.inflationRate    = inflationRate;
        repo.lastSnapshotTime = block.timestamp;
        repo.totalShares      = totalShares;
        repo.initialized      = true;
    }

    function inflate(
        uint repoId
    ) 
        public 
        onlyRepoOwner(repoId) 
    {
        MeritRepo storage repo = repos[repoId];
        uint elapsed = block.timestamp - repo.lastSnapshotTime;
        if (elapsed == 0) return; 

        uint yearsScaled         = (elapsed * 1e18) / 365 days;
        uint inflationMultiplier = 1e18 + ((repo.inflationRate * yearsScaled) / 10000);

        for (uint i = 0; i < repo.contributors.length; i++) {
            address user      = repo.contributors[i];
            uint oldShares    = repo.shares[user];
            uint newShares    = (oldShares * inflationMultiplier) / 1e18;
            repo.shares[user] = newShares;
        }

        uint oldTotal         = repo.totalShares;
        uint newTotal         = (oldTotal * inflationMultiplier) / 1e18;
        repo.totalShares      = newTotal;
        repo.lastSnapshotTime = block.timestamp;
    }

    function update(
        uint repoId,
        PullRequest[] calldata pullRequests
    )
        external
        onlyRepoOwner(repoId)
    {
        inflate(repoId);

        MeritRepo storage repo = repos[repoId];
        require(pullRequests.length > 0);

        uint lenPullRequests = pullRequests.length;
        uint newShares = repo.totalShares * repo.newSharesPerUpdate; 

        uint[] memory weights = new uint[](lenPullRequests);
        uint sumWeights = 0;

        for (uint i = 0; i < lenPullRequests; i++) {
            uint weight = pullRequests[i].weight;
            weights[i]  = weight;
            sumWeights += weight;
        }

        for (uint i = 0; i < lenPullRequests; i++) {
            PullRequest memory pullRequest = pullRequests[i];
            uint newSharesContributor = (newShares * weights[i]) / sumWeights;
            repo.shares[pullRequest.contributor] += newSharesContributor;
            repo.totalShares                     += newSharesContributor;
        }
    }

    function claim(
        uint               repoId,
        uint               index,
        address            account,
        uint               amount,
        bytes32[] calldata merkleProof
    ) external {
        MeritRepo storage repo = repos[repoId];
        require(msg.sender == account);
        require(!repo.claimed[index]);
        bytes32 leaf = keccak256(abi.encodePacked(index, account, amount));
        require(MerkleProof.verify(merkleProof, repo.paymentMerkleRoot, leaf));
        repo.claimed[index] = true;
        paymentToken.safeTransfer(account, amount);
    }

    function setNewSharesPerUpdate(uint repoId, uint sharesPerUpdate) external onlyRepoOwner(repoId) {
        repos[repoId].newSharesPerUpdate = sharesPerUpdate;
    }

    function setPaymentMerkleRoot(uint repoId, bytes32 paymentMerkleRoot) external onlyRepoOwner(repoId) {
        repos[repoId].paymentMerkleRoot = paymentMerkleRoot;
    }
}