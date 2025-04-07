# Merit Contracts

## Deposit Data Encoding

Deposit data is encoded using standard Ethereum ABI encoding rules for the following tuple structure:

`(uint8 version, uint8 paymentType, bytes32 repoId, bytes32 timestamp)`

- **`version` (uint8):** The encoding version number. Currently `0x01`.
- **`paymentType` (uint8):** Indicates the type of payment.
  - `0x00`: Solo Payment
  - `0x01`: Repo Payment
- **`repoId` (bytes32):** A unique identifier for the repository associated with the payment.
  - **Note:** If `paymentType` is `0x00` (Solo Payment), the `repoId` field is not relevant and can be ignored by the consumer or set to a default value (e.g., `bytes32(0)`) by the producer.
- **`timestamp` (bytes32)**: Timestamp of the snapshot

**Note on ABI Encoding:** According to standard ABI encoding rules for static types within a tuple, each element is padded to occupy 32 bytes. Therefore:

- The `uint8 version` is encoded as a 32-byte word.
- The `uint8 paymentType` is encoded as a 32-byte word.
- The `bytes32 timestamp` occupies 32 bytes.
- The `bytes32 repoId` occupies 32 bytes.

The total length of the ABI-encoded data is **128 bytes**.
