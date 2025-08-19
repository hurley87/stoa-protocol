// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./StoaQuestion.sol";
import "./StoaProtocol.sol";
import "openzeppelin-contracts/access/Ownable.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract StoaQuestionFactory is Ownable {
    address public evaluator;
    address public treasury;
    address public reputation;
    StoaProtocol public protocolRegistry;

    uint256 public questionCount;
    mapping(address => bool) public isWhitelisted;
    address[] public allQuestions;

    event QuestionCreated(
        uint256 indexed questionId,
        address indexed question,
        address indexed creator,
        address token,
        uint256 submissionCost,
        uint256 duration,
        uint8 maxWinners,
        uint256 seedAmount
    );

    constructor(address _evaluator, address _treasury, address _reputation, address _protocolRegistry) {
        _transferOwnership(msg.sender);
        evaluator = _evaluator;
        treasury = _treasury;
        reputation = _reputation;
        protocolRegistry = StoaProtocol(_protocolRegistry);
    }

    function whitelistCreator(address user, bool allowed) external onlyOwner {
        isWhitelisted[user] = allowed;
    }

    function createQuestion(
        address token,
        uint256 submissionCost,
        uint256 duration,
        uint8 maxWinners,
        uint256 seedAmount
    ) external returns (address) {
        require(isWhitelisted[msg.sender], "Not whitelisted");
        require(token != address(0), "Invalid token");

        StoaQuestion q = new StoaQuestion(token, submissionCost, duration, maxWinners, evaluator, treasury, reputation);

        q.transferOwnership(msg.sender);

        if (seedAmount > 0) {
            IERC20(token).transferFrom(msg.sender, address(this), seedAmount);
            IERC20(token).approve(address(q), seedAmount);
            q.seedQuestion(seedAmount);
        }

        allQuestions.push(address(q));
        questionCount++;

        emit QuestionCreated(
            questionCount, address(q), msg.sender, token, submissionCost, duration, maxWinners, seedAmount
        );

        protocolRegistry.registerQuestion(address(q), msg.sender, submissionCost, duration, maxWinners);

        return address(q);
    }

    function getAllQuestions() external view returns (address[] memory) {
        return allQuestions;
    }
}
