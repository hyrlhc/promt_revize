// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SimplePoll} from "../src/SimplePoll.sol";

contract SimplePollTest {
    SimplePoll private poll;

    function setUp() public {
        poll = new SimplePoll("Foundry'yi ogreniyor muyuz?");
    }

    function testInitialState() public view {
        require(keccak256(bytes(poll.question())) == keccak256(bytes("Foundry'yi ogreniyor muyuz?")));
        require(poll.yesVotes() == 0);
        require(poll.noVotes() == 0);
    }

    function testYesVote() public {
        poll.vote(true);

        require(poll.yesVotes() == 1);
        require(poll.noVotes() == 0);
    }

    function testNoVote() public {
        poll.vote(false);

        require(poll.yesVotes() == 0);
        require(poll.noVotes() == 1);
    }
}

