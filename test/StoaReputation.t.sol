// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/StoaReputation.sol";
import "solady/utils/FixedPointMathLib.sol";

/**
 * @title StoaReputation Test
 * @dev Comprehensive test suite for the StoaReputation contract covering:
 *      - Access controls and ownership
 *      - Submission and reward recording
 *      - Decay rate management
 *      - Effective score calculations with time-based decay
 *      - Event emissions
 *      - Edge cases and error conditions
 */
contract StoaReputationTest is Test {
    StoaReputation _reputation;
    address _owner;
    address _user1;
    address _user2;
    address _nonOwner;

    // Test constants
    uint256 constant INITIAL_DECAY_RATE = 115740740740; // ~0.001/day in 1e18
    uint256 constant HIGH_SCORE = 1000 * 1e18;
    uint256 constant MEDIUM_SCORE = 500 * 1e18;
    uint256 constant LOW_SCORE = 100 * 1e18;
    uint256 constant REWARD_AMOUNT = 50 * 1e18;
    uint256 constant ONE_DAY = 1 days;
    uint256 constant ONE_WEEK = 7 days;
    uint256 constant ONE_MONTH = 30 days;

    event SubmissionRecorded(address indexed user);
    event RewardRecorded(address indexed user, uint256 score, uint256 reward);
    event DecayRateUpdated(uint256 oldRate, uint256 newRate);

    function setUp() public {
        _owner = address(this);
        _user1 = vm.addr(1);
        _user2 = vm.addr(2);
        _nonOwner = vm.addr(3);

        _reputation = new StoaReputation();

        console.log("Setup completed. Owner address:", _owner);
        console.log("User1 address:", _user1);
        console.log("User2 address:", _user2);
        console.log("NonOwner address:", _nonOwner);
    }

    // ============ Initial State Tests ============

    function testInitialState() public {
        console.log("Testing initial contract state");

        assertEq(_reputation.owner(), _owner, "Owner should be set correctly");
        assertEq(_reputation.decayRate(), INITIAL_DECAY_RATE, "Initial decay rate should be set");

        // Check initial user reputation data
        (uint256 submissions, uint256 wins, uint256 totalRewards) = _reputation.rep(_user1);
        assertEq(submissions, 0, "Initial submissions should be 0");
        assertEq(wins, 0, "Initial wins should be 0");
        assertEq(totalRewards, 0, "Initial total rewards should be 0");

        assertEq(_reputation.getEffectiveScore(_user1), 0, "Initial effective score should be 0");
    }

    // ============ Ownership and Access Control Tests ============

    function testOnlyOwnerCanRecordSubmission() public {
        console.log("Testing submission recording access control");

        // Owner should be able to record submission
        _reputation.recordSubmission(_user1);
        (uint256 submissions,,) = _reputation.rep(_user1);
        assertEq(submissions, 1, "Owner should be able to record submission");

        // Non-owner should not be able to record submission
        vm.startPrank(_nonOwner);
        vm.expectRevert();
        _reputation.recordSubmission(_user1);
        vm.stopPrank();
    }

    function testOnlyOwnerCanRecordReward() public {
        console.log("Testing reward recording access control");

        // Owner should be able to record reward
        _reputation.recordReward(_user1, HIGH_SCORE, REWARD_AMOUNT);
        (, uint256 wins, uint256 totalRewards) = _reputation.rep(_user1);
        assertEq(wins, 1, "Owner should be able to record wins");
        assertEq(totalRewards, REWARD_AMOUNT, "Owner should be able to record rewards");

        // Non-owner should not be able to record reward
        vm.startPrank(_nonOwner);
        vm.expectRevert();
        _reputation.recordReward(_user1, HIGH_SCORE, REWARD_AMOUNT);
        vm.stopPrank();
    }

    function testOnlyOwnerCanSetDecayRate() public {
        console.log("Testing decay rate setting access control");

        uint256 newDecayRate = 200000000000; // ~0.002/day

        // Owner should be able to set decay rate
        _reputation.setDecayRate(newDecayRate);
        assertEq(_reputation.decayRate(), newDecayRate, "Owner should be able to set decay rate");

        // Non-owner should not be able to set decay rate
        vm.startPrank(_nonOwner);
        vm.expectRevert();
        _reputation.setDecayRate(newDecayRate);
        vm.stopPrank();
    }

    // ============ Submission Recording Tests ============

    function testRecordSubmission() public {
        console.log("Testing submission recording");

        // Record multiple submissions for user1
        _reputation.recordSubmission(_user1);
        _reputation.recordSubmission(_user1);
        _reputation.recordSubmission(_user1);

        (uint256 submissions,,) = _reputation.rep(_user1);
        assertEq(submissions, 3, "Should record correct number of submissions");

        // Record submission for user2
        _reputation.recordSubmission(_user2);
        (uint256 user2Submissions,,) = _reputation.rep(_user2);
        assertEq(user2Submissions, 1, "Should record submission for different user");
    }

    function testSubmissionEvent() public {
        console.log("Testing submission event emission");

        vm.expectEmit(true, false, false, false);
        emit SubmissionRecorded(_user1);
        _reputation.recordSubmission(_user1);
    }

    function testFuzzRecordSubmission(uint8 submissionCount) public {
        console.log("Fuzz testing submission recording with count:", submissionCount);

        for (uint256 i = 0; i < submissionCount; i++) {
            _reputation.recordSubmission(_user1);
        }

        (uint256 submissions,,) = _reputation.rep(_user1);
        assertEq(submissions, submissionCount, "Should record correct fuzzed submission count");
    }

    // ============ Reward Recording Tests ============

    function testRecordReward() public {
        console.log("Testing reward recording");

        _reputation.recordReward(_user1, HIGH_SCORE, REWARD_AMOUNT);

        (uint256 submissions, uint256 wins, uint256 totalRewards) = _reputation.rep(_user1);
        assertEq(wins, 1, "Should increment wins count");
        assertEq(totalRewards, REWARD_AMOUNT, "Should add to total rewards");

        // Test multiple rewards
        _reputation.recordReward(_user1, MEDIUM_SCORE, REWARD_AMOUNT * 2);
        (submissions, wins, totalRewards) = _reputation.rep(_user1);
        assertEq(wins, 2, "Should increment wins count again");
        assertEq(totalRewards, REWARD_AMOUNT * 3, "Should accumulate total rewards");
    }

    function testRewardEvent() public {
        console.log("Testing reward event emission");

        vm.expectEmit(true, false, false, true);
        emit RewardRecorded(_user1, HIGH_SCORE, REWARD_AMOUNT);
        _reputation.recordReward(_user1, HIGH_SCORE, REWARD_AMOUNT);
    }

    function testFuzzRecordReward(uint256 score, uint256 reward) public {
        // Bound inputs to reasonable ranges
        score = bound(score, 1, 10000 * 1e18);
        reward = bound(reward, 1, 1000 * 1e18);

        console.log("Fuzz testing reward recording with score:", score, "reward:", reward);

        _reputation.recordReward(_user1, score, reward);

        (, uint256 wins, uint256 totalRewards) = _reputation.rep(_user1);
        assertEq(wins, 1, "Should record win");
        assertEq(totalRewards, reward, "Should record correct reward amount");
    }

    // ============ Decay Rate Management Tests ============

    function testSetDecayRate() public {
        console.log("Testing decay rate setting");

        uint256 newDecayRate = 200000000000; // ~0.002/day

        _reputation.setDecayRate(newDecayRate);

        assertEq(_reputation.decayRate(), newDecayRate, "Should update decay rate");
    }

    function testSetDecayRateEvent() public {
        console.log("Testing decay rate event emission");

        uint256 newDecayRate = 200000000000;
        uint256 oldRate = _reputation.decayRate();

        vm.expectEmit(false, false, false, true);
        emit DecayRateUpdated(oldRate, newDecayRate);
        _reputation.setDecayRate(newDecayRate);
    }

    function testSetDecayRateValidation() public {
        console.log("Testing decay rate validation");

        // Should revert for zero decay rate
        vm.expectRevert("StoaReputation: decay rate must be greater than zero");
        _reputation.setDecayRate(0);

        // Should revert for decay rate too high
        vm.expectRevert("StoaReputation: decay rate too high");
        _reputation.setDecayRate(1e15 + 1);

        // Should accept maximum valid rate
        _reputation.setDecayRate(1e15);
        assertEq(_reputation.decayRate(), 1e15, "Should accept maximum valid rate");
    }

    function testFuzzSetDecayRate(uint256 decayRate) public {
        decayRate = bound(decayRate, 1, 1e15);

        console.log("Fuzz testing decay rate setting:", decayRate);

        _reputation.setDecayRate(decayRate);
        assertEq(_reputation.decayRate(), decayRate, "Should set fuzzed decay rate");
    }

    // ============ Effective Score Calculation Tests ============

    function testGetEffectiveScoreNoDecay() public {
        console.log("Testing effective score calculation without time passage");

        _reputation.recordReward(_user1, HIGH_SCORE, REWARD_AMOUNT);

        // Immediately after recording, effective score should equal the recorded score
        uint256 effectiveScore = _reputation.getEffectiveScore(_user1);
        assertEq(effectiveScore, HIGH_SCORE, "Effective score should equal recorded score immediately");
    }

    function testGetEffectiveScoreWithDecay() public {
        console.log("Testing effective score calculation with time-based decay");

        // Record initial reward
        _reputation.recordReward(_user1, HIGH_SCORE, REWARD_AMOUNT);

        // Fast forward time by one day
        vm.warp(block.timestamp + ONE_DAY);

        uint256 effectiveScore = _reputation.getEffectiveScore(_user1);

        // Score should be less than original due to decay
        assertLt(effectiveScore, HIGH_SCORE, "Effective score should decay over time");
        assertGt(effectiveScore, 0, "Effective score should still be positive");

        console.log("Original score:", HIGH_SCORE);
        console.log("Effective score after 1 day:", effectiveScore);
    }

    function testGetEffectiveScoreMultipleEntries() public {
        console.log("Testing effective score with multiple score entries");

        // Record first reward
        _reputation.recordReward(_user1, HIGH_SCORE, REWARD_AMOUNT);

        // Fast forward and record second reward
        vm.warp(block.timestamp + ONE_DAY);
        _reputation.recordReward(_user1, MEDIUM_SCORE, REWARD_AMOUNT);

        // Fast forward again
        vm.warp(block.timestamp + ONE_DAY);

        uint256 effectiveScore = _reputation.getEffectiveScore(_user1);

        // Should be combination of both scores with appropriate decay
        assertGt(effectiveScore, 0, "Should have positive effective score");
        console.log("Effective score with multiple entries:", effectiveScore);
    }

    function testGetEffectiveScoreLongTimeDecay() public {
        console.log("Testing effective score after extended time period");

        _reputation.recordReward(_user1, HIGH_SCORE, REWARD_AMOUNT);

        // Fast forward by a month
        vm.warp(block.timestamp + ONE_MONTH);

        uint256 effectiveScore = _reputation.getEffectiveScore(_user1);

        // Score should be decayed but still positive
        // With decay rate of ~0.001/day over 30 days, expect around 97% retention
        assertLt(effectiveScore, HIGH_SCORE, "Score should be decayed from original");
        assertGt(effectiveScore, HIGH_SCORE / 2, "Score should not be too heavily decayed");
        assertGt(effectiveScore, 0, "Score should still be positive");

        console.log("Original score:", HIGH_SCORE);
        console.log("Effective score after 1 month:", effectiveScore);
        console.log("Decay percentage:", (HIGH_SCORE - effectiveScore) * 100 / HIGH_SCORE);
    }

    function testGetEffectiveScoreZeroForNoHistory() public {
        console.log("Testing effective score for user with no history");

        uint256 effectiveScore = _reputation.getEffectiveScore(_user1);
        assertEq(effectiveScore, 0, "Should return 0 for user with no score history");
    }

    function testFuzzGetEffectiveScoreTimeDecay(uint32 timeElapsed) public {
        // Bound time to reasonable range (up to 1 year)
        timeElapsed = uint32(bound(timeElapsed, 0, 365 days));

        console.log("Fuzz testing effective score decay over time:", timeElapsed, "seconds");

        _reputation.recordReward(_user1, HIGH_SCORE, REWARD_AMOUNT);

        vm.warp(block.timestamp + timeElapsed);

        uint256 effectiveScore = _reputation.getEffectiveScore(_user1);

        if (timeElapsed == 0) {
            assertEq(effectiveScore, HIGH_SCORE, "No decay for zero time");
        } else {
            assertLe(effectiveScore, HIGH_SCORE, "Score should decay or stay same");
            assertGe(effectiveScore, 0, "Score should never be negative");
        }
    }

    // ============ Integration Tests ============

    function testCompleteUserJourney() public {
        console.log("Testing complete user reputation journey");

        // User starts with submissions
        _reputation.recordSubmission(_user1);
        _reputation.recordSubmission(_user1);
        _reputation.recordSubmission(_user1);

        // User gets first reward
        _reputation.recordReward(_user1, HIGH_SCORE, REWARD_AMOUNT);

        // Time passes
        vm.warp(block.timestamp + ONE_WEEK);

        // User gets another reward
        _reputation.recordReward(_user1, MEDIUM_SCORE, REWARD_AMOUNT * 2);

        // More time passes
        vm.warp(block.timestamp + ONE_WEEK);

        // Check final state
        (uint256 submissions, uint256 wins, uint256 totalRewards) = _reputation.rep(_user1);
        assertEq(submissions, 3, "Should have 3 submissions");
        assertEq(wins, 2, "Should have 2 wins");
        assertEq(totalRewards, REWARD_AMOUNT * 3, "Should have correct total rewards");

        uint256 effectiveScore = _reputation.getEffectiveScore(_user1);
        assertGt(effectiveScore, 0, "Should have positive effective score");

        console.log("Final submissions:", submissions);
        console.log("Final wins:", wins);
        console.log("Final total rewards:", totalRewards);
        console.log("Final effective score:", effectiveScore);
    }

    function testMultipleUsersScenario() public {
        console.log("Testing multiple users scenario");

        // User1 activity
        _reputation.recordSubmission(_user1);
        _reputation.recordReward(_user1, HIGH_SCORE, REWARD_AMOUNT);

        // User2 activity
        _reputation.recordSubmission(_user2);
        _reputation.recordSubmission(_user2);
        _reputation.recordReward(_user2, MEDIUM_SCORE, REWARD_AMOUNT * 2);

        // Time passes
        vm.warp(block.timestamp + ONE_DAY);

        // Check both users
        uint256 user1Score = _reputation.getEffectiveScore(_user1);
        uint256 user2Score = _reputation.getEffectiveScore(_user2);

        assertGt(user1Score, 0, "User1 should have positive score");
        assertGt(user2Score, 0, "User2 should have positive score");

        // User1 had higher original score, should still be higher after decay
        assertGt(user1Score, user2Score, "User1 should have higher effective score");

        console.log("User1 effective score:", user1Score);
        console.log("User2 effective score:", user2Score);
    }

    // ============ Edge Cases and Error Conditions ============

    function testScoreHistoryGrowth() public {
        console.log("Testing score history array growth");

        // Add multiple rewards to test array growth
        for (uint256 i = 0; i < 10; i++) {
            _reputation.recordReward(_user1, HIGH_SCORE + i * 1e18, REWARD_AMOUNT);
            vm.warp(block.timestamp + 1 hours); // Small time increments
        }

        uint256 effectiveScore = _reputation.getEffectiveScore(_user1);
        assertGt(effectiveScore, HIGH_SCORE, "Should accumulate multiple scores");

        (, uint256 wins,) = _reputation.rep(_user1);
        assertEq(wins, 10, "Should have 10 wins recorded");
    }

    function testZeroScoreReward() public {
        console.log("Testing zero score reward recording");

        _reputation.recordReward(_user1, 0, REWARD_AMOUNT);

        (, uint256 wins, uint256 totalRewards) = _reputation.rep(_user1);
        assertEq(wins, 1, "Should record win even with zero score");
        assertEq(totalRewards, REWARD_AMOUNT, "Should record reward amount");

        uint256 effectiveScore = _reputation.getEffectiveScore(_user1);
        assertEq(effectiveScore, 0, "Effective score should be 0 for zero score entry");
    }

    function testZeroRewardAmount() public {
        console.log("Testing zero reward amount");

        _reputation.recordReward(_user1, HIGH_SCORE, 0);

        (, uint256 wins, uint256 totalRewards) = _reputation.rep(_user1);
        assertEq(wins, 1, "Should record win");
        assertEq(totalRewards, 0, "Should record zero reward");

        uint256 effectiveScore = _reputation.getEffectiveScore(_user1);
        assertEq(effectiveScore, HIGH_SCORE, "Should still calculate score correctly");
    }

    function testMaxValues() public {
        console.log("Testing maximum value handling");

        uint256 maxScore = type(uint256).max / 1e18; // Avoid overflow in calculations
        uint256 maxReward = type(uint256).max / 2;

        _reputation.recordReward(_user1, maxScore, maxReward);

        (, uint256 wins, uint256 totalRewards) = _reputation.rep(_user1);
        assertEq(wins, 1, "Should handle max values");
        assertEq(totalRewards, maxReward, "Should record max reward");
    }

    // ============ Gas Optimization Tests ============

    function testGasEfficiencyMultipleScores() public {
        console.log("Testing gas efficiency with multiple score entries");

        // Add 5 score entries
        for (uint256 i = 0; i < 5; i++) {
            _reputation.recordReward(_user1, HIGH_SCORE, REWARD_AMOUNT);
            vm.warp(block.timestamp + ONE_DAY);
        }

        uint256 gasBefore = gasleft();
        uint256 effectiveScore = _reputation.getEffectiveScore(_user1);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for 5 score entries:", gasUsed);
        assertGt(effectiveScore, 0, "Should calculate score");

        // Add 5 more entries
        for (uint256 i = 0; i < 5; i++) {
            _reputation.recordReward(_user1, HIGH_SCORE, REWARD_AMOUNT);
            vm.warp(block.timestamp + ONE_DAY);
        }

        gasBefore = gasleft();
        effectiveScore = _reputation.getEffectiveScore(_user1);
        uint256 gasUsed10 = gasBefore - gasleft();

        console.log("Gas used for 10 score entries:", gasUsed10);
        assertGt(effectiveScore, 0, "Should calculate score");

        // Gas should scale roughly linearly
        assertLt(gasUsed10, gasUsed * 3, "Gas should scale reasonably with entries");
    }
}
