// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract MeritLedger {
    uint constant MAX_CONTRIBUTORS = 50;

    enum AttributionCurve {
        Constant, 
        Linear
    }

    struct Ownership {
        uint shares;  
        bool exists;
    }

    struct MeritRepoConfig {
        AttributionCurve curve;
        uint inflationRateBps; // e.g., 500 = 5% annual inflation
        uint lastSnapshotTime; 
    }

    struct MeritRepo {
        uint                          totalShares;
        mapping(address => Ownership) owners;
        address[]                     contributors;
        MeritRepoConfig               config;
        bool                          initialized;
    }

    mapping(uint => MeritRepo) private repos;

    modifier onlyInitialized(uint repoId) {
        require(repos[repoId].initialized);
        _;
    }

    function initializeRepo(
        uint               repoId,
        address[] calldata contributors,
        uint   [] calldata shares,
        AttributionCurve   curve,
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

            repo.owners[user] = Ownership({shares: userShares, exists: true});
            repo.contributors.push(user);
            total += userShares;
        }

        repo.config = MeritRepoConfig({
            curve:            curve,
            inflationRateBps: inflationRateBps,
            lastSnapshotTime: block.timestamp
        });

        repo.totalShares = total;
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
            address user                = repo.contributors[i];
            Ownership storage ownership = repo.owners[user];
            uint oldShares              = ownership.shares;
            uint newShares              = (oldShares * inflationMultiplier) / 1e18;
            ownership.shares            = newShares;
        }

        uint oldTotal    = repo.totalShares;
        uint newTotal    = (oldTotal * inflationMultiplier) / 1e18;
        repo.totalShares = newTotal;
        repo.config.lastSnapshotTime = block.timestamp;
    }

    function updateRepoLedger(
        uint repoId,
        address[] calldata contributors
    )
        external
        onlyInitialized(repoId)
    {
        applyInflation(repoId);

        MeritRepo storage repo = repos[repoId];
        require(contributors.length > 0);

        uint totalContributors = contributors.length;
        uint newSharesPool = repo.totalShares / 10; // TODO: Make this configurable

        uint[] memory curveWeights = new uint[](totalContributors);
        uint sumWeights = 0;

        for (uint i = 0; i < totalContributors; i++) {
            uint weight     = _calculateCurveValue(repo.config.curve);
            curveWeights[i] = weight;
            sumWeights     += weight;
        }

        for (uint i = 0; i < totalContributors; i++) {
            address user   = contributors[i];
            uint weight    = curveWeights[i];
            uint newShares = (newSharesPool * weight) / sumWeights;

            if (!repo.owners[user].exists) {
                repo.contributors.push(user);
                repo.owners[user] = Ownership({shares: 0, exists: true});
            }
            repo.owners[user].shares += newShares;
            repo.totalShares += newShares;
        }
    }

    function distributePayment(uint repoId) external payable onlyInitialized(repoId) {
        require(msg.value > 0);

        MeritRepo storage repo = repos[repoId];
        uint numContributors = repo.contributors.length;
        if (numContributors == 0 || repo.totalShares == 0) {
            (bool refunded, ) = msg.sender.call{value: msg.value}("");
            require(refunded);
            return;
        }

        uint maxContributors = numContributors > MAX_CONTRIBUTORS ? MAX_CONTRIBUTORS : numContributors;
        uint remaining = msg.value;

        for (uint i = 0; i < maxContributors; i++) {
            address user = repo.contributors[i];
            uint share = repo.owners[user].shares;
            uint payment = (msg.value * share) / repo.totalShares;
            if (payment > 0 && payment <= remaining) {
                remaining -= payment;
                (bool sent, ) = payable(user).call{value: payment}("");
                require(sent);
            }
        }

        if (remaining > 0) {
            (bool leftoverSent, ) = msg.sender.call{value: remaining}("");
            require(leftoverSent);
        }

    }

    function _calculateCurveValue(AttributionCurve curve)
        internal
        pure
        returns (uint weight)
    {
        if (curve == AttributionCurve.Constant) return 1;
        if (curve == AttributionCurve.Linear)   return 1; // TODO
        return 1;
    }
}
