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
BASE_SENDER      ?= 0xc9C88391e50eEADb43647fAC514fA26f8dFd7E7F
SEPOLIA_SENDER   ?= 0x39053B170bBD9580d0b86e8317c685aEFB65f1ec

# Common Forge script flags
FORGE_COMMON_FLAGS = \
	--broadcast \
	-i 1 \
	-vvvv \
	--via-ir \
	--verify \
	--optimize

# ---------------------------------------------------------------------------
# Deployment & Setup Targets
# ---------------------------------------------------------------------------

.PHONY: deploy deploy-sepolia deploy-base-sepolia deploy-base \
		deposit-count recipient-nonces flatten \
		test-escrow test-escrow-with-fee gas create-payments

# ----------------------
# Deploy to "base"
# ----------------------
deploy:
	forge clean
	forge script script/Deploy.s.sol \
		--rpc-url $(BASE_RPC) \
		--sender $(BASE_SENDER) \
		$(FORGE_COMMON_FLAGS)

# ----------------------
# Deploy to Sepolia
# ----------------------
deploy-sepolia:
	forge script script/Deploy.Sepolia.sol \
		--rpc-url $(SEPOLIA_RPC) \
		--sender $(SEPOLIA_SENDER) \
		$(FORGE_COMMON_FLAGS)

# ----------------------
# Deploy base -> Sepolia
# ----------------------
deploy-base-sepolia:
	forge script script/Deploy.BaseSepolia.s.sol \
		--rpc-url $(BASE_SEPOLIA_RPC) \
		--sender $(SEPOLIA_SENDER) \
		$(FORGE_COMMON_FLAGS)

# ----------------------
# Deploy to Base mainnet
# ----------------------
deploy-base:
	forge clean
	forge script script/Deploy.Base.s.sol \
		--rpc-url $(BASE_RPC) \
		--sender $(SEPOLIA_SENDER) \
		$(FORGE_COMMON_FLAGS)

# ---------------------------------------------------------------------------
# Testing Targets
# ---------------------------------------------------------------------------

test-escrow:
	forge test --match-path test/Escrow.t.sol

test-escrow-with-fee:
	forge test --match-path test/EscrowWithFee.t.sol

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
