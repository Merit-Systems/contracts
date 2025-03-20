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

deposit-count:
	cast call 0xc095C6D52Eb4aD0A13692DD214F329Ff3b8285e2 "depositCount()(uint256)" --rpc-url https://sepolia.infura.io/v3/485c1cc01d9c4606afd4f6e3bc38beb7

flatten:
	forge clean
	forge flatten src/MeritLedger.sol > flatten.sol
	echo "Saved in flatten.sol"

test-escrow:
	forge t --match-path test/Escrow.t.sol 

deploy-sepolia:
	forge script script/Deploy.Sepolia.sol \
		--rpc-url $(SEPOLIA_INFURA_URL) \
		--sender 0x39053B170bBD9580d0b86e8317c685aEFB65f1ec \
		--broadcast \
		-i 1 \
		-vvvv \
		--via-ir \
		--verify \
		--optimize

deploy-base:
	forge clean
	forge script script/Deploy.Base.s.sol \
		--rpc-url $(BASE_INFURA_URL) \
		--sender 0x39053B170bBD9580d0b86e8317c685aEFB65f1ec \
		--broadcast \
		-i 1 \
		-vvvv \
		--via-ir \
		--verify \
		--optimize
