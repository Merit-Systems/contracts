What do we need:

## For every User (Merit Account)

- All incoming payments (claimed, reclaimed)
- All outgoing payments (claimed, reclaimed)

- Merit Balance

  - All claimed incoming Payments
  - All claimable incoming Payments

- Merit Repo Balance

  - All Funded Amounts
  - Minus outgoing payments
  - Plus reclaimed repo payments

- Payments

  - From a Repo (repoId, instanceId)
  - From a Sender (githubId/address)

- Meta Level / Batches
- We need to indicate if the Batch is FromRepo/FromSender

### Tax Engine

- initRepo signature route
- claim signature route

### Terminal

### Indexer

Tables:

FundedRepo:

- repoId
- accountId
- token
- sender
- amount
- data

DistributedFromRepoBatch:

- batchId (primary key)
- repoId
- accountId
- distributionIds (array of distribution IDs in this batch)
- data

DistributedFromRepo:

- distributionId (primary key)
- batchId (foreign key -> DistributedFromRepoBatch.batchId)
- recipient
- token
- amount
- claimDeadline

DistributedFromSenderBatch:

- batchId (primary key)
- distributionIds (array of distribution IDs in this batch)
- data

DistributedFromSender:

- distributionId (primary key)
- batchId (foreign key -> DistributedFromSenderBatch.batchId)
- payer
- recipient
- token
- amount
- claimDeadline

ClaimedBatch:

- batchId (primary key)
- distributionIds (array of distribution IDs in this batch)
- recipient
- data

Claimed:

- distributionId (primary key)
- batchId (foreign key -> ClaimedBatch.batchId)
- recipient
- amount
- fee

ReclaimedRepoFunds:

- repoId
- accountId
- admin
- amount

ReclaimedRepoDistributionsBatch:

- batchId (primary key)
- repoId
- accountId
- distributionIds (array of distribution IDs in this batch)
- data

ReclaimedRepoDistribution:

- distributionId (primary key)
- batchId (foreign key -> ReclaimedRepoDistributionsBatch.batchId)
- admin
- amount

Relationships:

- Each batch table (DistributedFromRepoBatch, DistributedFromSenderBatch, ClaimedBatch, ReclaimedRepoDistributionsBatch) contains a distributionIds array that lists all distribution IDs belonging to that batch
- Each distribution table (DistributedFromRepo, DistributedFromSender, Claimed, ReclaimedRepoDistribution) has a batchId that references its parent batch

Notes on the Indexer:

- we still need the reclaim logic we had before but we are going to implement this in pure sql

### Tax Engine Routes

1. Signature Routes:

   - `GET /init-repo/signature`

     - Returns a signed message for initializing a repo with admins
     - Parameters: repoId, accountId, admins (array), signatureDeadline
     - Returns: { signature, message }

   - `GET /claim/signature`
     - Returns a signed message for claiming distributions
     - Parameters: distributionIds (array), recipient, signatureDeadline
     - Returns: { signature, message }

