Notes for Auditors

- Accepted ERC-20 Types: wETH, USDC
- Chains: Base
- Addresses can only claim if whitelisted by us with the signature
- All functions are mostly called by smart wallets (privy)
- Anyone claiming/reclaiming distributions is acceptable behavior for us
- Distributors remain authorized even after admin changes (by design)
- No ability to remove whitelisted tokens is intentional - prevents us from pausing the contract
- Fee mechanism has 10% maximum cap (MAX_FEE = 1,000 basis points)
- Batch operations are limited by configurable batchLimit to prevent gas issues
- EIP-712 signatures used for claim authorization and admin initialization
- Nonce-based replay protection for both recipient claims and owner operations
- Two distribution types: Repo (from deposited funds) and Solo (direct payment)
- Expired distributions can be reclaimed - repo funds return to account balance, solo funds return to original payer
- Contract tracks separate balances per repoId/accountId combination
- hasDistributions flag prevents fund reclaim once any distributions have occurred
