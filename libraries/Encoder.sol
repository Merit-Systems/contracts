// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

library DepositEncoder {
    uint8 constant ENCODING_VERSION = 1;

    enum DEPOSIT_TYPE {
        REPO,
        SOLO
    }

    function encode(
        DEPOSIT_TYPE depositType,
        uint64       repoId,
        uint64       timestamp
    ) internal pure returns (bytes memory) {
        return abi.encode(ENCODING_VERSION, depositType, repoId, timestamp);
    }
}