2. Query Routes:

   **User/Account Data:**

   - `GET /balance/merit/:githubId`

     - Returns Merit Balance (claimed + claimable incoming payments)

   - `GET /balance/repo/:repoId/:githubId`

     - Returns Merit Repo Balance (funded - outgoing + reclaimed)

   - `GET /payments/incoming/:githubId`

     - Returns all incoming payments (claimed and claimable)

   - `GET /payments/outgoing/:githubId`
     - Returns all outgoing payments (claimed and reclaimed)

   **Repo Management:**

   - `GET /repo/:repoId/:githubId/admins`

     - Returns list of repo admins

   - `GET /repo/:repoId/:githubId/distributors`

     - Returns list of repo distributors

   - `GET /repo/:repoId/:githubId/exists`

     - Returns whether repo account is initialized

   - `GET /repo/:repoId/:githubId/balance/:token`

     - Returns repo balance for specific token

   - `GET /repo/:repoId/:githubId/can-distribute/:address`

     - Returns whether address can distribute from repo

   - `GET /admin/repo/:repoId/:githubId/overview`

     - Returns complete repo overview (balances, admin count, distributor count, total distributions)

   - `GET /admin/repo/:repoId/:githubId/distributors/activity`

     - Returns activity summary for each distributor (total distributed, batch count, etc.)

   - `GET /admin/repo/:repoId/:githubId/distributor/:address/payments`

     - Returns all payments/distributions made by specific distributor

   - `GET /admin/repo/:repoId/:githubId/distributor/:address/batches`

     - Returns all batches created by specific distributor

   - `GET /batch/:batchId`

     - Returns batch details with all items

   - `GET /batch/:batchId/items`

     - Returns all distributions in a batch with their status

   - `GET /batches/repo/:repoId/:githubId`

     - Returns all batches for a repo (DistributedFromRepo, ReclaimedRepo)

   - `GET /batches/sender/:address`

     - Returns all batches for a sender (DistributedFromSender, ReclaimedSender)

   - `GET /batches/recipient/:githubId`

     - Returns all claim batches for a recipient

   - `GET /batches/recent/:limit?`

     - Returns recent batches across the system

   - `GET /batches/paid-to/:githubId`

     - Returns all batches containing distributions paid TO this recipient
     - Includes DistributedFromRepo and DistributedFromSender batches

   - `GET /batches/paid-to/:githubId/unclaimed`

     - Returns batches with unclaimed distributions for this recipient

   - `GET /batches/paid-to/:githubId/claimed`

     - Returns batches where this recipient has claimed distributions

   - `GET /distribution/:distributionId`

     - Returns full distribution details

   - `GET /distributions/claimable/:githubId`

     - Returns all claimable distributions for recipient

   - `GET /distributions/expired/:githubId`

     - Returns all expired (unclaimable) distributions for recipient

   - `GET /distributions/to/:githubId`

     - Returns ALL distributions sent to this recipient (claimed, unclaimed, expired)

   - `GET /distributions/to/:githubId/claimed`

     - Returns all claimed distributions for this recipient

   - `GET /distributions/to/:githubId/unclaimed`

     - Returns all unclaimed (still claimable) distributions for this recipient

   - `GET /distributions/repo/:repoId/:githubId`

     - Returns all distributions from a specific repo

   - `GET /distributions/repo/:repoId/:githubId/by-distributor`

     - Returns distributions grouped by distributor address

   - `GET /distributions/sender/:address`
     - Returns all distributions from a specific sender

   **Reclaim Data:**

   - `GET /reclaim/repo-funds/:repoId/:githubId`

     - Returns reclaimable repo funds (only if no distributions exist)

   - `GET /reclaim/repo-distributions/:repoId/:githubId`

     - Returns expired repo distributions that can be reclaimed

   - `GET /reclaim/repo-distributions/:repoId/:githubId/by-distributor`

     - Returns expired repo distributions grouped by distributor

   - `GET /reclaim/sender-distributions/:address`
     - Returns expired sender distributions that can be reclaimed

   **System Data:**

   - `GET /tokens/whitelisted`

     - Returns list of whitelisted tokens

   - `GET /config`

     - Returns system config (fee, batchLimit, feeRecipient, etc.)

   - `GET /nonce/recipient/:address`
     - Returns current nonce for recipient (for claim signatures)

   **Funding/Deposits:**

   - `GET /funding/repo/:repoId/:githubId`

     - Returns all funding transactions for a repo

   - `GET /funding/by-sender/:address`

     - Returns all funding transactions made by a specific sender

   - `GET /funding/recent/:limit?`
     - Returns recent funding transactions across all repos

   **Transaction History (Complete Flow):**

   - `GET /transactions/user/:githubId`

     - Returns complete transaction history: funded repos, distributions sent/received, claims, reclaims

   - `GET /transactions/repo/:repoId/:githubId`

     - Returns complete repo transaction history: funding, distributions, claims, reclaims

   - `GET /transactions/recent/:limit?`
     - Returns recent transactions across the entire system

   **Missing Reclaim Data:**

   - `GET /reclaims/repo-funds/:repoId/:githubId`

     - Returns history of repo fund reclaims

   - `GET /reclaims/repo-distributions/:repoId/:githubId`

     - Returns history of repo distribution reclaims

   - `GET /reclaims/sender-distributions/:address`

     - Returns history of sender distribution reclaims

   - `GET /reclaims/by-admin/:address`
     - Returns all reclaims performed by a specific admin

   **Fee Tracking:**

   - `GET /fees/collected`

     - Returns total fees collected by the system

   - `GET /fees/by-token/:token`

     - Returns fees collected for a specific token

   - `GET /fees/from-user/:githubId`
     - Returns total fees paid by a specific user through claims

Each signature route will:

- Validate the request parameters
- Check permissions
- Generate and sign the appropriate message
- Return the signature and message for the frontend to submit to the blockchain

The indexer will process the blockchain transactions to update the database state.
