#!/bin/bash
set -e

# Inputs for Escrow contract
OWNER=0x7163a6C74a3caB2A364F9aDD054bf83E50A1d8Bc
SIGNER=0x7F26a8d1A94bD7c1Db651306f503430dF37E9037
TOKENS="[0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913]"
FEE_BPS=250
BATCH_LIMIT=500

# Create2 configuration
FACTORY=0x4e59b44847b379578588920ca78fbf26c0b4956c
CALLER=0xC710b407f46823cBbdbDE6D344B8992c3062012F

# Get contract creation bytecode from forge
echo "Getting creation bytecode..."
BYTECODE=$(forge inspect Escrow bytecode | cut -c3-)

# Encode constructor arguments
echo "Encoding constructor arguments..."
ARGS=$(cast abi-encode "constructor(address,address,address[],uint256,uint256)" \
  $OWNER $SIGNER "$TOKENS" $FEE_BPS $BATCH_LIMIT | cut -c3-)

# Concatenate bytecode + constructor args
INIT_CODE="${BYTECODE}${ARGS}"

# Get init code hash
echo "Calculating init_code_hash..."
INIT_CODE_HASH=$(cast keccak 0x$INIT_CODE)

echo "INIT_CODE_HASH = $INIT_CODE_HASH"

# Run create2 crunch with the generated hash
export FACTORY=$FACTORY
export CALLER=$CALLER
export INIT_CODE_HASH=$INIT_CODE_HASH

echo "Running create2 crunch..."
# Parameters: factory caller init_code_hash gpu_device(255=CPU) leading_zeros total_zeros(255=disabled)
cargo run --release $FACTORY $CALLER $INIT_CODE_HASH 0 4 255