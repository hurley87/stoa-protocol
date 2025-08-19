// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts/access/Ownable.sol";

contract StoaProtocol is Ownable {
    struct QuestionMeta {
        address questionAddress;
        address creator;
        uint256 submissionCost;
        uint256 duration;
        uint8 maxWinners;
        uint256 createdAt;
    }

    QuestionMeta[] public allQuestions;

    event QuestionRegistered(
        uint256 indexed id,
        address indexed question,
        address indexed creator,
        uint256 submissionCost,
        uint256 duration,
        uint8 maxWinners
    );

    constructor() Ownable() {}

    function registerQuestion(
        address questionAddress,
        address creator,
        uint256 submissionCost,
        uint256 duration,
        uint8 maxWinners
    ) external onlyOwner {
        require(questionAddress != address(0), "Invalid question address");
        require(creator != address(0), "Invalid creator address");
        require(submissionCost > 0, "Submission cost must be greater than 0");
        require(duration > 0, "Duration must be greater than 0");

        allQuestions.push(
            QuestionMeta({
                questionAddress: questionAddress,
                creator: creator,
                submissionCost: submissionCost,
                duration: duration,
                maxWinners: maxWinners,
                createdAt: block.timestamp
            })
        );

        emit QuestionRegistered(allQuestions.length - 1, questionAddress, creator, submissionCost, duration, maxWinners);
    }

    function getQuestion(uint256 id) external view returns (QuestionMeta memory) {
        return allQuestions[id];
    }

    function getAllQuestions() external view returns (QuestionMeta[] memory) {
        return allQuestions;
    }

    function getQuestionCount() external view returns (uint256) {
        return allQuestions.length;
    }
}
