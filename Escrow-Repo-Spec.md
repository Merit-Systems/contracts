### EscrowRepo v2 — Quick Reference

**What it is**  
Repository "bank accounts".

---

#### Roles

- **Owner (Merit Systems)** – sets fee, whitelist, signer; signs EIP-712 messages for new repos/accounts.
- **Repo Admin** – controls a `(repoId, accountId)`; deposits claims, can reclaim, authorizes depositors.
- **Funder** – anyone calling `fund()`.
- **Recipient** – pulls their claim after being authorised via EIP-712 signature.
- **Signer** – off-chain backend that issues EIP-712 signatures to enable claiming.
- **Authorized Depositor** – addresses authorized by repo admin to call `deposit()` functions.

---

#### Repo & Account Creation

**Repos** are created via `addRepo()` with owner's EIP-712 signature:

- First account (accountId=0) is automatically created for the specified admin
- Additional accounts can be created via `addAccount()` (also requires owner signature)

Each account within a repo:

- Has its own admin
- Maintains separate pool balances, fundings, and claims
- Operates independently within the same repo

---

#### Token Journey

| Step                   | Call                                         | What happens                                                                                                                  |
| ---------------------- | -------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| 1. **Fund**            | `fund()`                                     | Tokens sent in ➜ fee (≤10%) to `feeRecipient`; net added to `_balance`.                                                       |
| 2. **Deposit**         | `deposit()` / `batchDeposit()`               | Admin or authorized depositor earmarks **amount** & `deadline` for recipient → new **Claim** record (funds stay in contract). |
| 3. **Claim**           | `claim()` / `batchClaim()`                   | Recipient proves `canClaim=true` (Signer EIP-712 signature). If before `deadline`, tokens sent and claim → _Claimed_.         |
| 4. **Reclaim fund**    | `reclaimFund()`                              | If account has no active deposits, admin withdraws unused pool balance.                                                       |
| 5. **Reclaim deposit** | `reclaimDeposit()` / `batchReclaimDeposit()` | After `deadline`, admin returns expired claim to pool (status → _Reclaimed_).                                                 |
