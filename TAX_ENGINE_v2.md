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

Batches:

- batchId (primary key)
- batchType (DistributedFromRepo, DistributedFromSender, Claimed, ReclaimedRepoDistributions)
- repoId (nullable - only for repo batches)
- accountId (nullable - only for repo batches)
- initiator (address who created the batch)
- recipient (nullable - only for claim batches)
- timestamp
- data

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

   **Contract-Based Routes (Current State):**

   - `GET /repo/:repoId/:accountId/admins`

     - Returns list of repo admins (from contract)

   - `GET /repo/:repoId/:accountId/distributors`

     - Returns list of repo distributors (from contract)

   - `GET /repo/:repoId/:accountId/exists`

     - Returns whether repo account is initialized (from contract)

   - `GET /repo/:repoId/:accountId/balance/:token`

     - Returns repo balance for specific token (from contract)

   - `GET /repo/:repoId/:accountId/can-distribute/:address`

     - Returns whether address can distribute from repo (from contract)

   - `GET /distribution/:distributionId`

     - Returns full distribution details (from contract)

   - `GET /tokens/whitelisted`

     - Returns list of whitelisted tokens (from contract)

   - `GET /config`

     - Returns system config (fee, batchLimit, feeRecipient, etc.) (from contract)

   - `GET /nonce/recipient/:address`
     - Returns current nonce for recipient (from contract)

   **Indexer-Based Routes (Historical Events):**

   - `GET /funding/repo/:repoId/:accountId`

     - Returns all funding transactions for a repo (from FundedRepo table)

   - `GET /funding/by-sender/:address`

     - Returns all funding transactions made by a specific sender (from FundedRepo table)

   - `GET /funding/recent`

     - Returns recent funding transactions across all repos (from FundedRepo table)

   - `GET /batch/:batchId`

     - Returns batch details with all items (from batch tables)

   - `GET /batches/repo/:repoId/:accountId`

     - Returns all batches for a repo (from DistributedFromRepoBatch, ReclaimedRepoDistributionsBatch)

   - `GET /batches/sender/:address`

     - Returns all batches for a sender (from DistributedFromSenderBatch by payer)

   - `GET /batches/recipient/:githubId`

     - Returns all claim batches for a recipient (from ClaimedBatch)

   - `GET /batches/recent`

     - Returns recent batches across the system (from all batch tables)

   - `GET /reclaims/repo-funds/:repoId/:accountId`

     - Returns history of repo fund reclaims (from ReclaimedRepoFunds)

   - `GET /reclaims/repo-distributions/:repoId/:accountId`

     - Returns history of repo distribution reclaims (from ReclaimedRepoDistributionsBatch)

   - `GET /reclaims/by-admin/:address`

     - Returns all reclaims performed by a specific admin (from ReclaimedRepoFunds, ReclaimedRepoDistribution)

   - `GET /fees/collected`

     - Returns total fees collected by the system (from Claimed table)

   - `GET /fees/by-token/:token`

     - Returns fees collected for a specific token (from Claimed table)

   - `GET /fees/from-user/:githubId`
     - Returns total fees paid by a specific user through claims (from Claimed table)

   **Hybrid Routes (Contract + Indexer):**

   - `GET /balance/merit/:githubId`

     - Returns Merit Balance (claimed from indexer + claimable from contract)

   - `GET /payments/incoming/:githubId`

     - Returns all incoming payments (from DistributedFromRepo/DistributedFromSender tables)

   - `GET /payments/outgoing/:githubId`

     - Returns all outgoing payments (from DistributedFromSender by payer + repo distributions where user is admin)

   - `GET /distributions/claimable/:githubId`

     - Returns all claimable distributions for recipient (contract state filtered by recipient)

   - `GET /distributions/expired/:githubId`

     - Returns all expired distributions for recipient (contract state filtered by recipient + deadline)

   - `GET /distributions/to/:githubId`

     - Returns ALL distributions sent to recipient (from DistributedFromRepo/DistributedFromSender tables)

   - `GET /distributions/to/:githubId/claimed`

     - Returns claimed distributions for recipient (from Claimed table)

   - `GET /distributions/to/:githubId/unclaimed`

     - Returns unclaimed distributions for recipient (contract state - claimed)

   - `GET /distributions/repo/:repoId/:accountId`

     - Returns all distributions from a repo (from DistributedFromRepo table)

   - `GET /distributions/sender/:address`

     - Returns all distributions from a sender (from DistributedFromSender by payer)

   - `GET /batches/paid-to/:githubId`

     - Returns all batches containing distributions paid TO recipient (from DistributedFromRepo/DistributedFromSender tables)

   - `GET /batches/paid-to/:githubId/unclaimed`

     - Returns batches with unclaimed distributions (indexer + contract state)

   - `GET /batches/paid-to/:githubId/claimed`

     - Returns batches where recipient has claimed distributions (from ClaimedBatch)

   - `GET /transactions/user/:githubId`

     - Returns complete transaction history (all relevant tables + contract state)

   - `GET /transactions/repo/:repoId/:accountId`

     - Returns complete repo transaction history (all relevant tables for the repo)

   - `GET /transactions/recent`
     - Returns recent transactions across the entire system (all tables)

   **Admin Dashboard Routes:**

   - `GET /admin/repo/:repoId/:accountId/overview`
     - Returns complete repo overview (contract state + indexer summaries)

Each signature route will:

- Validate the request parameters
- Check permissions
- Generate and sign the appropriate message
- Return the signature and message for the frontend to submit to the blockchain

The indexer will process the blockchain transactions to update the database state.
