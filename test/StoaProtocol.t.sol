// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/StoaProtocol.sol";

/**
 * @title StoaProtocol Test
 * @dev Comprehensive test suite for StoaProtocol contract covering all functionality,
 *      edge cases, access control, events, and fuzz testing scenarios.
 */
contract StoaProtocolTest is Test {
    StoaProtocol public stoaProtocol;

    // Test addresses
    address public owner;
    address public nonOwner;
    address public questionAddress1;
    address public questionAddress2;
    address public creator1;
    address public creator2;

    // Test constants
    uint256 constant SUBMISSION_COST_1 = 1 ether;
    uint256 constant SUBMISSION_COST_2 = 2 ether;
    uint256 constant DURATION_1 = 7 days;
    uint256 constant DURATION_2 = 14 days;
    uint8 constant MAX_WINNERS_1 = 5;
    uint8 constant MAX_WINNERS_2 = 10;

    event QuestionRegistered(
        uint256 indexed id,
        address indexed question,
        address indexed creator,
        uint256 submissionCost,
        uint256 duration,
        uint8 maxWinners
    );

    function setUp() public {
        owner = address(this);
        nonOwner = vm.addr(1);
        questionAddress1 = vm.addr(2);
        questionAddress2 = vm.addr(3);
        creator1 = vm.addr(4);
        creator2 = vm.addr(5);

        stoaProtocol = new StoaProtocol();
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_constructor_SetsOwnerCorrectly() public {
        assertEq(stoaProtocol.owner(), owner);
    }

    function test_constructor_InitializesEmptyQuestionArray() public {
        assertEq(stoaProtocol.getQuestionCount(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        REGISTER QUESTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_registerQuestion_Success() public {
        vm.expectEmit(true, true, true, true);
        emit QuestionRegistered(0, questionAddress1, creator1, SUBMISSION_COST_1, DURATION_1, MAX_WINNERS_1);

        stoaProtocol.registerQuestion(questionAddress1, creator1, SUBMISSION_COST_1, DURATION_1, MAX_WINNERS_1);

        assertEq(stoaProtocol.getQuestionCount(), 1);

        StoaProtocol.QuestionMeta memory question = stoaProtocol.getQuestion(0);
        assertEq(question.questionAddress, questionAddress1);
        assertEq(question.creator, creator1);
        assertEq(question.submissionCost, SUBMISSION_COST_1);
        assertEq(question.duration, DURATION_1);
        assertEq(question.maxWinners, MAX_WINNERS_1);
        assertEq(question.createdAt, block.timestamp);
    }

    function test_registerQuestion_MultipleQuestions() public {
        // Register first question
        stoaProtocol.registerQuestion(questionAddress1, creator1, SUBMISSION_COST_1, DURATION_1, MAX_WINNERS_1);

        // Register second question
        stoaProtocol.registerQuestion(questionAddress2, creator2, SUBMISSION_COST_2, DURATION_2, MAX_WINNERS_2);

        assertEq(stoaProtocol.getQuestionCount(), 2);

        // Verify first question
        StoaProtocol.QuestionMeta memory question1 = stoaProtocol.getQuestion(0);
        assertEq(question1.questionAddress, questionAddress1);
        assertEq(question1.creator, creator1);

        // Verify second question
        StoaProtocol.QuestionMeta memory question2 = stoaProtocol.getQuestion(1);
        assertEq(question2.questionAddress, questionAddress2);
        assertEq(question2.creator, creator2);
    }

    function test_registerQuestion_RevertIf_NotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        stoaProtocol.registerQuestion(questionAddress1, creator1, SUBMISSION_COST_1, DURATION_1, MAX_WINNERS_1);
    }

    function test_registerQuestion_RevertIf_InvalidQuestionAddress() public {
        vm.expectRevert("Invalid question address");
        stoaProtocol.registerQuestion(address(0), creator1, SUBMISSION_COST_1, DURATION_1, MAX_WINNERS_1);
    }

    function test_registerQuestion_RevertIf_InvalidCreatorAddress() public {
        vm.expectRevert("Invalid creator address");
        stoaProtocol.registerQuestion(questionAddress1, address(0), SUBMISSION_COST_1, DURATION_1, MAX_WINNERS_1);
    }

    function test_registerQuestion_RevertIf_ZeroSubmissionCost() public {
        vm.expectRevert("Submission cost must be greater than 0");
        stoaProtocol.registerQuestion(questionAddress1, creator1, 0, DURATION_1, MAX_WINNERS_1);
    }

    function test_registerQuestion_RevertIf_ZeroDuration() public {
        vm.expectRevert("Duration must be greater than 0");
        stoaProtocol.registerQuestion(questionAddress1, creator1, SUBMISSION_COST_1, 0, MAX_WINNERS_1);
    }

    function test_registerQuestion_AllowsZeroMaxWinners() public {
        stoaProtocol.registerQuestion(questionAddress1, creator1, SUBMISSION_COST_1, DURATION_1, 0);

        StoaProtocol.QuestionMeta memory question = stoaProtocol.getQuestion(0);
        assertEq(question.maxWinners, 0);
    }

    /*//////////////////////////////////////////////////////////////
                            GETTER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getQuestion_ReturnsCorrectData() public {
        stoaProtocol.registerQuestion(questionAddress1, creator1, SUBMISSION_COST_1, DURATION_1, MAX_WINNERS_1);

        StoaProtocol.QuestionMeta memory question = stoaProtocol.getQuestion(0);
        assertEq(question.questionAddress, questionAddress1);
        assertEq(question.creator, creator1);
        assertEq(question.submissionCost, SUBMISSION_COST_1);
        assertEq(question.duration, DURATION_1);
        assertEq(question.maxWinners, MAX_WINNERS_1);
        assertEq(question.createdAt, block.timestamp);
    }

    function test_getAllQuestions_EmptyArray() public {
        StoaProtocol.QuestionMeta[] memory questions = stoaProtocol.getAllQuestions();
        assertEq(questions.length, 0);
    }

    function test_getAllQuestions_MultipleQuestions() public {
        // Register multiple questions
        stoaProtocol.registerQuestion(questionAddress1, creator1, SUBMISSION_COST_1, DURATION_1, MAX_WINNERS_1);

        stoaProtocol.registerQuestion(questionAddress2, creator2, SUBMISSION_COST_2, DURATION_2, MAX_WINNERS_2);

        StoaProtocol.QuestionMeta[] memory questions = stoaProtocol.getAllQuestions();
        assertEq(questions.length, 2);
        assertEq(questions[0].questionAddress, questionAddress1);
        assertEq(questions[1].questionAddress, questionAddress2);
    }

    function test_getQuestionCount_StartsAtZero() public {
        assertEq(stoaProtocol.getQuestionCount(), 0);
    }

    function test_getQuestionCount_IncrementsCorrectly() public {
        assertEq(stoaProtocol.getQuestionCount(), 0);

        stoaProtocol.registerQuestion(questionAddress1, creator1, SUBMISSION_COST_1, DURATION_1, MAX_WINNERS_1);
        assertEq(stoaProtocol.getQuestionCount(), 1);

        stoaProtocol.registerQuestion(questionAddress2, creator2, SUBMISSION_COST_2, DURATION_2, MAX_WINNERS_2);
        assertEq(stoaProtocol.getQuestionCount(), 2);
    }

    /*//////////////////////////////////////////////////////////////
                            EVENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_event_QuestionRegistered_EmittedCorrectly() public {
        vm.expectEmit(true, true, true, true);
        emit QuestionRegistered(0, questionAddress1, creator1, SUBMISSION_COST_1, DURATION_1, MAX_WINNERS_1);

        stoaProtocol.registerQuestion(questionAddress1, creator1, SUBMISSION_COST_1, DURATION_1, MAX_WINNERS_1);
    }

    function test_event_QuestionRegistered_CorrectId() public {
        // First question should have id 0
        vm.expectEmit(true, true, true, true);
        emit QuestionRegistered(0, questionAddress1, creator1, SUBMISSION_COST_1, DURATION_1, MAX_WINNERS_1);

        stoaProtocol.registerQuestion(questionAddress1, creator1, SUBMISSION_COST_1, DURATION_1, MAX_WINNERS_1);

        // Second question should have id 1
        vm.expectEmit(true, true, true, true);
        emit QuestionRegistered(1, questionAddress2, creator2, SUBMISSION_COST_2, DURATION_2, MAX_WINNERS_2);

        stoaProtocol.registerQuestion(questionAddress2, creator2, SUBMISSION_COST_2, DURATION_2, MAX_WINNERS_2);
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_registerQuestion_ValidInputs(
        address questionAddr,
        address creator,
        uint256 submissionCost,
        uint256 duration,
        uint8 maxWinners
    ) public {
        // Bound inputs to valid ranges
        vm.assume(questionAddr != address(0));
        vm.assume(creator != address(0));
        vm.assume(submissionCost > 0);
        vm.assume(duration > 0);

        stoaProtocol.registerQuestion(questionAddr, creator, submissionCost, duration, maxWinners);

        assertEq(stoaProtocol.getQuestionCount(), 1);

        StoaProtocol.QuestionMeta memory question = stoaProtocol.getQuestion(0);
        assertEq(question.questionAddress, questionAddr);
        assertEq(question.creator, creator);
        assertEq(question.submissionCost, submissionCost);
        assertEq(question.duration, duration);
        assertEq(question.maxWinners, maxWinners);
    }

    function testFuzz_registerQuestion_RevertInvalidQuestionAddress(
        address creator,
        uint256 submissionCost,
        uint256 duration,
        uint8 maxWinners
    ) public {
        vm.assume(creator != address(0));
        vm.assume(submissionCost > 0);
        vm.assume(duration > 0);

        vm.expectRevert("Invalid question address");
        stoaProtocol.registerQuestion(address(0), creator, submissionCost, duration, maxWinners);
    }

    function testFuzz_registerQuestion_RevertInvalidCreator(
        address questionAddr,
        uint256 submissionCost,
        uint256 duration,
        uint8 maxWinners
    ) public {
        vm.assume(questionAddr != address(0));
        vm.assume(submissionCost > 0);
        vm.assume(duration > 0);

        vm.expectRevert("Invalid creator address");
        stoaProtocol.registerQuestion(questionAddr, address(0), submissionCost, duration, maxWinners);
    }

    function testFuzz_registerQuestion_RevertZeroSubmissionCost(
        address questionAddr,
        address creator,
        uint256 duration,
        uint8 maxWinners
    ) public {
        vm.assume(questionAddr != address(0));
        vm.assume(creator != address(0));
        vm.assume(duration > 0);

        vm.expectRevert("Submission cost must be greater than 0");
        stoaProtocol.registerQuestion(questionAddr, creator, 0, duration, maxWinners);
    }

    function testFuzz_registerQuestion_RevertZeroDuration(
        address questionAddr,
        address creator,
        uint256 submissionCost,
        uint8 maxWinners
    ) public {
        vm.assume(questionAddr != address(0));
        vm.assume(creator != address(0));
        vm.assume(submissionCost > 0);

        vm.expectRevert("Duration must be greater than 0");
        stoaProtocol.registerQuestion(questionAddr, creator, submissionCost, 0, maxWinners);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_registerQuestion_MaxUint256Values() public {
        stoaProtocol.registerQuestion(questionAddress1, creator1, type(uint256).max, type(uint256).max, type(uint8).max);

        StoaProtocol.QuestionMeta memory question = stoaProtocol.getQuestion(0);
        assertEq(question.submissionCost, type(uint256).max);
        assertEq(question.duration, type(uint256).max);
        assertEq(question.maxWinners, type(uint8).max);
    }

    function test_registerQuestion_MinValidValues() public {
        stoaProtocol.registerQuestion(
            questionAddress1,
            creator1,
            1, // minimum valid submission cost
            1, // minimum valid duration
            0 // minimum valid max winners
        );

        StoaProtocol.QuestionMeta memory question = stoaProtocol.getQuestion(0);
        assertEq(question.submissionCost, 1);
        assertEq(question.duration, 1);
        assertEq(question.maxWinners, 0);
    }

    function test_getQuestion_OutOfBounds() public {
        // This should revert due to array bounds check
        vm.expectRevert();
        stoaProtocol.getQuestion(0);
    }

    function test_registerQuestion_LargeNumberOfQuestions() public {
        uint256 numQuestions = 100;

        for (uint256 i = 0; i < numQuestions; i++) {
            address questionAddr = vm.addr(i + 100); // Generate unique addresses
            address creator = vm.addr(i + 200);

            stoaProtocol.registerQuestion(questionAddr, creator, SUBMISSION_COST_1, DURATION_1, MAX_WINNERS_1);
        }

        assertEq(stoaProtocol.getQuestionCount(), numQuestions);

        // Verify first and last questions
        StoaProtocol.QuestionMeta memory firstQuestion = stoaProtocol.getQuestion(0);
        assertEq(firstQuestion.questionAddress, vm.addr(100));

        StoaProtocol.QuestionMeta memory lastQuestion = stoaProtocol.getQuestion(numQuestions - 1);
        assertEq(lastQuestion.questionAddress, vm.addr(199));
    }

    /*//////////////////////////////////////////////////////////////
                        ACCESS CONTROL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_onlyOwner_CanRegisterQuestions() public {
        // Owner should be able to register
        stoaProtocol.registerQuestion(questionAddress1, creator1, SUBMISSION_COST_1, DURATION_1, MAX_WINNERS_1);

        assertEq(stoaProtocol.getQuestionCount(), 1);
    }

    function test_nonOwner_CannotRegisterQuestions() public {
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        stoaProtocol.registerQuestion(questionAddress1, creator1, SUBMISSION_COST_1, DURATION_1, MAX_WINNERS_1);
    }

    function test_publicViews_AccessibleByAnyone() public {
        // Register a question first
        stoaProtocol.registerQuestion(questionAddress1, creator1, SUBMISSION_COST_1, DURATION_1, MAX_WINNERS_1);

        // Non-owner should be able to call view functions
        vm.prank(nonOwner);
        assertEq(stoaProtocol.getQuestionCount(), 1);

        vm.prank(nonOwner);
        StoaProtocol.QuestionMeta memory question = stoaProtocol.getQuestion(0);
        assertEq(question.questionAddress, questionAddress1);

        vm.prank(nonOwner);
        StoaProtocol.QuestionMeta[] memory allQuestions = stoaProtocol.getAllQuestions();
        assertEq(allQuestions.length, 1);
    }

    /*//////////////////////////////////////////////////////////////
                        TIMESTAMP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_createdAt_TimestampAccuracy() public {
        uint256 timestampBefore = block.timestamp;

        stoaProtocol.registerQuestion(questionAddress1, creator1, SUBMISSION_COST_1, DURATION_1, MAX_WINNERS_1);

        uint256 timestampAfter = block.timestamp;

        StoaProtocol.QuestionMeta memory question = stoaProtocol.getQuestion(0);
        assertGe(question.createdAt, timestampBefore);
        assertLe(question.createdAt, timestampAfter);
    }

    function test_createdAt_DifferentTimestamps() public {
        // Register first question
        stoaProtocol.registerQuestion(questionAddress1, creator1, SUBMISSION_COST_1, DURATION_1, MAX_WINNERS_1);

        uint256 firstTimestamp = stoaProtocol.getQuestion(0).createdAt;

        // Advance time
        vm.warp(block.timestamp + 1 hours);

        // Register second question
        stoaProtocol.registerQuestion(questionAddress2, creator2, SUBMISSION_COST_2, DURATION_2, MAX_WINNERS_2);

        uint256 secondTimestamp = stoaProtocol.getQuestion(1).createdAt;

        assertGt(secondTimestamp, firstTimestamp);
        assertEq(secondTimestamp - firstTimestamp, 1 hours);
    }
}
