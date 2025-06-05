### EscrowRepo v2 — Quick Reference

**What it is**  
ERC-20 escrow pool. Repo admins earmark pooled funds as individual **claims** with expiry windows.

---

#### Roles

- **Owner** – sets fee, whitelist, signer; signs new repos/accounts.
- **Repo Admin** – controls a `(repoId, accountId)`; deposits claims, can reclaim.
- **Funder** – anyone calling `fund()`.
- **Recipient** – pulls their claim after being authorised.
- **Signer** – off-chain backend that issues EIP-712 signatures to enable claiming.
- **Authorized Depositor** – addresses authorized by repo admin to call `deposit()` functions.

---

#### Repo Accounts

Each repo can have **multiple accounts** (identified by `accountId`). Each account:

- Has its own admin (can be different people)
- Maintains separate pool balances, fundings, and claims
- Operates independently within the same repo

---

#### Depositor Management

The repo admin can authorize additional addresses to call `deposit()` functions:

- **`authorizeDepositor()`** – Admin grants deposit permission to an address
- **`deauthorizeDepositor()`** – Admin revokes deposit permission from an address
- **`batchAuthorizeDepositors()`** – Admin grants permission to multiple addresses
- **`batchDeauthorizeDepositors()`** – Admin revokes permission from multiple addresses
- **`isAuthorizedDepositor()`** – Check if an address is authorized to deposit
- **`canDeposit()`** – Check if an address can deposit (admin or authorized)

---

#### Token journey

| Step                   | Call               | What happens                                                                                                                       |
| ---------------------- | ------------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| 1. **Fund**            | `fund()`           | Tokens sent in ➜ fee (≤10 %) to `feeRecipient`; net added to `_balance`.                                                           |
| 2. **Deposit**         | `deposit()`        | Admin or authorized depositor earmarks an **amount** & `deadline` for a recipient → new **Claim** record (funds stay in contract). |
| 3. **Claim**           | `claim()`          | Recipient proves `canClaim=true` (Signer signature). If before `deadline`, tokens sent and claim ➜ _Claimed_.                      |
| 4. **Reclaim pool**    | `reclaimFund()`    | If account has no active claims, admin withdraws unused pool balance.                                                              |
| 5. **Reclaim deposit** | `reclaimDeposit()` | After `deadline`, admin returns expired claim to pool (status ➜ _Reclaimed_).                                                      |

---

#### Safety

- Max protocol fee: **10 %** (`MAX_FEE_BPS = 1000`).
- Only whitelisted ERC-20 tokens accepted.
- Transfers use `SafeTransferLib`.
