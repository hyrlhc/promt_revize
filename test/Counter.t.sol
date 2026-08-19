// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Counter} from "../src/Counter.sol";

contract CounterTest {
    function testInitialNumberIsZero() public {
        Counter counter = new Counter();

        require(counter.number() == 0);
    }

    function testIncrement() public {
        Counter counter = new Counter();

        counter.increment();

        require(counter.number() == 1);
    }
}
