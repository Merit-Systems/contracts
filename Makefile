include .env

deploy:
	forge clean
	forge script script/Deploy.s.sol \
		--rpc-url $(BASE_INFURA_URL) \
		--sender 0xc9C88391e50eEADb43647fAC514fA26f8dFd7E7F \
		--broadcast \
		-i 1 \
		-vvvv \
		--via-ir \
		--verify \
		--optimize

flatten:
	forge clean
	forge flatten src/MeritLedger.sol > flatten.sol
	echo "Saved in flatten.sol"

deploy-split-with-lockup:
	forge script script/Deploy.SplitWithLockup.sol \
		--rpc-url $(SEPOLIA_INFURA_URL) \
		--sender 0x39053B170bBD9580d0b86e8317c685aEFB65f1ec \
		--broadcast \
		-i 1 \
		-vvvv \
		--via-ir \
		--verify \
		--optimize

test-escrow:
	forge t --match-path test/escrow/Escrow.t.sol 