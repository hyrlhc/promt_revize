// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title A minimal counter
contract Counter {
    uint256 public number;

    function increment() external {
        number += 1;
    }
}

