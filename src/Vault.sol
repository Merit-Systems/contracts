// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {MerkleProof} from "openzeppelin/utils/cryptography/MerkleProof.sol";

import {Owners} from "./Owners.sol";

contract MeritLedger {
    uint constant MAX_CONTRIBUTORS = 50;

    Owners public owners;

    struct MeritRepoConfig {
        uint inflationRateBps; // e.g., 500 = 5% annual inflation
        uint lastSnapshotTime; 
    }

    struct MeritRepo {
        uint                     totalShares;
        mapping(address => uint) shares;
        address[]                contributors;
        MeritRepoConfig          config;
        bool                     initialized;
        uint                     ownerId;
        bytes32                  paymentMerkleRoot;
        mapping(uint => bool)    claimed;
    }

    struct Contribution {
        address contributor;
        uint    weight;
    }

    mapping(uint => MeritRepo) private repos;

    modifier onlyInitialized(uint repoId) {
        require(repos[repoId].initialized);
        _;
    }

    constructor(Owners _owners) {
        owners = _owners;
    }

    function initializeRepo(
        uint               repoId,
        address            owner,
        address[] calldata contributors,
        uint   [] calldata shares,
        uint               inflationRateBps
    )
        external
    {
        MeritRepo storage repo = repos[repoId];
        require(!repo.initialized);
        require(contributors.length == shares.length);

        uint total;
        uint totalContributors = contributors.length;
        for (uint i = 0; i < totalContributors; ++i) {
            address user = contributors[i];
            uint userShares = shares[i];
            require(user != address(0));
            require(userShares > 0);

            repo.shares[user] = userShares;
            repo.contributors.push(user);
            total += userShares;
        }

        repo.config = MeritRepoConfig({
            inflationRateBps: inflationRateBps,
            lastSnapshotTime: block.timestamp
        });

        repo.totalShares = total;
        repo.ownerId     = owners.mint(owner);
        repo.initialized = true;
    }

    function applyInflation(uint repoId) public onlyInitialized(repoId) {
        MeritRepo storage repo = repos[repoId];
        uint elapsed = block.timestamp - repo.config.lastSnapshotTime;
        if (elapsed == 0) return; 

        uint annualBps           = repo.config.inflationRateBps; 
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
        repo.config.lastSnapshotTime = block.timestamp;
    }

    function updateRepoLedger(
        uint repoId,
        Contribution[] calldata contributions
    )
        external
        onlyInitialized(repoId)
    {
        applyInflation(repoId);

        MeritRepo storage repo = repos[repoId];
        require(contributions.length > 0);

        uint totalContributions = contributions.length;
        uint newSharesPool = repo.totalShares / 10; // TODO: Make this configurable

        uint[] memory curveWeights = new uint[](totalContributions);
        uint sumWeights = 0;

        for (uint i = 0; i < totalContributions; i++) {
            uint weight     = contributions[i].weight;
            curveWeights[i] = weight;
            sumWeights     += weight;
        }

        for (uint i = 0; i < totalContributions; i++) {
            Contribution memory contribution = contributions[i];
            uint weight    = curveWeights[i];
            uint newShares = (newSharesPool * weight) / sumWeights;
            address contributor = contribution.contributor;
            repo.shares[contributor] += newShares;
            repo.totalShares += newShares;
        }
    }

    function setPaymentMerkleRoot(uint repoId, bytes32 merkleRoot) external onlyInitialized(repoId) {
        MeritRepo storage repo = repos[repoId];
        // require(msg.sender == repo.admin, "Only admin can set merkle root");
        repo.paymentMerkleRoot = merkleRoot;
    }

    function claimPayment(
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
        require(MerkleProof.verify(merkleProof, repo.paymentMerkleRoot, leaf), "Invalid merkle proof");
        repo.claimed[index] = true;
        (bool sent, ) = payable(account).call{value: amount}("");
        require(sent, "Transfer failed");
    }
}
