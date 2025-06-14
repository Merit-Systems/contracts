###############################################################################
# Makefile for Foundry Deployment & Testing
###############################################################################
include .env

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------
# RPC URLs (override if you wish, e.g., `make deploy BASE_RPC=...`)
BASE_RPC         ?= $(BASE_INFURA_URL)
SEPOLIA_RPC      ?= $(SEPOLIA_INFURA_URL)
BASE_SEPOLIA_RPC ?= $(BASE_SEPOLIA_INFURA_URL)

# Sender addresses
BASE_SENDER      ?= 0xC710b407f46823cBbdbDE6D344B8992c3062012F
SEPOLIA_SENDER   ?= 0x39053B170bBD9580d0b86e8317c685aEFB65f1ec

# Common Forge script flags
FORGE_COMMON_FLAGS = \
	--broadcast \
	-i 1 \
	-vvvv \
	--via-ir \
	--verify \
	--optimize

# Base-specific flags
BASE_FLAGS = $(FORGE_COMMON_FLAGS) --etherscan-api-key $(BASE_ETHERSCAN_API_KEY)

# Sepolia-specific flags
SEPOLIA_FLAGS = $(FORGE_COMMON_FLAGS) --etherscan-api-key $(ETH_ETHERSCAN_API_KEY)

# ---------------------------------------------------------------------------
# Deployment & Setup Targets
# ---------------------------------------------------------------------------

.PHONY: deploy deploy-sepolia deploy-base-sepolia deploy-base deploy-anvil \
		deposit-count recipient-nonces flatten \
		test-escrow test-escrow-with-fee gas create-payments

# ----------------------
# Deploy to Sepolia
# ----------------------
deploy-sepolia:
	forge script script/Deploy.Sepolia.sol \
		--rpc-url $(SEPOLIA_RPC) \
		--sender $(SEPOLIA_SENDER) \
		$(SEPOLIA_FLAGS)

# ----------------------
# Deploy to Base Sepolia
# ----------------------
deploy-base-sepolia:
	forge script script/Deploy.BaseSepolia.s.sol \
		--rpc-url $(BASE_SEPOLIA_RPC) \
		--sender $(SEPOLIA_SENDER) \
		$(BASE_FLAGS)

# ----------------------
# Deploy to Base Mainnet
# ----------------------
deploy-base:
	forge clean
	forge script script/Deploy.Base.s.sol \
		--rpc-url $(BASE_RPC) \
		--sender $(BASE_SENDER) \
		$(BASE_FLAGS)

# ----------------------
# Deploy to Anvil (Local)
# ----------------------
deploy-anvil:
	forge script script/Deploy.Anvil.s.sol:DeployAnvil \
		--fork-url http://localhost:8545 \
		--broadcast \
		--unlocked \
		-vvvv \
		--via-ir

# ---------------------------------------------------------------------------
# Testing Targets
# ---------------------------------------------------------------------------

test-escrow:
	forge test --match-path test/Escrow.t.sol

# ---------------------------------------------------------------------------
# Utility Scripts
# ---------------------------------------------------------------------------

gas:
	forge script script/utils/Gas.s.sol

create-payments:
	forge script script/utils/CreatePayments.s.sol \
		--rpc-url $(SEPOLIA_RPC) \
		--sender $(SEPOLIA_SENDER) \
		--broadcast \
		-i 1 \
		-vvvv
