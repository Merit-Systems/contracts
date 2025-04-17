// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

library DepositEncoder {
    uint constant ENCODING_VERSION = 1;

    enum DEPOSIT_TYPE {
        REPO,
        SOLO
    }

    function encode(
        DEPOSIT_TYPE depositType,
        uint         repoId,
        uint         timestamp
    ) internal pure returns (bytes memory) {
        return abi.encode(ENCODING_VERSION, depositType, repoId, timestamp);
    }
}
