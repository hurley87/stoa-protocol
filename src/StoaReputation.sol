// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts/access/Ownable.sol";
import "solady/utils/FixedPointMathLib.sol";

contract StoaReputation is Ownable {
    struct ScoreEntry {
        uint256 score;
        uint256 timestamp;
    }

    struct RepData {
        uint256 submissions;
        uint256 wins;
        uint256 totalRewards;
        ScoreEntry[] scoreHistory;
    }

    mapping(address => RepData) public rep;
    mapping(address => bool) public authorizedCallers;
    uint256 public decayRate = 115740740740; // ~0.001/day in 1e18

    event SubmissionRecorded(address indexed user);
    event RewardRecorded(address indexed user, uint256 score, uint256 reward);
    event DecayRateUpdated(uint256 oldRate, uint256 newRate);
    event AuthorizedCallerUpdated(address indexed caller, bool authorized);

    modifier onlyAuthorized() {
        require(authorizedCallers[msg.sender] || owner() == msg.sender, "Not authorized");
        _;
    }

    constructor() Ownable() {}

    function setAuthorizedCaller(address caller, bool authorized) external onlyOwner {
        authorizedCallers[caller] = authorized;
        emit AuthorizedCallerUpdated(caller, authorized);
    }

    function recordSubmission(address user) external onlyAuthorized {
        rep[user].submissions += 1;
        emit SubmissionRecorded(user);
    }

    function recordReward(address user, uint256 score, uint256 rewardAmount) external onlyAuthorized {
        rep[user].wins += 1;
        rep[user].totalRewards += rewardAmount;
        rep[user].scoreHistory.push(ScoreEntry(score, block.timestamp));
        emit RewardRecorded(user, score, rewardAmount);
    }

    /**
     * @notice Allows the owner to update the decay rate for reputation scores
     * @dev The decay rate is used in exponential decay calculations and should be scaled by 1e18
     * @param newDecayRate The new decay rate (scaled by 1e18)
     */
    function setDecayRate(uint256 newDecayRate) external onlyOwner {
        require(newDecayRate > 0, "StoaReputation: decay rate must be greater than zero");
        require(newDecayRate <= 1e15, "StoaReputation: decay rate too high");

        uint256 oldRate = decayRate;
        decayRate = newDecayRate;

        emit DecayRateUpdated(oldRate, newDecayRate);
    }

    function getEffectiveScore(address user) public view returns (uint256 effectiveScore) {
        ScoreEntry[] memory history = rep[user].scoreHistory;
        for (uint256 i = 0; i < history.length; i++) {
            uint256 delta = block.timestamp - history[i].timestamp;
            int256 exponent = -int256(decayRate * delta);
            uint256 decayFactor = uint256(FixedPointMathLib.expWad(exponent));
            effectiveScore += (history[i].score * decayFactor) / 1e18;
        }
    }
}
