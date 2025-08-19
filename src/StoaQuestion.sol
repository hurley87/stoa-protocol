// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts/access/Ownable.sol";

import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "./StoaBase.sol";
import "./StoaReputation.sol";

contract StoaQuestion is StoaBase {
    struct Answer {
        address responder;
        bytes32 answerHash;
        uint256 timestamp;
        uint256 score;
        bool rewarded;
    }

    IERC20 public token; // Single token for everything
    address public evaluator;
    StoaReputation public reputation;

    uint256 public submissionCost;
    uint256 public totalRewardPool; // Single reward pool
    uint256 public endsAt;
    uint256 public evaluationDeadline; // Deadline for evaluation
    uint256 private cachedTotalScore; // Cached total score after evaluation

    uint256 private constant BASIS_POINTS = 10000; // 100% = 10000 basis points
    uint8 public maxWinners;
    address public creator;

    Answer[] public answers;
    mapping(address => uint256) public userAnswerIndex;
    bool public evaluated;

    mapping(address => bool) public isAuthorizedSubmitter;

    event AnswerSubmitted(address indexed responder, uint256 index);
    event Evaluated(uint256[] rankedAnswerIndices);
    event RewardClaimed(address indexed user, uint256 amount);
    event Seeded(address indexed funder, uint256 amount);

    modifier onlyEvaluator() {
        require(msg.sender == evaluator, "Not evaluator");
        _;
    }

    modifier onlyBeforeEnd() {
        require(block.timestamp < endsAt, "Question ended");
        _;
    }

    modifier onlyAuthorizedSubmitter() {
        require(isAuthorizedSubmitter[msg.sender], "Not allowed");
        _;
    }

    constructor(
        address _token,
        uint256 _submissionCost,
        uint256 _duration,
        uint8 _maxWinners,
        address _evaluator,
        address _treasury,
        address _reputation
    ) StoaBase(_treasury) {
        token = IERC20(_token);
        submissionCost = _submissionCost;
        endsAt = block.timestamp + _duration;
        evaluationDeadline = endsAt + 7 days; // 7 days after question ends
        maxWinners = _maxWinners;
        evaluator = _evaluator;
        reputation = StoaReputation(_reputation);
        creator = msg.sender;
    }

    function setSubmitter(address submitter, bool allowed) external onlyOwner {
        isAuthorizedSubmitter[submitter] = allowed;
    }

    function seedQuestion(uint256 amount) public {
        require(amount > 0, "Amount must be greater than 0");
        token.transferFrom(msg.sender, address(this), amount);
        totalRewardPool += amount;
        emit Seeded(msg.sender, amount);
    }

    function submitAnswer(bytes32 answerHash) external onlyBeforeEnd {
        require(userAnswerIndex[msg.sender] == 0, "Already submitted");

        if (submissionCost > 0) {
            uint256 protocolCut = (submissionCost * feeBps) / BASIS_POINTS;
            uint256 creatorCut = (submissionCost * creatorFeeBps) / BASIS_POINTS;
            uint256 rewardCut = submissionCost - protocolCut - creatorCut;

            token.transferFrom(msg.sender, treasury, protocolCut);
            token.transferFrom(msg.sender, creator, creatorCut);
            token.transferFrom(msg.sender, address(this), rewardCut);
            totalRewardPool += rewardCut;
        }

        answers.push(
            Answer({
                responder: msg.sender,
                answerHash: answerHash,
                timestamp: block.timestamp,
                score: 0,
                rewarded: false
            })
        );

        userAnswerIndex[msg.sender] = answers.length;
        emit AnswerSubmitted(msg.sender, answers.length - 1);
    }

    function submitAnswerFor(address user, bytes32 answerHash) external onlyAuthorizedSubmitter onlyBeforeEnd {
        require(user != address(0), "Invalid user");
        require(userAnswerIndex[user] == 0, "Already submitted");

        if (submissionCost > 0) {
            uint256 protocolCut = (submissionCost * feeBps) / BASIS_POINTS;
            uint256 creatorCut = (submissionCost * creatorFeeBps) / BASIS_POINTS;
            uint256 rewardCut = submissionCost - protocolCut - creatorCut;

            token.transferFrom(msg.sender, treasury, protocolCut);
            token.transferFrom(msg.sender, creator, creatorCut);
            token.transferFrom(msg.sender, address(this), rewardCut);
            totalRewardPool += rewardCut;
        }

        answers.push(
            Answer({responder: user, answerHash: answerHash, timestamp: block.timestamp, score: 0, rewarded: false})
        );

        userAnswerIndex[user] = answers.length;
        emit AnswerSubmitted(user, answers.length - 1);
    }

    function evaluateAnswers(uint256[] calldata rankedIndices) external onlyEvaluator {
        require(!evaluated, "Already evaluated");
        require(block.timestamp >= endsAt, "Too early");
        require(rankedIndices.length <= maxWinners, "Too many winners");

        uint256 totalScoreSum = 0;
        for (uint256 i = 0; i < rankedIndices.length; i++) {
            require(rankedIndices[i] < answers.length, "Invalid answer index");
            uint256 score = maxWinners - i;
            answers[rankedIndices[i]].score = score;
            totalScoreSum += score;
        }

        evaluated = true;
        cachedTotalScore = totalScoreSum; // Cache the total score
        emit Evaluated(rankedIndices);
    }

    function claimReward() external {
        uint256 index = userAnswerIndex[msg.sender];
        require(index > 0, "No submission");
        Answer storage ans = answers[index - 1];
        require(evaluated, "Not evaluated yet");
        require(ans.score > 0, "No reward");
        require(!ans.rewarded, "Already claimed");

        require(cachedTotalScore > 0, "No scores assigned");

        // Simple single-token reward calculation
        uint256 reward = (totalRewardPool * ans.score) / cachedTotalScore;
        ans.rewarded = true;

        // Single token transfer - much simpler!
        token.transfer(msg.sender, reward);
        emit RewardClaimed(msg.sender, reward);
    }

    function totalScore() public view returns (uint256) {
        if (evaluated) {
            return cachedTotalScore;
        }
        // Fallback to loop calculation if not evaluated yet
        uint256 sum = 0;
        for (uint256 i = 0; i < answers.length; i++) {
            sum += answers[i].score;
        }
        return sum;
    }

    function getAnswer(uint256 index) external view returns (Answer memory) {
        return answers[index];
    }

    function getAllAnswers() external view returns (Answer[] memory) {
        return answers;
    }

    function getUserAnswer(address user) external view returns (Answer memory) {
        uint256 index = userAnswerIndex[user];
        require(index > 0, "No answer");
        return answers[index - 1];
    }

    function getTotalRewardValue() external view returns (uint256) {
        return totalRewardPool;
    }

    function emergencyRefund() external {
        require(!evaluated, "Already evaluated");
        require(block.timestamp > evaluationDeadline, "Evaluation deadline not reached");

        uint256 index = userAnswerIndex[msg.sender];
        require(index > 0, "No submission");

        Answer storage ans = answers[index - 1];
        require(!ans.rewarded, "Already refunded");

        ans.rewarded = true; // Prevent double refunds

        // Equal refund distribution from single pool
        uint256 refundAmount = totalRewardPool / answers.length;
        if (refundAmount > 0) {
            token.transfer(msg.sender, refundAmount);
        }

        emit RewardClaimed(msg.sender, refundAmount);
    }
}
