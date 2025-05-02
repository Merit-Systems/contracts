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

### Create2Crunch Vanity Address Mining

The project includes a vanity address miner using [create2crunch](https://github.com/0age/create2crunch) to find specific contract addresses that match desired patterns. This is particularly useful for creating contracts at predictable addresses.

To use create2crunch:

1. Navigate to the create2crunch directory:

   ```bash
   cd create2crunch
   ```

2. Configure the parameters in `run.sh`:

   - `OWNER`: Contract owner address
   - `SIGNER`: Signer address
   - `TOKENS`: Array of token addresses
   - `FEE_BPS`: Fee basis points
   - `BATCH_LIMIT`: Batch size limit
   - `FACTORY`: Factory contract address
   - `CALLER`: Caller address

3. Run the mining script:
   ```bash
   ./run.sh
   ```

The script will compile the contract, generate the initialization code, and use create2crunch to find salt values that generate contract addresses matching your desired patterns.

For more detailed information, see the [create2crunch README](./create2crunch/README.md).
