// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IsletmeKimligi} from "../src/IsletmeKimligi.sol";

interface VmKimlikDeploy {
    function startBroadcast() external;
    function stopBroadcast() external;
}

/// @notice Base Sepolia'daki mevcut İşletme Haritasına kimlik NFT'si bağlar
contract DeployIsletmeKimligi {
    VmKimlikDeploy private constant vm = VmKimlikDeploy(address(uint160(uint256(keccak256("hevm cheat code")))));
    address private constant ISLETME_HARITASI = 0xea004DbD58F988da2752388cf80D1e0dDB5777ed;

    function run() external returns (IsletmeKimligi kimlik) {
        vm.startBroadcast();
        kimlik = new IsletmeKimligi(ISLETME_HARITASI);
        vm.stopBroadcast();
    }
}
