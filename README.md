# Merit Contracts

We have one contract called [Escrow.sol](./src/Escrow.sol)

| Single Operation | Batch Operation | Description                                     |
| ---------------- | --------------- | ----------------------------------------------- |
| `deposit`        | `batchDeposit`  | Deposit tokens into escrow                      |
| `claim`          | `batchClaim`    | Claim tokens as the recipient                   |
| `reclaim`        | `batchReclaim`  | Reclaim tokens as the sender after claim period |

### Build

`forge build`

### Test

`forge test`

### Deploy

##### Sepolia

`make deploy-sepolia`

##### Base Sepolia

`make deploy-base-sepolia`

##### Base

`make deploy-base`

### Audits

All reports are in [audits](./audits/)
