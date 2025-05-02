# Create2Crunch Vanity Address Miner

This project uses [create2crunch](https://github.com/0age/create2crunch) to mine for vanity addresses using the CREATE2 opcode. It allows you to find specific contract addresses that match desired patterns.

## Overview

The project mines for salt values that, when used with the CREATE2 opcode, generate contract addresses matching specific patterns. This is particularly useful for creating contracts at predictable addresses.

## Prerequisites

- Rust (for building create2crunch)
- Foundry (for contract compilation)
- Bash shell

## Usage

1. Configure the parameters in `run.sh`:

   - `OWNER`: Contract owner address
   - `SIGNER`: Signer address
   - `TOKENS`: Array of token addresses
   - `FEE_BPS`: Fee basis points
   - `BATCH_LIMIT`: Batch size limit
   - `FACTORY`: Factory contract address
   - `CALLER`: Caller address

2. Run the mining script:
   ```bash
   ./run.sh
   ```

The script will:

- Compile the contract
- Generate the initialization code
- Calculate the init code hash
- Run create2crunch to find matching salt values

## Configuration

All configuration parameters are set in `run.sh`. The default values are:

- Factory address: `0x4e59b44847b379578588920ca78fbf26c0b4956c`
- Caller address: `0xC710b407f46823cBbdbDE6D344B8992c3062012F`

You can modify these values in the script to match your deployment requirements.

## License

This project is based on [create2crunch](https://github.com/0age/create2crunch) by 0age.
