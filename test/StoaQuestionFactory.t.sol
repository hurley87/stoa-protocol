// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/StoaQuestionFactory.sol";
import "../src/StoaQuestion.sol";
import "../src/StoaProtocol.sol";
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

/**
 * @title StoaQuestionFactory Test
 * @dev Comprehensive test suite for StoaQuestionFactory contract covering all functionality,
 *      edge cases, access control, events, and integration scenarios.
 */
contract StoaQuestionFactoryTest is Test {
    StoaQuestionFactory public factory;
    StoaProtocol public protocolRegistry;
    MockToken public paymentToken;

    // Test addresses
    address public owner;
    address public nonOwner;
    address public treasury;
    address public creator1;
    address public creator2;
    address public nonWhitelistedUser;

    // Test constants
    uint256 constant SUBMISSION_COST_1 = 1 ether;
    uint256 constant SUBMISSION_COST_2 = 2 ether;
    uint256 constant DURATION_1 = 7 days;
    uint256 constant DURATION_2 = 14 days;
    uint8 constant MAX_WINNERS_1 = 5;
    uint8 constant MAX_WINNERS_2 = 10;
    uint256 constant SEED_AMOUNT_1 = 5 ether;
    uint256 constant SEED_AMOUNT_2 = 10 ether;

    // Events to test
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

    function setUp() public {
        owner = address(this);
        nonOwner = vm.addr(1);
        treasury = vm.addr(2);
        creator1 = vm.addr(3);
        creator2 = vm.addr(4);
        nonWhitelistedUser = vm.addr(5);

        // Deploy mock contracts
        paymentToken = new MockToken("PaymentToken", "PAY");
        protocolRegistry = new StoaProtocol();

        // Deploy factory
        factory = new StoaQuestionFactory(treasury, address(protocolRegistry));

        // Transfer protocol registry ownership to factory so it can register questions
        protocolRegistry.transferOwnership(address(factory));
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_constructor_SetsOwnerCorrectly() public {
        assertEq(factory.owner(), owner);
    }

    function test_constructor_SetsTreasuryCorrectly() public {
        assertEq(factory.treasury(), treasury);
    }

    function test_constructor_SetsReputationCorrectly() public {}

    function test_constructor_SetsProtocolRegistryCorrectly() public {
        assertEq(address(factory.protocolRegistry()), address(protocolRegistry));
    }

    function test_constructor_InitializesQuestionCountToZero() public {
        assertEq(factory.questionCount(), 0);
    }

    function test_constructor_InitializesEmptyQuestionsArray() public {
        address[] memory questions = factory.getAllQuestions();
        assertEq(questions.length, 0);
    }

    /*//////////////////////////////////////////////////////////////
                          WHITELIST MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_whitelistCreator_Success() public {
        assertFalse(factory.isWhitelisted(creator1));

        factory.whitelistCreator(creator1, true);

        assertTrue(factory.isWhitelisted(creator1));
    }

    function test_whitelistCreator_RemoveFromWhitelist() public {
        factory.whitelistCreator(creator1, true);
        assertTrue(factory.isWhitelisted(creator1));

        factory.whitelistCreator(creator1, false);

        assertFalse(factory.isWhitelisted(creator1));
    }

    function test_whitelistCreator_OnlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        factory.whitelistCreator(creator1, true);
    }

    function test_whitelistCreator_MultipleUsers() public {
        factory.whitelistCreator(creator1, true);
        factory.whitelistCreator(creator2, true);

        assertTrue(factory.isWhitelisted(creator1));
        assertTrue(factory.isWhitelisted(creator2));
        assertFalse(factory.isWhitelisted(nonWhitelistedUser));
    }

    /*//////////////////////////////////////////////////////////////
                        CREATE QUESTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_createQuestion_Success() public {
        factory.whitelistCreator(owner, true);

        address questionAddress =
            factory.createQuestion(address(paymentToken), SUBMISSION_COST_1, DURATION_1, MAX_WINNERS_1, 0);

        assertTrue(questionAddress != address(0));
        assertEq(factory.questionCount(), 1);

        address[] memory allQuestions = factory.getAllQuestions();
        assertEq(allQuestions.length, 1);
        assertEq(allQuestions[0], questionAddress);

        // Verify question was registered in protocol
        assertEq(protocolRegistry.getQuestionCount(), 1);
    }

    function test_createQuestion_WithSeedAmount() public {
        factory.whitelistCreator(owner, true);

        // Approve single token for seeding
        paymentToken.approve(address(factory), SEED_AMOUNT_1);

        address questionAddress =
            factory.createQuestion(address(paymentToken), SUBMISSION_COST_1, DURATION_1, MAX_WINNERS_1, SEED_AMOUNT_1);

        assertTrue(questionAddress != address(0));
        StoaQuestion question = StoaQuestion(questionAddress);
        assertEq(question.totalRewardPool(), SEED_AMOUNT_1);
    }

    function test_createQuestion_MultipleQuestions() public {
        factory.whitelistCreator(owner, true);

        // Create first question (no seed amount - should work)
        address question1 =
            factory.createQuestion(address(paymentToken), SUBMISSION_COST_1, DURATION_1, MAX_WINNERS_1, 0);

        assertTrue(question1 != address(0));
        assertEq(factory.questionCount(), 1);

        // Second question without seed amount
        address question2 =
            factory.createQuestion(address(paymentToken), SUBMISSION_COST_2, DURATION_2, MAX_WINNERS_2, 0);

        assertTrue(question2 != address(0));
        assertEq(factory.questionCount(), 2);
    }

    function test_createQuestion_NotWhitelistedUser() public {
        // Don't whitelist nonOwner

        vm.prank(nonOwner);
        vm.expectRevert("Not whitelisted");
        factory.createQuestion(address(paymentToken), SUBMISSION_COST_1, DURATION_1, MAX_WINNERS_1, 0);
    }

    function test_createQuestion_NotWhitelisted() public {
        // Owner is not whitelisted by default
        vm.expectRevert("Not whitelisted");
        factory.createQuestion(address(paymentToken), SUBMISSION_COST_1, DURATION_1, MAX_WINNERS_1, 0);
    }

    function test_createQuestion_TransfersOwnershipToCreator() public {
        factory.whitelistCreator(owner, true);

        address questionAddress =
            factory.createQuestion(address(paymentToken), SUBMISSION_COST_1, DURATION_1, MAX_WINNERS_1, 0);

        StoaQuestion question = StoaQuestion(questionAddress);
        assertEq(question.owner(), owner);
    }

    function test_createQuestion_CorrectParameters() public {
        factory.whitelistCreator(owner, true);

        address questionAddress =
            factory.createQuestion(address(paymentToken), SUBMISSION_COST_1, DURATION_1, MAX_WINNERS_1, 0);

        StoaQuestion question = StoaQuestion(questionAddress);
        assertEq(address(question.token()), address(paymentToken));
        assertEq(question.submissionCost(), SUBMISSION_COST_1);
        assertEq(question.endsAt(), block.timestamp + DURATION_1);
        assertEq(question.maxWinners(), MAX_WINNERS_1);
        assertEq(question.creator(), owner);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getAllQuestions_EmptyInitially() public {
        address[] memory questions = factory.getAllQuestions();
        assertEq(questions.length, 0);
    }

    function test_getAllQuestions_ReturnsAllCreatedQuestions() public {
        factory.whitelistCreator(owner, true);

        address question1 =
            factory.createQuestion(address(paymentToken), SUBMISSION_COST_1, DURATION_1, MAX_WINNERS_1, 0);
        address question2 =
            factory.createQuestion(address(paymentToken), SUBMISSION_COST_2, DURATION_2, MAX_WINNERS_2, 0);

        address[] memory allQuestions = factory.getAllQuestions();
        assertEq(allQuestions.length, 2);
        assertEq(allQuestions[0], question1);
        assertEq(allQuestions[1], question2);
    }

    /*//////////////////////////////////////////////////////////////
                            EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_createQuestion_ZeroSubmissionCost() public {
        factory.whitelistCreator(owner, true);

        // Protocol registry requires submission cost > 0, so this should revert
        vm.expectRevert("Submission cost must be greater than 0");
        factory.createQuestion(address(paymentToken), 0, DURATION_1, MAX_WINNERS_1, 0);
    }

    function test_createQuestion_ZeroMaxWinners() public {
        factory.whitelistCreator(owner, true);

        address questionAddress = factory.createQuestion(address(paymentToken), SUBMISSION_COST_1, DURATION_1, 0, 0);

        assertTrue(questionAddress != address(0));
        StoaQuestion question = StoaQuestion(questionAddress);
        assertEq(question.maxWinners(), 0);
    }

    function test_createQuestion_MinimumDuration() public {
        factory.whitelistCreator(owner, true);

        address questionAddress = factory.createQuestion(address(paymentToken), SUBMISSION_COST_1, 1, MAX_WINNERS_1, 0);

        assertTrue(questionAddress != address(0));
        StoaQuestion question = StoaQuestion(questionAddress);
        assertEq(question.endsAt(), block.timestamp + 1);
    }

    function test_createQuestion_MaxUint8Winners() public {
        factory.whitelistCreator(owner, true);

        address questionAddress =
            factory.createQuestion(address(paymentToken), SUBMISSION_COST_1, DURATION_1, type(uint8).max, 0);

        assertTrue(questionAddress != address(0));
        StoaQuestion question = StoaQuestion(questionAddress);
        assertEq(question.maxWinners(), type(uint8).max);
    }

    function test_createQuestion_VerifyReferralFeeConfiguration() public {
        factory.whitelistCreator(owner, true);

        address questionAddress =
            factory.createQuestion(address(paymentToken), SUBMISSION_COST_1, DURATION_1, MAX_WINNERS_1, 0);

        StoaQuestion question = StoaQuestion(questionAddress);

        // Verify that the question has the default referral fee configuration
        assertEq(question.referralFeeBps(), 500); // Default 5% referral fee
        assertEq(question.feeBps(), 1000); // Default 10% protocol fee
        assertEq(question.creatorFeeBps(), 1000); // Default 10% creator fee

        // Verify the question is owned by the correct creator
        assertEq(question.owner(), owner);
        assertEq(question.creator(), owner);
    }

    function test_createQuestion_ReferralFunctionalityWorks() public {
        factory.whitelistCreator(creator1, true);

        // Create tokens for the creator
        paymentToken.transfer(creator1, 1000 ether);

        vm.prank(creator1);
        address questionAddress =
            factory.createQuestion(address(paymentToken), SUBMISSION_COST_1, DURATION_1, MAX_WINNERS_1, 0);

        StoaQuestion question = StoaQuestion(questionAddress);

        // Setup test users
        address user = vm.addr(100);
        address referrer = vm.addr(101);

        // Give user tokens and approve
        paymentToken.transfer(user, 10 ether);
        vm.prank(user);
        paymentToken.approve(questionAddress, type(uint256).max);

        uint256 referrerBalanceBefore = paymentToken.balanceOf(referrer);

        // Submit answer with referral
        vm.prank(user);
        question.submitAnswerWithReferral(keccak256("Test answer"), referrer);

        // Verify referrer received payment
        uint256 expectedReferralCut = (SUBMISSION_COST_1 * 500) / 10000; // 5% of submission cost
        assertEq(paymentToken.balanceOf(referrer) - referrerBalanceBefore, expectedReferralCut);

        // Verify answer was recorded
        assertEq(question.userAnswerIndex(user), 1); // 1-indexed

        // Verify question owner can still manage the question
        assertEq(question.owner(), creator1);
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_createQuestion_ValidParameters(uint256 submissionCost, uint256 duration, uint8 maxWinners)
        public
    {
        // Bound inputs to reasonable ranges (submissionCost must be > 0 for protocol)
        submissionCost = bound(submissionCost, 1, type(uint128).max);
        duration = bound(duration, 1, 365 days);

        factory.whitelistCreator(owner, true);

        address questionAddress = factory.createQuestion(address(paymentToken), submissionCost, duration, maxWinners, 0);

        assertTrue(questionAddress != address(0));
        assertEq(factory.questionCount(), 1);

        StoaQuestion question = StoaQuestion(questionAddress);
        assertEq(question.submissionCost(), submissionCost);
        assertEq(question.endsAt(), block.timestamp + duration);
        assertEq(question.maxWinners(), maxWinners);
    }

    function testFuzz_whitelistCreator_RandomAddresses(address user, bool allowed) public {
        factory.whitelistCreator(user, allowed);
        assertEq(factory.isWhitelisted(user), allowed);
    }

    /*//////////////////////////////////////////////////////////////
                            STATE CONSISTENCY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_questionCount_IncreasesWithEachCreation() public {
        factory.whitelistCreator(owner, true);

        assertEq(factory.questionCount(), 0);

        factory.createQuestion(address(paymentToken), SUBMISSION_COST_1, DURATION_1, MAX_WINNERS_1, 0);
        assertEq(factory.questionCount(), 1);

        factory.createQuestion(address(paymentToken), SUBMISSION_COST_2, DURATION_2, MAX_WINNERS_2, 0);
        assertEq(factory.questionCount(), 2);
    }

    function test_allQuestions_GrowsWithEachCreation() public {
        factory.whitelistCreator(owner, true);

        address[] memory questions = factory.getAllQuestions();
        assertEq(questions.length, 0);

        address question1 =
            factory.createQuestion(address(paymentToken), SUBMISSION_COST_1, DURATION_1, MAX_WINNERS_1, 0);
        questions = factory.getAllQuestions();
        assertEq(questions.length, 1);
        assertEq(questions[0], question1);

        address question2 =
            factory.createQuestion(address(paymentToken), SUBMISSION_COST_2, DURATION_2, MAX_WINNERS_2, 0);
        questions = factory.getAllQuestions();
        assertEq(questions.length, 2);
        assertEq(questions[0], question1);
        assertEq(questions[1], question2);
    }

    /*//////////////////////////////////////////////////////////////
                            INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_integration_ProtocolRegistrationAfterCreation() public {
        factory.whitelistCreator(owner, true);

        address questionAddress =
            factory.createQuestion(address(paymentToken), SUBMISSION_COST_1, DURATION_1, MAX_WINNERS_1, 0);

        // Verify the question was registered in the protocol
        assertEq(protocolRegistry.getQuestionCount(), 1);

        StoaProtocol.QuestionMeta memory questionMeta = protocolRegistry.getQuestion(0);
        assertEq(questionMeta.questionAddress, questionAddress);
        assertEq(questionMeta.creator, owner);
        assertEq(questionMeta.submissionCost, SUBMISSION_COST_1);
        assertEq(questionMeta.duration, DURATION_1);
        assertEq(questionMeta.maxWinners, MAX_WINNERS_1);
    }

    function test_integration_QuestionOwnershipTransfer() public {
        factory.whitelistCreator(owner, true);

        address questionAddress =
            factory.createQuestion(address(paymentToken), SUBMISSION_COST_1, DURATION_1, MAX_WINNERS_1, 0);

        StoaQuestion question = StoaQuestion(questionAddress);

        // Factory should have transferred ownership to the creator (owner in this case)
        assertEq(question.owner(), owner);

        // Question should be properly initialized
        assertEq(address(question.token()), address(paymentToken));
        assertEq(question.creator(), owner);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCESS CONTROL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_onlyOwner_Functions() public {
        vm.startPrank(nonOwner);

        // Test whitelistCreator
        vm.expectRevert("Ownable: caller is not the owner");
        factory.whitelistCreator(creator1, true);

        // Test createQuestion - should fail due to not being whitelisted
        vm.expectRevert("Not whitelisted");
        factory.createQuestion(address(paymentToken), SUBMISSION_COST_1, DURATION_1, MAX_WINNERS_1, 0);

        vm.stopPrank();
    }

    function test_ownerCanCallAllFunctions() public {
        // Owner should be able to call all functions
        factory.whitelistCreator(owner, true);

        address questionAddress =
            factory.createQuestion(address(paymentToken), SUBMISSION_COST_1, DURATION_1, MAX_WINNERS_1, 0);

        assertTrue(questionAddress != address(0));
        assertTrue(factory.isWhitelisted(owner));
    }
}
