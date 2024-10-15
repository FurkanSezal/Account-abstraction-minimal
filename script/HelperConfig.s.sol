//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {EntryPoint} from "lib/account-abstraction/contracts/core/EntryPoint.sol";

contract HelperConfig is Script {
    error HelperConfig__InvalidChainId();

    struct NetworkConfig {
        address entryPoint;
        address account;
    }

    uint256 constant ETH_SEPOLIA_CHAINID = 11155111;
    uint256 constant ZKSYNC_TESTNET_CHAINID = 300;
    uint256 constant ANVIL_CHAINID = 31337;
    address constant TEST_WALLET = 0xEaC9eDFE37fA378E8795253d292e6393d29aBCa2;
    address constant ANVIL_WALLET = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    NetworkConfig public localNetworkConfig;
    mapping(uint256 => NetworkConfig) public networkConfigs;

    constructor() {
        networkConfigs[ETH_SEPOLIA_CHAINID] = getEthSepoliaConfig();
        networkConfigs[ZKSYNC_TESTNET_CHAINID] = getZkSyncTestnetConfig();
    }

    function getConfig() public returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    function getConfigByChainId(uint256 chainId) public returns (NetworkConfig memory) {
        if (chainId == ANVIL_CHAINID) {
            return getOrCreateAnvilEthConfig();
        } else if (networkConfigs[chainId].account != address(0)) {
            return networkConfigs[chainId];
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }

    function getEthSepoliaConfig() internal pure returns (NetworkConfig memory) {
        return NetworkConfig({entryPoint: 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789, account: TEST_WALLET});
    }

    function getZkSyncTestnetConfig() internal pure returns (NetworkConfig memory) {
        return NetworkConfig({entryPoint: address(0), account: TEST_WALLET});
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (localNetworkConfig.account != address(0)) {
            return localNetworkConfig;
        }
        // deploy a mock entry point
        console2.log("deploying mocks...");
        vm.startBroadcast(ANVIL_WALLET);
        EntryPoint entryPoint = new EntryPoint();
        vm.stopBroadcast();
        console2.log("mocks deployed address: ", address(entryPoint));

        localNetworkConfig = NetworkConfig({entryPoint: address(entryPoint), account: ANVIL_WALLET});

        return localNetworkConfig;
    }
}
