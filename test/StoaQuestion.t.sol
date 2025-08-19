// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/StoaQuestion.sol";
import "openzeppelin-contracts/token/ERC20/ERC20.sol";

// Mock ERC20 token for testing
contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract StoaQuestionTest is Test {
    StoaQuestion public question;
    MockToken public paymentToken; // Single token for everything

    address public owner;
    address public treasury;
    address public evaluator;
    address public creator;
    address public user1;
    address public user2;
    address public user3;
    address public submitter;
    address public funder;

    uint256 public constant SUBMISSION_COST = 10 * 10 ** 18; // 10 tokens
    uint256 public constant DURATION = 7 days;
    uint8 public constant MAX_WINNERS = 3;
    uint256 public constant INITIAL_BALANCE = 1000 * 10 ** 18;

    // Events for testing
    event AnswerSubmitted(address indexed responder, uint256 index);
    event Evaluated(uint256[] rankedAnswerIndices);
    event RewardClaimed(address indexed user, uint256 amount);
    event Seeded(address indexed funder, uint256 amount);
    event FeeUpdated(uint256 newFeeBps);
    event TreasuryUpdated(address newTreasury);

    function setUp() public {
        owner = address(this);
        treasury = makeAddr("treasury");
        evaluator = makeAddr("evaluator");
        creator = makeAddr("creator");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        submitter = makeAddr("submitter");
        funder = makeAddr("funder");

        // Deploy token and reputation system
        paymentToken = new MockToken("PaymentToken", "PAY");

        // Deploy question contract with single token
        vm.prank(creator);
        question = new StoaQuestion(
            address(paymentToken), SUBMISSION_COST, DURATION, MAX_WINNERS, evaluator, treasury
        );


        // Distribute tokens to users
        paymentToken.mint(user1, INITIAL_BALANCE);
        paymentToken.mint(user2, INITIAL_BALANCE);
        paymentToken.mint(user3, INITIAL_BALANCE);
        paymentToken.mint(submitter, INITIAL_BALANCE);
        paymentToken.mint(funder, INITIAL_BALANCE);

        // Only need single token - no separate reward token needed

        // Approve single token spending
        vm.prank(user1);
        paymentToken.approve(address(question), type(uint256).max);
        vm.prank(user2);
        paymentToken.approve(address(question), type(uint256).max);
        vm.prank(user3);
        paymentToken.approve(address(question), type(uint256).max);
        vm.prank(submitter);
        paymentToken.approve(address(question), type(uint256).max);
        vm.prank(funder);
        paymentToken.approve(address(question), type(uint256).max);
    }

    // Constructor Tests
    function testConstructor() public {
        assertEq(address(question.token()), address(paymentToken));
        assertEq(question.submissionCost(), SUBMISSION_COST);
        assertEq(question.maxWinners(), MAX_WINNERS);
        assertEq(question.evaluator(), evaluator);
        assertEq(question.treasury(), treasury);
        assertEq(question.creator(), creator);
        assertEq(question.feeBps(), 1000); // 10% default fee
        assertEq(question.totalRewardPool(), 0);
        assertFalse(question.evaluated());
        assertEq(question.endsAt(), block.timestamp + DURATION);
    }

    // Seeding Tests
    function testSeedQuestion() public {
        uint256 seedAmount = 100 * 10 ** 18;

        vm.expectEmit(true, false, false, true);
        emit Seeded(funder, seedAmount);

        vm.prank(funder);
        question.seedQuestion(seedAmount);

        assertEq(question.totalRewardPool(), seedAmount);
        assertEq(paymentToken.balanceOf(address(question)), seedAmount);
    }

    function testSeedQuestionRevertsWithZeroAmount() public {
        vm.prank(funder);
        vm.expectRevert("Amount must be greater than 0");
        question.seedQuestion(0);
    }

    function testSeedQuestionMultipleTimes() public {
        uint256 firstSeed = 50 * 10 ** 18;
        uint256 secondSeed = 75 * 10 ** 18;

        vm.prank(funder);
        question.seedQuestion(firstSeed);
        assertEq(question.totalRewardPool(), firstSeed);

        vm.prank(user1);
        question.seedQuestion(secondSeed);
        assertEq(question.totalRewardPool(), firstSeed + secondSeed);
    }

    // Submitter Authorization Tests
    function testSetSubmitter() public {
        assertFalse(question.isAuthorizedSubmitter(submitter));

        vm.prank(creator);
        question.setSubmitter(submitter, true);
        assertTrue(question.isAuthorizedSubmitter(submitter));

        vm.prank(creator);
        question.setSubmitter(submitter, false);
        assertFalse(question.isAuthorizedSubmitter(submitter));
    }

    function testSetSubmitterOnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        question.setSubmitter(submitter, true);
    }

    // Answer Submission Tests
    function testSubmitAnswer() public {
        bytes32 answerHash = keccak256("My answer");
        uint256 protocolCut = SUBMISSION_COST * 1000 / 10000; // 10% protocol fee
        uint256 creatorCut = SUBMISSION_COST * 1000 / 10000; // 10% creator fee
        uint256 expectedRewardCut = SUBMISSION_COST - protocolCut - creatorCut;

        uint256 creatorBalanceBefore = paymentToken.balanceOf(creator);

        vm.expectEmit(true, false, false, true);
        emit AnswerSubmitted(user1, 0);

        vm.prank(user1);
        question.submitAnswer(answerHash);

        // Check answer was recorded
        StoaQuestion.Answer memory answer = question.getAnswer(0);
        assertEq(answer.responder, user1);
        assertEq(answer.answerHash, answerHash);
        assertEq(answer.timestamp, block.timestamp);
        assertEq(answer.score, 0);
        assertFalse(answer.rewarded);

        // Check mappings
        assertEq(question.userAnswerIndex(user1), 1); // 1-indexed

        // Check total reward pool increased
        assertEq(question.totalRewardPool(), expectedRewardCut);

        // Check creator received their fee
        assertEq(paymentToken.balanceOf(creator) - creatorBalanceBefore, creatorCut);

        // Check fees were paid to treasury
        assertEq(paymentToken.balanceOf(treasury), protocolCut);
    }

    function testSubmitAnswerAfterDeadline() public {
        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(user1);
        vm.expectRevert("Question ended");
        question.submitAnswer(keccak256("Late answer"));
    }

    function testSubmitAnswerTwice() public {
        vm.prank(user1);
        question.submitAnswer(keccak256("First answer"));

        vm.prank(user1);
        vm.expectRevert("Already submitted");
        question.submitAnswer(keccak256("Second answer"));
    }

    function testSubmitAnswerWithZeroSubmissionCost() public {

        // Deploy new question with zero submission cost
        vm.prank(creator);
        StoaQuestion zeroFeeQuestion = new StoaQuestion(
            address(paymentToken),
            0, // Zero submission cost
            DURATION,
            MAX_WINNERS,
            evaluator,
            treasury
        );


        vm.prank(user1);
        zeroFeeQuestion.submitAnswer(keccak256("Free answer"));

        assertEq(zeroFeeQuestion.totalRewardPool(), 0);
        assertEq(paymentToken.balanceOf(treasury), 0);
    }

    // Submit Answer For Tests
    function testSubmitAnswerFor() public {
        bytes32 answerHash = keccak256("Answer for user");

        vm.prank(creator);
        question.setSubmitter(submitter, true);

        vm.expectEmit(true, false, false, true);
        emit AnswerSubmitted(user1, 0);

        vm.prank(submitter);
        question.submitAnswerFor(user1, answerHash);

        StoaQuestion.Answer memory answer = question.getAnswer(0);
        assertEq(answer.responder, user1);
        assertEq(answer.answerHash, answerHash);
        assertEq(question.userAnswerIndex(user1), 1);
    }

    function testSubmitAnswerForUnauthorized() public {
        vm.prank(user2);
        vm.expectRevert("Not allowed");
        question.submitAnswerFor(user1, keccak256("Unauthorized"));
    }

    function testSubmitAnswerForZeroAddress() public {
        vm.prank(creator);
        question.setSubmitter(submitter, true);

        vm.prank(submitter);
        vm.expectRevert("Invalid user");
        question.submitAnswerFor(address(0), keccak256("Zero address"));
    }

    function testSubmitAnswerForAlreadySubmitted() public {
        vm.prank(creator);
        question.setSubmitter(submitter, true);

        vm.prank(submitter);
        question.submitAnswerFor(user1, keccak256("First"));

        vm.prank(submitter);
        vm.expectRevert("Already submitted");
        question.submitAnswerFor(user1, keccak256("Second"));
    }

    // Evaluation Tests
    function testEvaluateAnswers() public {
        // Submit multiple answers
        vm.prank(user1);
        question.submitAnswer(keccak256("Answer 1"));
        vm.prank(user2);
        question.submitAnswer(keccak256("Answer 2"));
        vm.prank(user3);
        question.submitAnswer(keccak256("Answer 3"));

        // Wait for question to end
        vm.warp(block.timestamp + DURATION + 1);

        uint256[] memory rankedIndices = new uint256[](2);
        rankedIndices[0] = 1; // user2 first place
        rankedIndices[1] = 0; // user1 second place

        vm.expectEmit(true, false, false, true);
        emit Evaluated(rankedIndices);

        vm.prank(evaluator);
        question.evaluateAnswers(rankedIndices);

        assertTrue(question.evaluated());

        // Check scores
        assertEq(question.getAnswer(1).score, MAX_WINNERS); // First place: 3
        assertEq(question.getAnswer(0).score, MAX_WINNERS - 1); // Second place: 2
        assertEq(question.getAnswer(2).score, 0); // No score
    }

    function testEvaluateAnswersOnlyEvaluator() public {
        vm.warp(block.timestamp + DURATION + 1);

        uint256[] memory rankedIndices = new uint256[](0);

        vm.prank(user1);
        vm.expectRevert("Not evaluator");
        question.evaluateAnswers(rankedIndices);
    }

    function testEvaluateAnswersTooEarly() public {
        uint256[] memory rankedIndices = new uint256[](0);

        vm.prank(evaluator);
        vm.expectRevert("Too early");
        question.evaluateAnswers(rankedIndices);
    }

    function testEvaluateAnswersAlreadyEvaluated() public {
        vm.warp(block.timestamp + DURATION + 1);

        uint256[] memory rankedIndices = new uint256[](0);

        vm.prank(evaluator);
        question.evaluateAnswers(rankedIndices);

        vm.prank(evaluator);
        vm.expectRevert("Already evaluated");
        question.evaluateAnswers(rankedIndices);
    }

    function testEvaluateAnswersTooManyWinners() public {
        vm.warp(block.timestamp + DURATION + 1);

        uint256[] memory rankedIndices = new uint256[](MAX_WINNERS + 1);
        for (uint256 i = 0; i < MAX_WINNERS + 1; i++) {
            rankedIndices[i] = i;
        }

        vm.prank(evaluator);
        vm.expectRevert("Too many winners");
        question.evaluateAnswers(rankedIndices);
    }

    // Reward Claiming Tests
    function testClaimReward() public {
        // Seed the question
        uint256 seedAmount = 300 * 10 ** 18;
        vm.prank(funder);
        question.seedQuestion(seedAmount);

        // Submit answers
        vm.prank(user1);
        question.submitAnswer(keccak256("Answer 1"));
        vm.prank(user2);
        question.submitAnswer(keccak256("Answer 2"));

        // Evaluate
        vm.warp(block.timestamp + DURATION + 1);
        uint256[] memory rankedIndices = new uint256[](2);
        rankedIndices[0] = 0; // user1 first place (score = 3)
        rankedIndices[1] = 1; // user2 second place (score = 2)

        vm.prank(evaluator);
        question.evaluateAnswers(rankedIndices);

        // Calculate expected rewards from total reward pool
        uint256 totalRewardValue = question.getTotalRewardValue();
        uint256 totalScore = question.totalScore(); // 3 + 2 = 5
        uint256 expectedRewardUser1 = (totalRewardValue * 3) / totalScore;
        uint256 expectedRewardUser2 = (totalRewardValue * 2) / totalScore;

        uint256 balanceBefore1 = paymentToken.balanceOf(user1);
        uint256 balanceBefore2 = paymentToken.balanceOf(user2);

        // Claim rewards
        vm.expectEmit(true, false, false, true);
        emit RewardClaimed(user1, expectedRewardUser1);
        vm.prank(user1);
        question.claimReward();

        vm.expectEmit(true, false, false, true);
        emit RewardClaimed(user2, expectedRewardUser2);
        vm.prank(user2);
        question.claimReward();

        // Verify reward amounts (single token)
        uint256 rewardReceived1 = paymentToken.balanceOf(user1) - balanceBefore1;
        uint256 rewardReceived2 = paymentToken.balanceOf(user2) - balanceBefore2;

        assertEq(rewardReceived1, expectedRewardUser1);
        assertEq(rewardReceived2, expectedRewardUser2);

        // Check answer states
        assertTrue(question.getAnswer(0).rewarded);
        assertTrue(question.getAnswer(1).rewarded);
    }

    function testClaimRewardNoSubmission() public {
        vm.prank(user1);
        vm.expectRevert("No submission");
        question.claimReward();
    }

    function testClaimRewardNotEvaluated() public {
        vm.prank(user1);
        question.submitAnswer(keccak256("Answer"));

        vm.prank(user1);
        vm.expectRevert("Not evaluated yet");
        question.claimReward();
    }

    function testClaimRewardNoScore() public {
        vm.prank(user1);
        question.submitAnswer(keccak256("Answer"));

        vm.warp(block.timestamp + DURATION + 1);
        uint256[] memory rankedIndices = new uint256[](0); // No winners

        vm.prank(evaluator);
        question.evaluateAnswers(rankedIndices);

        vm.prank(user1);
        vm.expectRevert("No reward");
        question.claimReward();
    }

    function testClaimRewardAlreadyClaimed() public {
        vm.prank(funder);
        question.seedQuestion(100 * 10 ** 18);

        vm.prank(user1);
        question.submitAnswer(keccak256("Answer"));

        vm.warp(block.timestamp + DURATION + 1);
        uint256[] memory rankedIndices = new uint256[](1);
        rankedIndices[0] = 0;

        vm.prank(evaluator);
        question.evaluateAnswers(rankedIndices);

        vm.prank(user1);
        question.claimReward();

        vm.prank(user1);
        vm.expectRevert("Already claimed");
        question.claimReward();
    }

    // View Function Tests
    function testGetAnswer() public {
        bytes32 answerHash = keccak256("Test answer");

        vm.prank(user1);
        question.submitAnswer(answerHash);

        StoaQuestion.Answer memory answer = question.getAnswer(0);
        assertEq(answer.responder, user1);
        assertEq(answer.answerHash, answerHash);
        assertEq(answer.timestamp, block.timestamp);
        assertEq(answer.score, 0);
        assertFalse(answer.rewarded);
    }

    function testGetAllAnswers() public {
        vm.prank(user1);
        question.submitAnswer(keccak256("Answer 1"));
        vm.prank(user2);
        question.submitAnswer(keccak256("Answer 2"));

        StoaQuestion.Answer[] memory answers = question.getAllAnswers();
        assertEq(answers.length, 2);
        assertEq(answers[0].responder, user1);
        assertEq(answers[1].responder, user2);
    }

    function testGetUserAnswer() public {
        bytes32 answerHash = keccak256("User answer");

        vm.prank(user1);
        question.submitAnswer(answerHash);

        StoaQuestion.Answer memory answer = question.getUserAnswer(user1);
        assertEq(answer.responder, user1);
        assertEq(answer.answerHash, answerHash);
    }

    function testGetUserAnswerNoAnswer() public {
        vm.expectRevert("No answer");
        question.getUserAnswer(user1);
    }

    function testTotalScore() public {
        vm.prank(user1);
        question.submitAnswer(keccak256("Answer 1"));
        vm.prank(user2);
        question.submitAnswer(keccak256("Answer 2"));
        vm.prank(user3);
        question.submitAnswer(keccak256("Answer 3"));

        vm.warp(block.timestamp + DURATION + 1);
        uint256[] memory rankedIndices = new uint256[](3);
        rankedIndices[0] = 0; // score = 3
        rankedIndices[1] = 1; // score = 2
        rankedIndices[2] = 2; // score = 1

        vm.prank(evaluator);
        question.evaluateAnswers(rankedIndices);

        assertEq(question.totalScore(), 6); // 3 + 2 + 1
    }

    // Integration Tests
    function testCompleteWorkflow() public {
        // Seed question
        uint256 seedAmount = 500 * 10 ** 18;
        vm.prank(funder);
        question.seedQuestion(seedAmount);

        // Submit answers
        vm.prank(user1);
        question.submitAnswer(keccak256("Best answer"));
        vm.prank(user2);
        question.submitAnswer(keccak256("Good answer"));
        vm.prank(user3);
        question.submitAnswer(keccak256("Ok answer"));

        // Check initial state
        assertEq(question.getAllAnswers().length, 3);
        assertFalse(question.evaluated());

        // Wait for deadline
        vm.warp(block.timestamp + DURATION + 1);

        // Evaluate answers
        uint256[] memory rankedIndices = new uint256[](2);
        rankedIndices[0] = 0; // user1 wins
        rankedIndices[1] = 1; // user2 second

        vm.prank(evaluator);
        question.evaluateAnswers(rankedIndices);

        assertTrue(question.evaluated());

        // Claim rewards
        vm.prank(user1);
        question.claimReward();
        vm.prank(user2);
        question.claimReward();

        // Verify final state
        assertTrue(question.getAnswer(0).rewarded);
        assertTrue(question.getAnswer(1).rewarded);
        assertFalse(question.getAnswer(2).rewarded);
    }

    // Edge Cases
    function testEvaluateWithNoAnswers() public {
        vm.warp(block.timestamp + DURATION + 1);

        uint256[] memory rankedIndices = new uint256[](0);

        vm.prank(evaluator);
        question.evaluateAnswers(rankedIndices);

        assertTrue(question.evaluated());
        assertEq(question.totalScore(), 0);
    }

    function testSubmissionCostCalculation() public {
        uint256 submissionCost = SUBMISSION_COST; // Use the actual submission cost from the contract
        uint256 feeBps = 1000; // 10% protocol fee
        uint256 creatorFeeBps = 1000; // 10% creator fee

        uint256 expectedProtocolCut = (submissionCost * feeBps) / 10000;
        uint256 expectedCreatorCut = (submissionCost * creatorFeeBps) / 10000;
        uint256 expectedRewardCut = submissionCost - expectedProtocolCut - expectedCreatorCut;

        uint256 creatorBalanceBefore = paymentToken.balanceOf(creator);

        vm.prank(user1);
        question.submitAnswer(keccak256("Answer"));

        assertEq(paymentToken.balanceOf(treasury), expectedProtocolCut);
        assertEq(paymentToken.balanceOf(creator) - creatorBalanceBefore, expectedCreatorCut);
        assertEq(question.totalRewardPool(), expectedRewardCut);
    }

    // Fuzz Tests
    function testFuzzSeedQuestion(uint256 amount) public {
        vm.assume(amount > 0 && amount <= paymentToken.balanceOf(funder));

        vm.prank(funder);
        question.seedQuestion(amount);

        assertEq(question.totalRewardPool(), amount);
    }

    function testFuzzSubmitAnswer(bytes32 answerHash) public {
        vm.prank(user1);
        question.submitAnswer(answerHash);

        assertEq(question.getAnswer(0).answerHash, answerHash);
        assertEq(question.userAnswerIndex(user1), 1);
    }

    function testFuzzEvaluateAnswers(uint8 numWinners) public {
        vm.assume(numWinners <= MAX_WINNERS);

        // Submit enough answers
        for (uint256 i = 0; i < numWinners; i++) {
            address user = address(uint160(0x1000 + i));
            paymentToken.mint(user, INITIAL_BALANCE);
            vm.prank(user);
            paymentToken.approve(address(question), type(uint256).max);
            vm.prank(user);
            question.submitAnswer(keccak256(abi.encodePacked("Answer", i)));
        }

        vm.warp(block.timestamp + DURATION + 1);

        uint256[] memory rankedIndices = new uint256[](numWinners);
        for (uint256 i = 0; i < numWinners; i++) {
            rankedIndices[i] = i;
        }

        vm.prank(evaluator);
        question.evaluateAnswers(rankedIndices);

        assertTrue(question.evaluated());
    }

    // Gas Usage Tests
    function testGasUsageSubmitAnswer() public {
        uint256 gasBefore = gasleft();
        vm.prank(user1);
        question.submitAnswer(keccak256("Test answer"));
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for submitAnswer:", gasUsed);
    }

    function testGasUsageEvaluateAnswers() public {
        // Submit some answers first
        vm.prank(user1);
        question.submitAnswer(keccak256("Answer 1"));
        vm.prank(user2);
        question.submitAnswer(keccak256("Answer 2"));

        vm.warp(block.timestamp + DURATION + 1);

        uint256[] memory rankedIndices = new uint256[](2);
        rankedIndices[0] = 0;
        rankedIndices[1] = 1;

        uint256 gasBefore = gasleft();
        vm.prank(evaluator);
        question.evaluateAnswers(rankedIndices);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for evaluateAnswers:", gasUsed);
    }

    function testGasUsageClaimReward() public {
        vm.prank(funder);
        question.seedQuestion(100 * 10 ** 18);

        vm.prank(user1);
        question.submitAnswer(keccak256("Answer"));

        vm.warp(block.timestamp + DURATION + 1);

        uint256[] memory rankedIndices = new uint256[](1);
        rankedIndices[0] = 0;

        vm.prank(evaluator);
        question.evaluateAnswers(rankedIndices);

        uint256 gasBefore = gasleft();
        vm.prank(user1);
        question.claimReward();
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for claimReward:", gasUsed);
    }

    // Emergency refund tests
    function testEmergencyRefund() public {
        // Submit an answer
        vm.prank(user1);
        question.submitAnswer(keccak256("Answer"));

        // Wait past evaluation deadline (7 days after question ends)
        vm.warp(block.timestamp + DURATION + 7 days + 1);

        uint256 balanceBefore = paymentToken.balanceOf(user1);

        // User can claim emergency refund
        vm.prank(user1);
        question.emergencyRefund();

        uint256 balanceAfter = paymentToken.balanceOf(user1);
        assertTrue(balanceAfter > balanceBefore, "Should receive refund");
    }

    function testEmergencyRefundTooEarly() public {
        vm.prank(user1);
        question.submitAnswer(keccak256("Answer"));

        vm.prank(user1);
        vm.expectRevert("Evaluation deadline not reached");
        question.emergencyRefund();
    }

    function testEmergencyRefundAfterEvaluation() public {
        vm.prank(user1);
        question.submitAnswer(keccak256("Answer"));

        // Evaluate normally
        vm.warp(block.timestamp + DURATION + 1);
        uint256[] memory rankedIndices = new uint256[](1);
        rankedIndices[0] = 0;

        vm.prank(evaluator);
        question.evaluateAnswers(rankedIndices);

        // Try emergency refund after evaluation
        vm.warp(block.timestamp + 7 days + 1);
        vm.prank(user1);
        vm.expectRevert("Already evaluated");
        question.emergencyRefund();
    }
}
