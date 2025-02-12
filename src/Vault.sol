// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {MerkleProof}              from "openzeppelin/utils/cryptography/MerkleProof.sol";
import {ERC721, ERC721Enumerable} from "openzeppelin/token/ERC721/extensions/ERC721Enumerable.sol";
import {ERC20}                    from "solmate/tokens/ERC20.sol";
import {SafeTransferLib}          from "solmate/utils/SafeTransferLib.sol";

contract MeritLedger is ERC721Enumerable {
    using SafeTransferLib for ERC20;

    uint constant MAX_CONTRIBUTORS = 50;

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
    }

    struct PullRequest {
        address contributor;
        uint    weight;
    }

    ERC20 public paymentToken;

    mapping(uint => MeritRepo) public repos;

    modifier onlyInitialized(uint repoId) {
        require(repos[repoId].initialized);
        _;
    }

    constructor(ERC20 _paymentToken) ERC721("Merit Repository Owners", "MRO") {
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
    {
        MeritRepo storage repo = repos[repoId];
        require(!repo.initialized);
        require(contributors.length == shares.length);

        uint totalShares;
        uint totalContributors = contributors.length;
        for (uint i = 0; i < totalContributors; ++i) {
            address contributor = contributors[i];
            uint    share       = shares[i];
            require(contributor != address(0));
            require(share > 0);

            repo.shares[contributor] = share;
            repo.contributors.push(contributor);
            totalShares += share;
        }

        uint ownerId = totalSupply();
        _mint(owner, ownerId);

        repo.ownerId          = ownerId;
        repo.inflationRate = inflationRate;
        repo.lastSnapshotTime = block.timestamp;
        repo.totalShares      = totalShares;
        repo.initialized      = true;
    }

    function applyInflation(uint repoId) public onlyInitialized(repoId) {
        MeritRepo storage repo = repos[repoId];
        uint elapsed = block.timestamp - repo.lastSnapshotTime;
        if (elapsed == 0) return; 

        uint annualBps           = repo.inflationRate; 
        uint yearsScaled         = (elapsed * 1e18) / 365 days;
        uint inflationMultiplier = 1e18 + ((annualBps * yearsScaled) / 10000);

        for (uint i = 0; i < repo.contributors.length; i++) {
            address user      = repo.contributors[i];
            uint oldShares    = repo.shares[user];
            uint newShares    = (oldShares * inflationMultiplier) / 1e18;
            repo.shares[user] = newShares;
        }

        uint oldTotal    = repo.totalShares;
        uint newTotal    = (oldTotal * inflationMultiplier) / 1e18;
        repo.totalShares = newTotal;
        repo.lastSnapshotTime = block.timestamp;
    }

    function update(
        uint repoId,
        PullRequest[] calldata pullRequests
    )
        external
        onlyInitialized(repoId)
    {
        applyInflation(repoId);

        MeritRepo storage repo = repos[repoId];
        require(pullRequests.length > 0);

        uint totalContributions = pullRequests.length;
        uint newSharesPool = repo.totalShares / 10; // TODO: Make this configurable

        uint[] memory curveWeights = new uint[](totalContributions);
        uint sumWeights = 0;

        for (uint i = 0; i < totalContributions; i++) {
            uint weight     = pullRequests[i].weight;
            curveWeights[i] = weight;
            sumWeights     += weight;
        }

        for (uint i = 0; i < totalContributions; i++) {
            PullRequest memory pullRequest = pullRequests[i];
            uint weight    = curveWeights[i];
            uint newShares = (newSharesPool * weight) / sumWeights;
            address contributor = pullRequest.contributor;
            repo.shares[contributor] += newShares;
            repo.totalShares += newShares;
        }
    }

    function setPaymentMerkleRoot(uint repoId, bytes32 merkleRoot) external onlyInitialized(repoId) {
        MeritRepo storage repo = repos[repoId];
        require(msg.sender == ownerOf(repo.ownerId));
        repo.paymentMerkleRoot = merkleRoot;
    }

    function claim(
        uint               repoId,
        uint               index,
        address            account,
        uint               amount,
        bytes32[] calldata merkleProof
    )
        external
        onlyInitialized(repoId)
    {
        MeritRepo storage repo = repos[repoId];
        require(msg.sender == account);
        require(!repo.claimed[index]);
        bytes32 leaf = keccak256(abi.encodePacked(index, account, amount));
        require(MerkleProof.verify(merkleProof, repo.paymentMerkleRoot, leaf));
        repo.claimed[index] = true;
        paymentToken.safeTransfer(account, amount);
    }
}
