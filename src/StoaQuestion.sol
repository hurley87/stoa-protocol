// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts/access/Ownable.sol";

import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "./StoaBase.sol";

contract StoaQuestion is StoaBase {
    struct Answer {
        address responder;
        bytes32 answerHash;
        uint256 timestamp;
        uint256 score;
        bool rewarded;
    }

    IERC20 public token; // Single token for everything

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
    event AnswerSubmittedWithReferral(address indexed responder, uint256 index, address indexed referrer);
    event Evaluated(uint256[] rankedAnswerIndices);
    event RewardClaimed(address indexed user, uint256 amount);
    event Seeded(address indexed funder, uint256 amount);

    modifier onlyEvaluator() {
        require(msg.sender == creator, "Not evaluator");
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
        address _treasury,
        address _creator
    ) StoaBase(_treasury) {
        token = IERC20(_token);
        submissionCost = _submissionCost;
        endsAt = block.timestamp + _duration;
        evaluationDeadline = endsAt + 7 days; // 7 days after question ends
        maxWinners = _maxWinners;
        creator = _creator;
    }

    /**
     * @notice Sets the authorization status for a submitter to submit answers on behalf of others
     * @dev Only the contract owner can call this function
     * @param submitter The address to authorize or revoke authorization for
     * @param allowed True to authorize, false to revoke authorization
     */
    function setSubmitter(address submitter, bool allowed) external onlyOwner {
        isAuthorizedSubmitter[submitter] = allowed;
    }

    /**
     * @notice Adds funds to the question's reward pool
     * @dev Anyone can seed the question to increase the total reward pool
     * @param amount The amount of tokens to add to the reward pool (must be > 0)
     * @custom:requirements
     * - Caller must have approved this contract to spend at least `amount` tokens
     * - Amount must be greater than 0
     */
    function seedQuestion(uint256 amount) public {
        require(amount > 0, "Amount must be greater than 0");
        token.transferFrom(msg.sender, address(this), amount);
        totalRewardPool += amount;
        emit Seeded(msg.sender, amount);
    }

    /**
     * @notice Submits an answer to the question by the caller
     * @dev The submission cost is split between protocol treasury, creator, and reward pool
     * @param answerHash The keccak256 hash of the answer content
     * @custom:requirements
     * - Question must not have ended (block.timestamp < endsAt)
     * - Caller must not have already submitted an answer
     * - If submissionCost > 0, caller must have approved the contract to spend the full amount
     * @custom:behavior
     * - Submission cost is divided: protocol fee to treasury, creator fee to creator, remainder to reward pool
     * - Answer is stored with caller as responder and current timestamp
     * - Emits AnswerSubmitted event with the caller and answer index
     */
    function submitAnswer(bytes32 answerHash) external onlyBeforeEnd {
        _submitAnswer(msg.sender, answerHash, address(0));
    }

    /**
     * @notice Submits an answer to the question by the caller with a referrer
     * @dev The submission cost is split between protocol treasury, creator, referrer, and reward pool
     * @param answerHash The keccak256 hash of the answer content
     * @param referrer The address of the person who referred this submission
     * @custom:requirements
     * - Question must not have ended (block.timestamp < endsAt)
     * - Caller must not have already submitted an answer
     * - If submissionCost > 0, caller must have approved the contract to spend the full amount
     * @custom:behavior
     * - Submission cost is divided: protocol fee to treasury, creator fee to creator, referral fee to referrer, remainder to reward pool
     * - If referrer is zero address, referral cut goes to reward pool
     * - Answer is stored with caller as responder and current timestamp
     * - Emits AnswerSubmittedWithReferral event with the caller, answer index, and referrer
     */
    function submitAnswerWithReferral(bytes32 answerHash, address referrer) external onlyBeforeEnd {
        _submitAnswer(msg.sender, answerHash, referrer);
    }

    /**
     * @notice Submits an answer on behalf of another user (authorized submitters only)
     * @dev Allows authorized submitters to submit answers for users, with caller paying submission costs
     * @param user The address of the user for whom the answer is being submitted
     * @param answerHash The keccak256 hash of the answer content
     * @custom:requirements
     * - Caller must be an authorized submitter (set via setSubmitter)
     * - Question must not have ended (block.timestamp < endsAt)
     * - User address must not be zero address
     * - User must not have already submitted an answer
     * - If submissionCost > 0, caller must have approved the contract to spend the full amount
     * @custom:behavior
     * - Submission cost is paid by the caller but answer is attributed to the user
     * - Submission cost is divided: protocol fee to treasury, creator fee to creator, remainder to reward pool
     * - Answer is stored with user as responder and current timestamp
     * - Emits AnswerSubmitted event with the user and answer index
     */
    function submitAnswerFor(address user, bytes32 answerHash) external onlyAuthorizedSubmitter onlyBeforeEnd {
        _submitAnswerFor(user, answerHash, address(0));
    }

    /**
     * @notice Submits an answer on behalf of another user with a referrer (authorized submitters only)
     * @dev Allows authorized submitters to submit answers for users with referral tracking
     * @param user The address of the user for whom the answer is being submitted
     * @param answerHash The keccak256 hash of the answer content
     * @param referrer The address of the person who referred this submission
     * @custom:requirements
     * - Caller must be an authorized submitter (set via setSubmitter)
     * - Question must not have ended (block.timestamp < endsAt)
     * - User address must not be zero address
     * - User must not have already submitted an answer
     * - If submissionCost > 0, caller must have approved the contract to spend the full amount
     * @custom:behavior
     * - Submission cost is paid by the caller but answer is attributed to the user
     * - Submission cost is divided: protocol fee to treasury, creator fee to creator, referral fee to referrer, remainder to reward pool
     * - If referrer is zero address, referral cut goes to reward pool
     * - Answer is stored with user as responder and current timestamp
     * - Emits AnswerSubmittedWithReferral event with the user, answer index, and referrer
     */
    function submitAnswerForWithReferral(address user, bytes32 answerHash, address referrer)
        external
        onlyAuthorizedSubmitter
        onlyBeforeEnd
    {
        _submitAnswerFor(user, answerHash, referrer);
    }

    /**
     * @notice Evaluates and ranks submitted answers, assigning scores to winners
     * @dev Only the question creator can evaluate answers after the question period ends
     * @param rankedIndices Array of answer indices in descending order of quality (best first)
     * @custom:requirements
     * - Only the creator (evaluator) can call this function
     * - Question must not have been evaluated yet
     * - Current time must be >= endsAt (question period must be over)
     * - Number of ranked indices must not exceed maxWinners
     * - All indices in rankedIndices must be valid (< answers.length)
     * @custom:behavior
     * - Assigns scores inversely proportional to rank (1st place gets maxWinners points, 2nd gets maxWinners-1, etc.)
     * - Caches total score for efficient reward calculations
     * - Sets evaluated flag to true, preventing future evaluations
     * - Emits Evaluated event with the ranked indices
     */
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

    /**
     * @notice Allows users to claim their reward based on their answer's score
     * @dev Calculates reward proportionally based on answer score relative to total scores
     * @custom:requirements
     * - Caller must have submitted an answer
     * - Answers must have been evaluated
     * - Caller's answer must have received a score > 0
     * - Caller must not have already claimed their reward
     * - Total scores must be greater than 0
     * @custom:behavior
     * - Reward = (totalRewardPool * answerScore) / cachedTotalScore
     * - Marks answer as rewarded to prevent double claims
     * - Transfers tokens directly to the caller
     * - Emits RewardClaimed event with user address and reward amount
     */
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

    /**
     * @notice Returns the total score across all answers
     * @dev Uses cached value if evaluation is complete, otherwise calculates dynamically
     * @return The sum of all answer scores
     * @custom:behavior
     * - If evaluated: returns cachedTotalScore for gas efficiency
     * - If not evaluated: loops through all answers to sum scores (more expensive)
     */
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

    /**
     * @notice Retrieves a specific answer by its index
     * @param index The index of the answer in the answers array
     * @return The Answer struct containing responder, answerHash, timestamp, score, and rewarded status
     * @custom:requirements
     * - Index must be within bounds of the answers array
     */
    function getAnswer(uint256 index) external view returns (Answer memory) {
        return answers[index];
    }

    /**
     * @notice Retrieves all submitted answers
     * @return Array of all Answer structs submitted to this question
     * @dev Returns the complete answers array, useful for frontend display or analysis
     */
    function getAllAnswers() external view returns (Answer[] memory) {
        return answers;
    }

    /**
     * @notice Retrieves the answer submitted by a specific user
     * @param user The address of the user whose answer to retrieve
     * @return The Answer struct submitted by the specified user
     * @custom:requirements
     * - User must have submitted an answer
     */
    function getUserAnswer(address user) external view returns (Answer memory) {
        uint256 index = userAnswerIndex[user];
        require(index > 0, "No answer");
        return answers[index - 1];
    }

    /**
     * @notice Returns the total amount in the reward pool
     * @return The current total reward pool amount in tokens
     * @dev This includes all seeded funds and submission costs allocated to rewards
     */
    function getTotalRewardValue() external view returns (uint256) {
        return totalRewardPool;
    }

    /**
     * @notice Internal function to handle answer submission logic
     * @param responder The address of the answer responder
     * @param answerHash The keccak256 hash of the answer content
     * @param referrer The address of the referrer (address(0) if no referrer)
     */
    function _submitAnswer(address responder, bytes32 answerHash, address referrer) internal {
        require(userAnswerIndex[responder] == 0, "Already submitted");

        if (submissionCost > 0) {
            uint256 protocolCut = (submissionCost * feeBps) / BASIS_POINTS;
            uint256 creatorCut = (submissionCost * creatorFeeBps) / BASIS_POINTS;
            uint256 referralCut = (submissionCost * referralFeeBps) / BASIS_POINTS;
            uint256 rewardCut = submissionCost - protocolCut - creatorCut - referralCut;

            token.transferFrom(msg.sender, treasury, protocolCut);
            token.transferFrom(msg.sender, creator, creatorCut);

            if (referrer != address(0)) {
                token.transferFrom(msg.sender, referrer, referralCut);
            } else {
                rewardCut += referralCut; // Add referral cut to reward pool if no referrer
            }

            token.transferFrom(msg.sender, address(this), rewardCut);
            totalRewardPool += rewardCut;
        }

        answers.push(
            Answer({responder: responder, answerHash: answerHash, timestamp: block.timestamp, score: 0, rewarded: false})
        );

        userAnswerIndex[responder] = answers.length;

        if (referrer != address(0)) {
            emit AnswerSubmittedWithReferral(responder, answers.length - 1, referrer);
        } else {
            emit AnswerSubmitted(responder, answers.length - 1);
        }
    }

    /**
     * @notice Internal function to handle answer submission on behalf of another user
     * @param user The address of the user for whom the answer is being submitted
     * @param answerHash The keccak256 hash of the answer content
     * @param referrer The address of the referrer (address(0) if no referrer)
     */
    function _submitAnswerFor(address user, bytes32 answerHash, address referrer) internal {
        require(user != address(0), "Invalid user");
        require(userAnswerIndex[user] == 0, "Already submitted");

        if (submissionCost > 0) {
            uint256 protocolCut = (submissionCost * feeBps) / BASIS_POINTS;
            uint256 creatorCut = (submissionCost * creatorFeeBps) / BASIS_POINTS;
            uint256 referralCut = (submissionCost * referralFeeBps) / BASIS_POINTS;
            uint256 rewardCut = submissionCost - protocolCut - creatorCut - referralCut;

            token.transferFrom(msg.sender, treasury, protocolCut);
            token.transferFrom(msg.sender, creator, creatorCut);

            if (referrer != address(0)) {
                token.transferFrom(msg.sender, referrer, referralCut);
            } else {
                rewardCut += referralCut; // Add referral cut to reward pool if no referrer
            }

            token.transferFrom(msg.sender, address(this), rewardCut);
            totalRewardPool += rewardCut;
        }

        answers.push(
            Answer({responder: user, answerHash: answerHash, timestamp: block.timestamp, score: 0, rewarded: false})
        );

        userAnswerIndex[user] = answers.length;

        if (referrer != address(0)) {
            emit AnswerSubmittedWithReferral(user, answers.length - 1, referrer);
        } else {
            emit AnswerSubmitted(user, answers.length - 1);
        }
    }

    /**
     * @notice Provides emergency refund when evaluation deadline is missed
     * @dev Allows participants to claim equal refunds if creator fails to evaluate within deadline
     * @custom:requirements
     * - Question must not have been evaluated
     * - Current time must exceed evaluation deadline (endsAt + 7 days)
     * - Caller must have submitted an answer
     * - Caller must not have already received a refund
     * @custom:behavior
     * - Distributes totalRewardPool equally among all participants
     * - Marks caller's answer as rewarded to prevent double refunds
     * - Transfers refund amount to caller
     * - Emits RewardClaimed event (reused for refunds)
     * @custom:security This is a safety mechanism to prevent funds from being locked forever
     */
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

    /**
     * @notice Returns the claimable reward amount for a specific user
     * @param user The address of the user to check
     * @return claimableAmount The amount of tokens the user can claim (0 if not eligible)
     * @custom:behavior
     * - Returns 0 if user hasn't submitted an answer
     * - Returns 0 if question hasn't been evaluated yet
     * - Returns 0 if user's answer has no score (not a winner)
     * - Returns 0 if user has already claimed their reward
     * - Returns calculated reward amount based on score proportion if eligible
     */
    function getClaimableAmount(address user) external view returns (uint256) {
        uint256 index = userAnswerIndex[user];
        if (index == 0) return 0; // No submission

        Answer memory ans = answers[index - 1];

        if (!evaluated) return 0; // Not evaluated yet
        if (ans.score == 0) return 0; // No reward
        if (ans.rewarded) return 0; // Already claimed
        if (cachedTotalScore == 0) return 0; // No scores assigned

        return (totalRewardPool * ans.score) / cachedTotalScore;
    }

    /**
     * @notice Returns whether the question is currently active for submissions
     * @return True if submissions are still allowed, false otherwise
     */
    function isActive() external view returns (bool) {
        return block.timestamp < endsAt;
    }

    /**
     * @notice Returns whether the question is in the evaluation period
     * @return True if question ended but evaluation deadline hasn't passed
     */
    function isEvaluationPeriod() external view returns (bool) {
        return block.timestamp >= endsAt && block.timestamp <= evaluationDeadline && !evaluated;
    }

    /**
     * @notice Returns the time remaining for submissions (0 if ended)
     * @return Time remaining in seconds, or 0 if question has ended
     */
    function timeRemaining() external view returns (uint256) {
        if (block.timestamp >= endsAt) return 0;
        return endsAt - block.timestamp;
    }

    /**
     * @notice Returns the current status of the question
     * @return Status string: "Active", "AwaitingEvaluation", "Evaluated", "EmergencyRefundAvailable"
     */
    function getQuestionStatus() external view returns (string memory) {
        if (block.timestamp < endsAt) {
            return "Active";
        } else if (!evaluated && block.timestamp <= evaluationDeadline) {
            return "AwaitingEvaluation";
        } else if (evaluated) {
            return "Evaluated";
        } else {
            return "EmergencyRefundAvailable";
        }
    }

    /**
     * @notice Returns the total number of submitted answers
     * @return The length of the answers array
     */
    function getAnswerCount() external view returns (uint256) {
        return answers.length;
    }

    /**
     * @notice Checks if a user has submitted an answer
     * @param user The address to check
     * @return True if user has submitted an answer, false otherwise
     */
    function hasUserSubmitted(address user) external view returns (bool) {
        return userAnswerIndex[user] > 0;
    }

    /**
     * @notice Returns addresses of all users who received scores (winners)
     * @return Array of winner addresses
     */
    function getWinnerAddresses() external view returns (address[] memory) {
        uint256 winnerCount = 0;

        // First pass: count winners
        for (uint256 i = 0; i < answers.length; i++) {
            if (answers[i].score > 0) {
                winnerCount++;
            }
        }

        // Second pass: collect winner addresses
        address[] memory winners = new address[](winnerCount);
        uint256 index = 0;
        for (uint256 i = 0; i < answers.length; i++) {
            if (answers[i].score > 0) {
                winners[index] = answers[i].responder;
                index++;
            }
        }

        return winners;
    }

    /**
     * @notice Returns winners ranked by score (highest first) with their scores
     * @return addresses Array of winner addresses in descending score order
     * @return scores Array of scores corresponding to the addresses
     */
    function getRankedWinners() external view returns (address[] memory addresses, uint256[] memory scores) {
        uint256 winnerCount = 0;

        // Count winners
        for (uint256 i = 0; i < answers.length; i++) {
            if (answers[i].score > 0) {
                winnerCount++;
            }
        }

        addresses = new address[](winnerCount);
        scores = new uint256[](winnerCount);

        // Collect winners
        uint256 index = 0;
        for (uint256 i = 0; i < answers.length; i++) {
            if (answers[i].score > 0) {
                addresses[index] = answers[i].responder;
                scores[index] = answers[i].score;
                index++;
            }
        }

        // Simple bubble sort by score (descending)
        for (uint256 i = 0; i < winnerCount; i++) {
            for (uint256 j = 0; j < winnerCount - 1 - i; j++) {
                if (scores[j] < scores[j + 1]) {
                    // Swap scores
                    (scores[j], scores[j + 1]) = (scores[j + 1], scores[j]);
                    // Swap addresses
                    (addresses[j], addresses[j + 1]) = (addresses[j + 1], addresses[j]);
                }
            }
        }

        return (addresses, scores);
    }

    /**
     * @notice Returns the total amount of rewards that have been claimed
     * @return Total claimed reward amount
     */
    function getTotalClaimed() external view returns (uint256) {
        if (!evaluated || cachedTotalScore == 0) return 0;

        uint256 totalClaimed = 0;
        for (uint256 i = 0; i < answers.length; i++) {
            if (answers[i].rewarded && answers[i].score > 0) {
                totalClaimed += (totalRewardPool * answers[i].score) / cachedTotalScore;
            }
        }
        return totalClaimed;
    }

    /**
     * @notice Returns the total amount of unclaimed rewards available
     * @return Total unclaimed reward amount
     */
    function getUnclaimedRewards() external view returns (uint256) {
        if (!evaluated || cachedTotalScore == 0) return totalRewardPool;

        uint256 totalClaimed = 0;
        for (uint256 i = 0; i < answers.length; i++) {
            if (answers[i].rewarded && answers[i].score > 0) {
                totalClaimed += (totalRewardPool * answers[i].score) / cachedTotalScore;
            }
        }
        return totalRewardPool > totalClaimed ? totalRewardPool - totalClaimed : 0;
    }

    /**
     * @notice Checks if emergency refund is available
     * @return True if users can claim emergency refunds
     */
    function canEmergencyRefund() external view returns (bool) {
        return !evaluated && block.timestamp > evaluationDeadline;
    }

    /**
     * @notice Returns the emergency refund amount per participant
     * @return Amount each participant can claim in emergency refund
     */
    function getEmergencyRefundAmount() external view returns (uint256) {
        if (evaluated || block.timestamp <= evaluationDeadline || answers.length == 0) {
            return 0;
        }
        return totalRewardPool / answers.length;
    }

    /**
     * @notice Returns claimable amounts for multiple users in a single call
     * @param users Array of user addresses to check
     * @return amounts Array of claimable amounts corresponding to each user
     */
    function getMultipleClaimableAmounts(address[] calldata users) external view returns (uint256[] memory amounts) {
        amounts = new uint256[](users.length);

        for (uint256 i = 0; i < users.length; i++) {
            uint256 index = userAnswerIndex[users[i]];
            if (index == 0) {
                amounts[i] = 0; // No submission
                continue;
            }

            Answer memory ans = answers[index - 1];

            if (!evaluated || ans.score == 0 || ans.rewarded || cachedTotalScore == 0) {
                amounts[i] = 0;
            } else {
                amounts[i] = (totalRewardPool * ans.score) / cachedTotalScore;
            }
        }

        return amounts;
    }
}
