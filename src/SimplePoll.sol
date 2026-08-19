// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title A minimal yes/no poll for learning Foundry
contract SimplePoll {
    string public question;
    uint256 public yesVotes;
    uint256 public noVotes;

    constructor(string memory question_) {
        question = question_;
    }

    function vote(bool support) external {
        if (support) {
            yesVotes += 1;
        } else {
            noVotes += 1;
        }
    }
}

