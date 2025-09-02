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
    address public creator;
    address public user1;
    address public user2;
    address public user3;
    address public submitter;
    address public funder;
    address public referrer;

    uint256 public constant SUBMISSION_COST = 10 * 10 ** 18; // 10 tokens
    uint256 public constant DURATION = 7 days;
    uint8 public constant MAX_WINNERS = 3;
    uint256 public constant INITIAL_BALANCE = 1000 * 10 ** 18;

    // Events for testing
    event AnswerSubmitted(address indexed responder, uint256 index);
    event AnswerSubmittedWithReferral(address indexed responder, uint256 index, address indexed referrer);
    event Evaluated(uint256[] rankedAnswerIndices);
    event RewardClaimed(address indexed user, uint256 amount);
    event Seeded(address indexed funder, uint256 amount);
    event FeeUpdated(uint256 newFeeBps);
    event ReferralFeeUpdated(uint256 newReferralFeeBps);
    event TreasuryUpdated(address newTreasury);

    function setUp() public {
        owner = address(this);
        treasury = makeAddr("treasury");
        creator = makeAddr("creator");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        submitter = makeAddr("submitter");
        funder = makeAddr("funder");
        referrer = makeAddr("referrer");

        // Deploy token and reputation system
        paymentToken = new MockToken("PaymentToken", "PAY");

        // Deploy question contract with single token
        vm.prank(creator);
        question = new StoaQuestion(address(paymentToken), SUBMISSION_COST, DURATION, MAX_WINNERS, treasury, creator);

        // Distribute tokens to users
        paymentToken.mint(user1, INITIAL_BALANCE);
        paymentToken.mint(user2, INITIAL_BALANCE);
        paymentToken.mint(user3, INITIAL_BALANCE);
        paymentToken.mint(submitter, INITIAL_BALANCE);
        paymentToken.mint(funder, INITIAL_BALANCE);
        paymentToken.mint(referrer, INITIAL_BALANCE);

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
        vm.prank(referrer);
        paymentToken.approve(address(question), type(uint256).max);
    }

    // Constructor Tests
    function testConstructor() public {
        assertEq(address(question.token()), address(paymentToken));
        assertEq(question.submissionCost(), SUBMISSION_COST);
        assertEq(question.maxWinners(), MAX_WINNERS);
        assertEq(question.creator(), creator);
        assertEq(question.treasury(), treasury);
        assertEq(question.creator(), creator);
        assertEq(question.feeBps(), 1000); // 10% default fee
        assertEq(question.creatorFeeBps(), 1000); // 10% default creator fee
        assertEq(question.referralFeeBps(), 500); // 5% default referral fee
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
        uint256 referralCut = SUBMISSION_COST * 500 / 10000; // 5% referral fee (goes to reward pool when no referrer)
        uint256 expectedRewardCut = SUBMISSION_COST - protocolCut - creatorCut; // includes referral cut since no referrer

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

        // Check total reward pool increased (includes referral cut since no referrer)
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
            treasury,
            creator
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

        vm.prank(creator);
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

        vm.prank(creator);
        vm.expectRevert("Too early");
        question.evaluateAnswers(rankedIndices);
    }

    function testEvaluateAnswersAlreadyEvaluated() public {
        vm.warp(block.timestamp + DURATION + 1);

        uint256[] memory rankedIndices = new uint256[](0);

        vm.prank(creator);
        question.evaluateAnswers(rankedIndices);

        vm.prank(creator);
        vm.expectRevert("Already evaluated");
        question.evaluateAnswers(rankedIndices);
    }

    function testEvaluateAnswersTooManyWinners() public {
        vm.warp(block.timestamp + DURATION + 1);

        uint256[] memory rankedIndices = new uint256[](MAX_WINNERS + 1);
        for (uint256 i = 0; i < MAX_WINNERS + 1; i++) {
            rankedIndices[i] = i;
        }

        vm.prank(creator);
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

        vm.prank(creator);
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

        vm.prank(creator);
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

        vm.prank(creator);
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

        vm.prank(creator);
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

        vm.prank(creator);
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

        vm.prank(creator);
        question.evaluateAnswers(rankedIndices);

        assertTrue(question.evaluated());
        assertEq(question.totalScore(), 0);
    }

    function testSubmissionCostCalculation() public {
        uint256 submissionCost = SUBMISSION_COST; // Use the actual submission cost from the contract
        uint256 feeBps = 1000; // 10% protocol fee
        uint256 creatorFeeBps = 1000; // 10% creator fee
        uint256 referralFeeBps = 500; // 5% referral fee

        uint256 expectedProtocolCut = (submissionCost * feeBps) / 10000;
        uint256 expectedCreatorCut = (submissionCost * creatorFeeBps) / 10000;
        uint256 expectedReferralCut = (submissionCost * referralFeeBps) / 10000;
        uint256 expectedRewardCut = submissionCost - expectedProtocolCut - expectedCreatorCut; // includes referral cut when no referrer

        uint256 creatorBalanceBefore = paymentToken.balanceOf(creator);

        vm.prank(user1);
        question.submitAnswer(keccak256("Answer"));

        assertEq(paymentToken.balanceOf(treasury), expectedProtocolCut);
        assertEq(paymentToken.balanceOf(creator) - creatorBalanceBefore, expectedCreatorCut);
        assertEq(question.totalRewardPool(), expectedRewardCut);
        assertEq(paymentToken.balanceOf(referrer), INITIAL_BALANCE); // No referrer used, so referrer balance unchanged
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

        vm.prank(creator);
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
        vm.prank(creator);
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

        vm.prank(creator);
        question.evaluateAnswers(rankedIndices);

        uint256 gasBefore = gasleft();
        vm.prank(user1);
        question.claimReward();
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for claimReward:", gasUsed);
    }

    // Referral Mechanism Tests
    function testSubmitAnswerWithReferral() public {
        bytes32 answerHash = keccak256("Answer with referral");
        uint256 protocolCut = SUBMISSION_COST * 1000 / 10000; // 10% protocol fee
        uint256 creatorCut = SUBMISSION_COST * 1000 / 10000; // 10% creator fee
        uint256 referralCut = SUBMISSION_COST * 500 / 10000; // 5% referral fee
        uint256 expectedRewardCut = SUBMISSION_COST - protocolCut - creatorCut - referralCut;

        uint256 creatorBalanceBefore = paymentToken.balanceOf(creator);
        uint256 referrerBalanceBefore = paymentToken.balanceOf(referrer);

        vm.expectEmit(true, false, false, true);
        emit AnswerSubmittedWithReferral(user1, 0, referrer);

        vm.prank(user1);
        question.submitAnswerWithReferral(answerHash, referrer);

        // Check answer was recorded
        StoaQuestion.Answer memory answer = question.getAnswer(0);
        assertEq(answer.responder, user1);
        assertEq(answer.answerHash, answerHash);

        // Check fee distribution
        assertEq(paymentToken.balanceOf(treasury), protocolCut);
        assertEq(paymentToken.balanceOf(creator) - creatorBalanceBefore, creatorCut);
        assertEq(paymentToken.balanceOf(referrer) - referrerBalanceBefore, referralCut);
        assertEq(question.totalRewardPool(), expectedRewardCut);
    }

    function testSubmitAnswerWithZeroReferrer() public {
        bytes32 answerHash = keccak256("Answer with zero referrer");
        uint256 protocolCut = SUBMISSION_COST * 1000 / 10000;
        uint256 creatorCut = SUBMISSION_COST * 1000 / 10000;
        uint256 referralCut = SUBMISSION_COST * 500 / 10000; // Goes to reward pool
        uint256 expectedRewardCut = SUBMISSION_COST - protocolCut - creatorCut; // includes referral cut

        vm.expectEmit(true, false, false, true);
        emit AnswerSubmitted(user1, 0); // Should emit regular event, not referral event

        vm.prank(user1);
        question.submitAnswerWithReferral(answerHash, address(0));

        assertEq(question.totalRewardPool(), expectedRewardCut);
        assertEq(paymentToken.balanceOf(address(0)), 0); // Zero address gets nothing
    }

    function testSubmitAnswerForWithReferral() public {
        bytes32 answerHash = keccak256("Answer for user with referral");

        // Authorize submitter
        vm.prank(creator);
        question.setSubmitter(submitter, true);

        uint256 referrerBalanceBefore = paymentToken.balanceOf(referrer);
        uint256 referralCut = SUBMISSION_COST * 500 / 10000;

        vm.expectEmit(true, false, false, true);
        emit AnswerSubmittedWithReferral(user1, 0, referrer);

        vm.prank(submitter);
        question.submitAnswerForWithReferral(user1, answerHash, referrer);

        // Check answer attributed to user1
        StoaQuestion.Answer memory answer = question.getAnswer(0);
        assertEq(answer.responder, user1);
        assertEq(question.userAnswerIndex(user1), 1);

        // Check referrer got paid
        assertEq(paymentToken.balanceOf(referrer) - referrerBalanceBefore, referralCut);
    }

    function testSubmitAnswerForWithZeroReferrer() public {
        vm.prank(creator);
        question.setSubmitter(submitter, true);

        vm.expectEmit(true, false, false, true);
        emit AnswerSubmitted(user1, 0); // Regular event when no referrer

        vm.prank(submitter);
        question.submitAnswerForWithReferral(user1, keccak256("Answer"), address(0));

        assertEq(question.userAnswerIndex(user1), 1);
    }

    function testReferralFeeCalculationAccuracy() public {
        // Test with different submission costs to ensure accurate calculations
        uint256[] memory costs = new uint256[](3);
        costs[0] = 1000; // Small amount
        costs[1] = 12345; // Odd amount
        costs[2] = 1000000; // Large amount

        for (uint256 i = 0; i < costs.length; i++) {
            // Deploy new question with different cost
            vm.prank(creator);
            StoaQuestion testQuestion =
                new StoaQuestion(address(paymentToken), costs[i], DURATION, MAX_WINNERS, treasury, creator);

            vm.prank(user1);
            paymentToken.approve(address(testQuestion), type(uint256).max);

            uint256 referrerBalanceBefore = paymentToken.balanceOf(referrer);

            vm.prank(user1);
            testQuestion.submitAnswerWithReferral(keccak256(abi.encodePacked("Answer", i)), referrer);

            uint256 expectedReferralCut = (costs[i] * 500) / 10000;
            uint256 actualReferralCut = paymentToken.balanceOf(referrer) - referrerBalanceBefore;

            assertEq(actualReferralCut, expectedReferralCut, "Referral cut calculation incorrect");
        }
    }

    function testReferralWithCompleteWorkflow() public {
        // Seed question
        uint256 seedAmount = 500 * 10 ** 18;
        vm.prank(funder);
        question.seedQuestion(seedAmount);

        // Submit answers with referrals
        vm.prank(user1);
        question.submitAnswerWithReferral(keccak256("Best answer"), referrer);
        vm.prank(user2);
        question.submitAnswer(keccak256("Good answer")); // No referral
        vm.prank(user3);
        question.submitAnswerWithReferral(keccak256("Ok answer"), referrer);

        // Check referrer got paid twice (they had initial balance from setup)
        uint256 expectedReferralTotal = (SUBMISSION_COST * 500 / 10000) * 2;
        uint256 initialReferrerBalance = INITIAL_BALANCE; // From setup
        assertEq(paymentToken.balanceOf(referrer), initialReferrerBalance + expectedReferralTotal);

        // Complete evaluation and rewards
        vm.warp(block.timestamp + DURATION + 1);

        uint256[] memory rankedIndices = new uint256[](2);
        rankedIndices[0] = 0; // user1 wins
        rankedIndices[1] = 1; // user2 second

        vm.prank(creator);
        question.evaluateAnswers(rankedIndices);

        // Claim rewards - should work normally despite referral mechanism
        vm.prank(user1);
        question.claimReward();
        vm.prank(user2);
        question.claimReward();

        assertTrue(question.getAnswer(0).rewarded);
        assertTrue(question.getAnswer(1).rewarded);
        assertFalse(question.getAnswer(2).rewarded);
    }

    function testFuzzReferralCalculation(uint256 submissionCost, uint16 referralBps) public {
        vm.assume(submissionCost > 0 && submissionCost <= paymentToken.balanceOf(user1));
        vm.assume(referralBps <= 10000); // Max 100%

        // Ensure total fees don't exceed 100% to prevent overflow
        uint256 totalFees = 1000 + 1000 + referralBps; // protocol + creator + referral
        vm.assume(totalFees <= 10000);
        vm.assume(submissionCost >= totalFees); // Prevent underflow in reward calculation

        // Deploy question with fuzzed parameters
        vm.prank(creator);
        StoaQuestion fuzzQuestion =
            new StoaQuestion(address(paymentToken), submissionCost, DURATION, MAX_WINNERS, treasury, creator);

        // Set custom referral fee
        vm.prank(creator);
        fuzzQuestion.setReferralFeeBps(referralBps);

        vm.prank(user1);
        paymentToken.approve(address(fuzzQuestion), type(uint256).max);

        uint256 referrerBalanceBefore = paymentToken.balanceOf(referrer);

        vm.prank(user1);
        fuzzQuestion.submitAnswerWithReferral(keccak256("Fuzz answer"), referrer);

        uint256 expectedReferralCut = (submissionCost * referralBps) / 10000;
        uint256 actualReferralCut = paymentToken.balanceOf(referrer) - referrerBalanceBefore;

        assertEq(actualReferralCut, expectedReferralCut);
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

        vm.prank(creator);
        question.evaluateAnswers(rankedIndices);

        // Try emergency refund after evaluation
        vm.warp(block.timestamp + 7 days + 1);
        vm.prank(user1);
        vm.expectRevert("Already evaluated");
        question.emergencyRefund();
    }

    // Test referral fee configuration
    function testSetReferralFeeBps() public {
        vm.expectEmit(true, false, false, true);
        emit ReferralFeeUpdated(750); // 7.5%

        vm.prank(creator);
        question.setReferralFeeBps(750);

        assertEq(question.referralFeeBps(), 750);
    }

    function testSetReferralFeeBpsOnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        question.setReferralFeeBps(750);
    }

    function testSetReferralFeeBpsMaxLimit() public {
        vm.prank(creator);
        vm.expectRevert("Referral fee cannot exceed 100%");
        question.setReferralFeeBps(10001); // 100.01%
    }

    // ============= NEW UTILITY FUNCTION TESTS =============

    // Question Status Function Tests
    function testIsActive() public {
        // Should be active initially
        assertTrue(question.isActive());

        // Should be inactive after end time
        vm.warp(block.timestamp + DURATION + 1);
        assertFalse(question.isActive());
    }

    function testIsEvaluationPeriod() public {
        // Should not be in evaluation period initially
        assertFalse(question.isEvaluationPeriod());

        // Should be in evaluation period after question ends but before evaluation deadline
        vm.warp(block.timestamp + DURATION + 1);
        assertTrue(question.isEvaluationPeriod());

        // Should not be in evaluation period after evaluation deadline
        vm.warp(block.timestamp + 8 days);
        assertFalse(question.isEvaluationPeriod());

        // Test with a fresh question for evaluation scenario
        StoaQuestion freshQuestion =
            new StoaQuestion(address(paymentToken), SUBMISSION_COST, DURATION, MAX_WINNERS, treasury, creator);

        // Submit answer to fresh question
        vm.prank(user1);
        paymentToken.approve(address(freshQuestion), SUBMISSION_COST);
        vm.prank(user1);
        freshQuestion.submitAnswer(keccak256("answer1"));

        // Should be in evaluation period after question ends
        vm.warp(block.timestamp + DURATION + 1);
        assertTrue(freshQuestion.isEvaluationPeriod());

        // Evaluate and should not be in evaluation period anymore
        uint256[] memory rankedIndices = new uint256[](1);
        rankedIndices[0] = 0;

        vm.prank(creator);
        freshQuestion.evaluateAnswers(rankedIndices);

        assertFalse(freshQuestion.isEvaluationPeriod());
    }

    function testTimeRemaining() public {
        // Should return correct time remaining
        uint256 remaining = question.timeRemaining();
        assertEq(remaining, DURATION);

        // Should decrease over time
        vm.warp(block.timestamp + 1 days);
        remaining = question.timeRemaining();
        assertEq(remaining, DURATION - 1 days);

        // Should return 0 after end time
        vm.warp(block.timestamp + DURATION);
        remaining = question.timeRemaining();
        assertEq(remaining, 0);
    }

    function testGetQuestionStatus() public {
        // Should be "Active" initially
        assertEq(question.getQuestionStatus(), "Active");

        // Should be "AwaitingEvaluation" after question ends
        vm.warp(block.timestamp + DURATION + 1);
        assertEq(question.getQuestionStatus(), "AwaitingEvaluation");

        // Submit answer and evaluate
        vm.warp(block.timestamp - DURATION - 1); // Back to active period
        vm.prank(user1);
        question.submitAnswer(keccak256("answer1"));

        vm.warp(block.timestamp + DURATION + 1);
        uint256[] memory rankedIndices = new uint256[](1);
        rankedIndices[0] = 0;

        vm.prank(creator);
        question.evaluateAnswers(rankedIndices);

        assertEq(question.getQuestionStatus(), "Evaluated");

        // Test emergency refund status with a new question
        StoaQuestion newQuestion =
            new StoaQuestion(address(paymentToken), SUBMISSION_COST, DURATION, MAX_WINNERS, treasury, creator);

        vm.prank(user1);
        paymentToken.approve(address(newQuestion), SUBMISSION_COST);
        vm.prank(user1);
        newQuestion.submitAnswer(keccak256("answer1"));

        // Wait past evaluation deadline without evaluating
        vm.warp(block.timestamp + DURATION + 8 days);
        assertEq(newQuestion.getQuestionStatus(), "EmergencyRefundAvailable");
    }

    // Participant Information Function Tests
    function testGetAnswerCount() public {
        assertEq(question.getAnswerCount(), 0);

        vm.prank(user1);
        question.submitAnswer(keccak256("answer1"));
        assertEq(question.getAnswerCount(), 1);

        vm.prank(user2);
        question.submitAnswer(keccak256("answer2"));
        assertEq(question.getAnswerCount(), 2);
    }

    function testHasUserSubmitted() public {
        assertFalse(question.hasUserSubmitted(user1));
        assertFalse(question.hasUserSubmitted(user2));

        vm.prank(user1);
        question.submitAnswer(keccak256("answer1"));

        assertTrue(question.hasUserSubmitted(user1));
        assertFalse(question.hasUserSubmitted(user2));

        vm.prank(user2);
        question.submitAnswer(keccak256("answer2"));

        assertTrue(question.hasUserSubmitted(user1));
        assertTrue(question.hasUserSubmitted(user2));
    }

    function testGetWinnerAddresses() public {
        // Submit answers
        vm.prank(user1);
        question.submitAnswer(keccak256("answer1"));
        vm.prank(user2);
        question.submitAnswer(keccak256("answer2"));
        vm.prank(user3);
        question.submitAnswer(keccak256("answer3"));

        // No winners before evaluation
        address[] memory winners = question.getWinnerAddresses();
        assertEq(winners.length, 0);

        // Evaluate with 2 winners
        vm.warp(block.timestamp + DURATION + 1);
        uint256[] memory rankedIndices = new uint256[](2);
        rankedIndices[0] = 0; // user1 - 1st place
        rankedIndices[1] = 2; // user3 - 2nd place

        vm.prank(creator);
        question.evaluateAnswers(rankedIndices);

        winners = question.getWinnerAddresses();
        assertEq(winners.length, 2);
        // Check that winners contain user1 and user3 (order doesn't matter in getWinnerAddresses)
        assertTrue(winners[0] == user1 || winners[1] == user1);
        assertTrue(winners[0] == user3 || winners[1] == user3);
    }

    function testGetRankedWinners() public {
        // Submit answers
        vm.prank(user1);
        question.submitAnswer(keccak256("answer1"));
        vm.prank(user2);
        question.submitAnswer(keccak256("answer2"));
        vm.prank(user3);
        question.submitAnswer(keccak256("answer3"));

        // Evaluate with all 3 winners in specific order
        vm.warp(block.timestamp + DURATION + 1);
        uint256[] memory rankedIndices = new uint256[](3);
        rankedIndices[0] = 2; // user3 - 1st place (score 3)
        rankedIndices[1] = 0; // user1 - 2nd place (score 2)
        rankedIndices[2] = 1; // user2 - 3rd place (score 1)

        vm.prank(creator);
        question.evaluateAnswers(rankedIndices);

        (address[] memory addresses, uint256[] memory scores) = question.getRankedWinners();

        assertEq(addresses.length, 3);
        assertEq(scores.length, 3);

        // Should be sorted by score descending
        assertEq(addresses[0], user3); // 1st place
        assertEq(scores[0], 3);
        assertEq(addresses[1], user1); // 2nd place
        assertEq(scores[1], 2);
        assertEq(addresses[2], user2); // 3rd place
        assertEq(scores[2], 1);
    }

    // Reward Pool Information Function Tests
    function testGetTotalClaimed() public {
        // Setup answers and evaluation
        vm.prank(user1);
        question.submitAnswer(keccak256("answer1"));
        vm.prank(user2);
        question.submitAnswer(keccak256("answer2"));

        // Seed the question for rewards
        uint256 seedAmount = 100 * 10 ** 18;
        vm.prank(funder);
        question.seedQuestion(seedAmount);

        // Before evaluation, should return 0
        assertEq(question.getTotalClaimed(), 0);

        vm.warp(block.timestamp + DURATION + 1);
        uint256[] memory rankedIndices = new uint256[](2);
        rankedIndices[0] = 0; // user1 - score 2
        rankedIndices[1] = 1; // user2 - score 1

        vm.prank(creator);
        question.evaluateAnswers(rankedIndices);

        // After evaluation but no claims yet
        assertEq(question.getTotalClaimed(), 0);

        // User1 claims (should get 2/3 of total pool)
        vm.prank(user1);
        question.claimReward();

        uint256 totalPool = question.totalRewardPool();
        uint256 claimedAfterUser1 = question.getTotalClaimed();

        // User2 claims (should get 1/3 of total pool)
        vm.prank(user2);
        question.claimReward();

        uint256 totalClaimedAfterBoth = question.getTotalClaimed();

        // The total claimed should equal the total pool (minus any rounding)
        assertEq(totalClaimedAfterBoth, totalPool);
    }

    function testGetUnclaimedRewards() public {
        // Setup answers and evaluation
        vm.prank(user1);
        question.submitAnswer(keccak256("answer1"));
        vm.prank(user2);
        question.submitAnswer(keccak256("answer2"));

        // Seed the question for rewards
        uint256 seedAmount = 100 * 10 ** 18;
        vm.prank(funder);
        question.seedQuestion(seedAmount);

        uint256 totalPool = question.totalRewardPool();

        // Before evaluation, unclaimed should be total pool
        assertEq(question.getUnclaimedRewards(), totalPool);

        vm.warp(block.timestamp + DURATION + 1);
        uint256[] memory rankedIndices = new uint256[](2);
        rankedIndices[0] = 0; // user1 - score 2
        rankedIndices[1] = 1; // user2 - score 1

        vm.prank(creator);
        question.evaluateAnswers(rankedIndices);

        // After evaluation, unclaimed should still be total pool
        assertEq(question.getUnclaimedRewards(), totalPool);

        // User1 claims
        vm.prank(user1);
        question.claimReward();

        uint256 unclaimedAfterUser1 = question.getUnclaimedRewards();
        assertTrue(unclaimedAfterUser1 < totalPool); // Should be less than total pool

        // User2 claims
        vm.prank(user2);
        question.claimReward();

        // After all users claim, unclaimed should be 0 (or very close due to rounding)
        assertEq(question.getUnclaimedRewards(), 0);
    }

    // Emergency/Admin Function Tests
    function testCanEmergencyRefund() public {
        // Create fresh question for this test
        StoaQuestion freshQuestion =
            new StoaQuestion(address(paymentToken), SUBMISSION_COST, DURATION, MAX_WINNERS, treasury, creator);

        // Should not be available initially
        assertFalse(freshQuestion.canEmergencyRefund());

        // Should not be available during active period
        vm.warp(block.timestamp + DURATION - 1);
        assertFalse(freshQuestion.canEmergencyRefund());

        // Should not be available during evaluation period
        vm.warp(block.timestamp + DURATION + 1);
        assertFalse(freshQuestion.canEmergencyRefund());

        // Should be available after evaluation deadline without evaluation
        vm.warp(block.timestamp + 8 days);
        assertTrue(freshQuestion.canEmergencyRefund());

        // Create another question to test evaluated scenario
        vm.warp(block.timestamp - DURATION - 8 days); // Reset time
        StoaQuestion evaluatedQuestion =
            new StoaQuestion(address(paymentToken), SUBMISSION_COST, DURATION, MAX_WINNERS, treasury, creator);

        vm.prank(user1);
        paymentToken.approve(address(evaluatedQuestion), SUBMISSION_COST);
        vm.prank(user1);
        evaluatedQuestion.submitAnswer(keccak256("answer1"));

        vm.warp(block.timestamp + DURATION + 1);
        uint256[] memory rankedIndices = new uint256[](1);
        rankedIndices[0] = 0;

        vm.prank(creator);
        evaluatedQuestion.evaluateAnswers(rankedIndices);

        vm.warp(block.timestamp + 8 days);
        assertFalse(evaluatedQuestion.canEmergencyRefund());
    }

    function testGetEmergencyRefundAmount() public {
        // Should return 0 initially
        assertEq(question.getEmergencyRefundAmount(), 0);

        // Submit answers and seed
        vm.prank(user1);
        question.submitAnswer(keccak256("answer1"));
        vm.prank(user2);
        question.submitAnswer(keccak256("answer2"));

        uint256 seedAmount = 100 * 10 ** 18;
        vm.prank(funder);
        question.seedQuestion(seedAmount);

        uint256 totalPool = question.totalRewardPool();

        // Should return 0 during active period
        assertEq(question.getEmergencyRefundAmount(), 0);

        // Should return 0 during evaluation period
        vm.warp(block.timestamp + DURATION + 1);
        assertEq(question.getEmergencyRefundAmount(), 0);

        // Should return equal distribution after evaluation deadline
        vm.warp(block.timestamp + DURATION + 8 days);
        assertEq(question.getEmergencyRefundAmount(), totalPool / 2); // 2 participants

        // Should return 0 if evaluated
        vm.warp(block.timestamp - 8 days); // Back to evaluation period

        uint256[] memory rankedIndices = new uint256[](1);
        rankedIndices[0] = 0;

        vm.prank(creator);
        question.evaluateAnswers(rankedIndices);

        vm.warp(block.timestamp + 8 days);
        assertEq(question.getEmergencyRefundAmount(), 0);
    }

    // Batch Operations Function Tests
    function testGetMultipleClaimableAmounts() public {
        // Setup answers and evaluation
        vm.prank(user1);
        question.submitAnswer(keccak256("answer1"));
        vm.prank(user2);
        question.submitAnswer(keccak256("answer2"));
        vm.prank(user3);
        question.submitAnswer(keccak256("answer3"));

        // Seed the question
        uint256 seedAmount = 100 * 10 ** 18;
        vm.prank(funder);
        question.seedQuestion(seedAmount);

        // Test before evaluation
        address[] memory users = new address[](4);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;
        users[3] = makeAddr("nonParticipant");

        uint256[] memory amounts = question.getMultipleClaimableAmounts(users);

        // All should be 0 before evaluation
        for (uint256 i = 0; i < amounts.length; i++) {
            assertEq(amounts[i], 0);
        }

        // Evaluate
        vm.warp(block.timestamp + DURATION + 1);
        uint256[] memory rankedIndices = new uint256[](2);
        rankedIndices[0] = 0; // user1 - score 2
        rankedIndices[1] = 2; // user3 - score 1

        vm.prank(creator);
        question.evaluateAnswers(rankedIndices);

        // Test after evaluation
        amounts = question.getMultipleClaimableAmounts(users);

        assertTrue(amounts[0] > 0); // user1 - winner
        assertEq(amounts[1], 0); // user2 - not a winner
        assertTrue(amounts[2] > 0); // user3 - winner
        assertEq(amounts[3], 0); // non-participant

        uint256 user1ClaimableAmount = amounts[0];
        uint256 user3ClaimableAmount = amounts[2];

        // User1 claims
        vm.prank(user1);
        question.claimReward();

        // Test after partial claiming
        amounts = question.getMultipleClaimableAmounts(users);

        assertEq(amounts[0], 0); // user1 - already claimed
        assertEq(amounts[1], 0); // user2 - not a winner
        assertEq(amounts[2], user3ClaimableAmount); // user3 - still can claim same amount
        assertEq(amounts[3], 0); // non-participant
    }

    function testGetMultipleClaimableAmountsEmptyArray() public {
        address[] memory users = new address[](0);
        uint256[] memory amounts = question.getMultipleClaimableAmounts(users);
        assertEq(amounts.length, 0);
    }

    // Test getClaimableAmount function that was added earlier
    function testGetClaimableAmount() public {
        // Should return 0 for non-participant
        assertEq(question.getClaimableAmount(user1), 0);

        // Submit answer
        vm.prank(user1);
        question.submitAnswer(keccak256("answer1"));

        // Should return 0 before evaluation
        assertEq(question.getClaimableAmount(user1), 0);

        // Seed the question
        uint256 seedAmount = 100 * 10 ** 18;
        vm.prank(funder);
        question.seedQuestion(seedAmount);

        // Evaluate
        vm.warp(block.timestamp + DURATION + 1);
        uint256[] memory rankedIndices = new uint256[](1);
        rankedIndices[0] = 0; // user1 wins

        vm.prank(creator);
        question.evaluateAnswers(rankedIndices);

        // Should return claimable amount
        uint256 expectedAmount = question.totalRewardPool();
        assertEq(question.getClaimableAmount(user1), expectedAmount);

        // Claim
        vm.prank(user1);
        question.claimReward();

        // Should return 0 after claiming
        assertEq(question.getClaimableAmount(user1), 0);
    }
}
