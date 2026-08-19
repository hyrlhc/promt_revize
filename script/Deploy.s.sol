// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SimplePoll} from "../src/SimplePoll.sol";

interface Vm {
    function startBroadcast() external;
    function stopBroadcast() external;
}

contract Deploy {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function run() external returns (SimplePoll poll) {
        vm.startBroadcast();
        poll = new SimplePoll("Foundry'yi ogreniyor muyuz?");
        vm.stopBroadcast();
    }
}

