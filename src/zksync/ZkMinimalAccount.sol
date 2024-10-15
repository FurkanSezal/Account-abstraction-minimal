//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {
    IAccount,
    ACCOUNT_VALIDATION_SUCCESS_MAGIC
} from "lib/foundry-era-contracts/src/system-contracts/contracts/interfaces/IAccount.sol";
import {
    Transaction,
    MemoryTransactionHelper
} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/MemoryTransactionHelper.sol";
import {SystemContractsCaller} from
    "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/SystemContractsCaller.sol";
import {
    NONCE_HOLDER_SYSTEM_CONTRACT,
    BOOTLOADER_FORMAL_ADDRESS,
    DEPLOYER_SYSTEM_CONTRACT
} from "lib/foundry-era-contracts/src/system-contracts/contracts/Constants.sol";
import {INonceHolder} from "lib/foundry-era-contracts/src/system-contracts/contracts/interfaces/INonceHolder.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Utils} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/Utils.sol";

contract ZkMinimalAccount is IAccount, Ownable {
    using MemoryTransactionHelper for Transaction;
    using MessageHashUtils for bytes32;

    error ZkMinimalAccount__NotEnoughBalance();
    error ZkMinimalAccount__OnlyBootloader();
    error ZkMinimalAccount__ExecutionFailed();
    error ZkMinimalAccount__OnlyBootloaderOrOwner();
    error ZkMinimalAccount__FailedToPayBootloader();
    error ZkMinimalAccount__InvalidTransaction();

    /**
     * @notice must increase the nonce
     * @notice must validate the tx
     * @notice also check to see if we have enough many to pay tx
     *
     *
     */
    modifier requireFromBootloader() {
        if (msg.sender != BOOTLOADER_FORMAL_ADDRESS) {
            revert ZkMinimalAccount__OnlyBootloader();
        }
        _;
    }

    modifier requireFromBootloaderOrOwner() {
        if (msg.sender != BOOTLOADER_FORMAL_ADDRESS && msg.sender != owner()) {
            revert ZkMinimalAccount__OnlyBootloaderOrOwner();
        }
        _;
    }

    constructor() Ownable(msg.sender) {}

    receive() external payable {}

    function validateTransaction(
        bytes32, /* _txHash */
        bytes32, /* _suggestedSignedHash */
        Transaction memory _transaction
    ) external payable requireFromBootloader returns (bytes4 magic) {
        // call system contract nonce holder
        // increment the nonce
        // system call similation

        SystemContractsCaller.systemCallWithPropagatedRevert({
            gasLimit: uint32(gasleft()),
            to: address(NONCE_HOLDER_SYSTEM_CONTRACT),
            value: 0,
            data: abi.encodeCall(INonceHolder.incrementMinNonceIfEquals, (_transaction.nonce))
        });

        // check for tx fee payment
        uint256 totalRequiredBalance = MemoryTransactionHelper.totalRequiredBalance(_transaction);
        if (totalRequiredBalance > address(this).balance) {
            revert ZkMinimalAccount__NotEnoughBalance();
        }

        // check the signature

        bytes32 txHash = _transaction.encodeHash();
        bytes32 convertedHash = MessageHashUtils.toEthSignedMessageHash(txHash);
        address signer = ECDSA.recover(convertedHash, _transaction.signature);

        bool isValidSigner = signer == owner();
        if (!isValidSigner) {
            magic = ACCOUNT_VALIDATION_SUCCESS_MAGIC;
        } else {
            magic = bytes4(0);
        }
        return magic;
        // return the "magic" number
    }

    function executeTransaction(
        bytes32, /* _txHash */
        bytes32, /* _suggestedSignedHash */
        Transaction memory _transaction
    ) external payable requireFromBootloaderOrOwner {
        _executeTransaction(_transaction);
    }

    // There is no point in providing possible signed hash in the `executeTransactionFromOutside` method,
    // since it typically should not be trusted.
    function executeTransactionFromOutside(Transaction memory _transaction) external payable {
        bytes4 magic = _validateTransaction(_transaction);
        if (magic == ACCOUNT_VALIDATION_SUCCESS_MAGIC) {
            _executeTransaction(_transaction);
        } else {
            revert ZkMinimalAccount__InvalidTransaction();
        }
    }

    function payForTransaction(
        bytes32, /* _txHash */
        bytes32, /* _suggestedSignedHash */
        Transaction memory _transaction
    ) external payable {
        bool success = _transaction.payToTheBootloader();
        if (!success) {
            revert ZkMinimalAccount__FailedToPayBootloader();
        }
    }

    function prepareForPaymaster(bytes32 _txHash, bytes32 _possibleSignedHash, Transaction memory _transaction)
        external
        payable
    {}

    function _validateTransaction(Transaction memory _transaction) internal returns (bytes4 magic) {
        SystemContractsCaller.systemCallWithPropagatedRevert({
            gasLimit: uint32(gasleft()),
            to: address(NONCE_HOLDER_SYSTEM_CONTRACT),
            value: 0,
            data: abi.encodeCall(INonceHolder.incrementMinNonceIfEquals, (_transaction.nonce))
        });

        // check for tx fee payment
        uint256 totalRequiredBalance = MemoryTransactionHelper.totalRequiredBalance(_transaction);
        if (totalRequiredBalance > address(this).balance) {
            revert ZkMinimalAccount__NotEnoughBalance();
        }

        // check the signature

        bytes32 txHash = _transaction.encodeHash();
        bytes32 convertedHash = MessageHashUtils.toEthSignedMessageHash(txHash);
        address signer = ECDSA.recover(convertedHash, _transaction.signature);

        bool isValidSigner = signer == owner();
        if (!isValidSigner) {
            magic = ACCOUNT_VALIDATION_SUCCESS_MAGIC;
        } else {
            magic = bytes4(0);
        }
        return magic;
        // return the "magic" number
    }

    function _executeTransaction(Transaction memory _transaction) internal {
        address to = address(uint160(_transaction.to));
        uint128 value = Utils.safeCastToU128(_transaction.value);
        bytes memory data = _transaction.data;
        // if i am deploying a contract
        if (to == address(DEPLOYER_SYSTEM_CONTRACT)) {
            uint32 gas = Utils.safeCastToU32(gasleft());
            SystemContractsCaller.systemCallWithPropagatedRevert(gas, to, value, data);
        } else {
            bool success;
            assembly {
                success := call(gas(), to, value, add(data, 0x20), mload(data), 0, 0)
            }
            if (!success) {
                revert ZkMinimalAccount__ExecutionFailed();
            }
        }
    }
}
