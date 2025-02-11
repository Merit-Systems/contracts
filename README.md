# Merit Contracts

## Definitions

1. `PR` (Pull Request):

   Set of `(address, score)`

2. `PRs` (List of Pull Requests)

   Ordered List of PRs `[PR_1, PR_2, PR_3, … ]`

3. `CT` (Cap Table)

   Mapping from `address` => `weight`

4. `F` State Update Function

   New `CT'` = `F(CT, PRs)`

5. `Claim` is the set of `(address, amount, last_update, unlocked)`

### Ownership

Ownership is represented by one NFT.

### CT Initialization

`CT` is seeded by Repo owners.

### CT Update

Additive: Add `PR` score to `CT` entry.

### Claiming

1. Time Based

Rewards are distributed relative to the current `CT` after a fixed period of time.
For example If I own 20% of the `CT` and $100 are distributed for this time window I get $20.

#### Merkle Root Update

For every state update a new Merkle Root with the updated rewards to claim is posted on-chain. These rewards can be unlocked or locked.

For every unlock, a new merkle root is posted on-chain.

If rewards are not claimed after time X they can be claimed by the owner.

### Wallet Abstraction

You need to map every user on GitHub for that repo to an Ethereum Address.
