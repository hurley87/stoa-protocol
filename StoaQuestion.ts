export const StoaQuestionABI = [
  // Constructor
  {
    "inputs": [
      {"internalType": "address", "name": "_token", "type": "address"},
      {"internalType": "uint256", "name": "_submissionCost", "type": "uint256"},
      {"internalType": "uint256", "name": "_duration", "type": "uint256"},
      {"internalType": "uint8", "name": "_maxWinners", "type": "uint8"},
      {"internalType": "address", "name": "_evaluator", "type": "address"},
      {"internalType": "address", "name": "_treasury", "type": "address"},
    ],
    "stateMutability": "nonpayable",
    "type": "constructor"
  },

  // Core Functions
  {
    "inputs": [{"internalType": "bytes32", "name": "answerHash", "type": "bytes32"}],
    "name": "submitAnswer",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [
      {"internalType": "address", "name": "user", "type": "address"},
      {"internalType": "bytes32", "name": "answerHash", "type": "bytes32"}
    ],
    "name": "submitAnswerFor",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [{"internalType": "uint256", "name": "amount", "type": "uint256"}],
    "name": "seedQuestion",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [{"internalType": "uint256[]", "name": "rankedIndices", "type": "uint256[]"}],
    "name": "evaluateAnswers",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "claimReward",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "emergencyRefund",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },

  // Admin Functions
  {
    "inputs": [
      {"internalType": "address", "name": "submitter", "type": "address"},
      {"internalType": "bool", "name": "allowed", "type": "bool"}
    ],
    "name": "setSubmitter",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },

  // View Functions
  {
    "inputs": [],
    "name": "token",
    "outputs": [{"internalType": "contract IERC20", "name": "", "type": "address"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "evaluator",
    "outputs": [{"internalType": "address", "name": "", "type": "address"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "submissionCost",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "totalRewardPool",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "endsAt",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "evaluationDeadline",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "maxWinners",
    "outputs": [{"internalType": "uint8", "name": "", "type": "uint8"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "creator",
    "outputs": [{"internalType": "address", "name": "", "type": "address"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "evaluated",
    "outputs": [{"internalType": "bool", "name": "", "type": "bool"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "owner",
    "outputs": [{"internalType": "address", "name": "", "type": "address"}],
    "stateMutability": "view",
    "type": "function"
  },

  // Mappings and Arrays
  {
    "inputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "name": "answers",
    "outputs": [
      {"internalType": "address", "name": "responder", "type": "address"},
      {"internalType": "bytes32", "name": "answerHash", "type": "bytes32"},
      {"internalType": "uint256", "name": "timestamp", "type": "uint256"},
      {"internalType": "uint256", "name": "score", "type": "uint256"},
      {"internalType": "bool", "name": "rewarded", "type": "bool"}
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [{"internalType": "address", "name": "", "type": "address"}],
    "name": "userAnswerIndex",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [{"internalType": "address", "name": "", "type": "address"}],
    "name": "isAuthorizedSubmitter",
    "outputs": [{"internalType": "bool", "name": "", "type": "bool"}],
    "stateMutability": "view",
    "type": "function"
  },

  // Helper Functions
  {
    "inputs": [{"internalType": "uint256", "name": "index", "type": "uint256"}],
    "name": "getAnswer",
    "outputs": [
      {
        "components": [
          {"internalType": "address", "name": "responder", "type": "address"},
          {"internalType": "bytes32", "name": "answerHash", "type": "bytes32"},
          {"internalType": "uint256", "name": "timestamp", "type": "uint256"},
          {"internalType": "uint256", "name": "score", "type": "uint256"},
          {"internalType": "bool", "name": "rewarded", "type": "bool"}
        ],
        "internalType": "struct StoaQuestion.Answer",
        "name": "",
        "type": "tuple"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "getAllAnswers",
    "outputs": [
      {
        "components": [
          {"internalType": "address", "name": "responder", "type": "address"},
          {"internalType": "bytes32", "name": "answerHash", "type": "bytes32"},
          {"internalType": "uint256", "name": "timestamp", "type": "uint256"},
          {"internalType": "uint256", "name": "score", "type": "uint256"},
          {"internalType": "bool", "name": "rewarded", "type": "bool"}
        ],
        "internalType": "struct StoaQuestion.Answer[]",
        "name": "",
        "type": "tuple[]"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [{"internalType": "address", "name": "user", "type": "address"}],
    "name": "getUserAnswer",
    "outputs": [
      {
        "components": [
          {"internalType": "address", "name": "responder", "type": "address"},
          {"internalType": "bytes32", "name": "answerHash", "type": "bytes32"},
          {"internalType": "uint256", "name": "timestamp", "type": "uint256"},
          {"internalType": "uint256", "name": "score", "type": "uint256"},
          {"internalType": "bool", "name": "rewarded", "type": "bool"}
        ],
        "internalType": "struct StoaQuestion.Answer",
        "name": "",
        "type": "tuple"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "getTotalRewardValue",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "totalScore",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  },

  // Events
  {
    "anonymous": false,
    "inputs": [
      {"indexed": true, "internalType": "address", "name": "responder", "type": "address"},
      {"indexed": false, "internalType": "uint256", "name": "index", "type": "uint256"}
    ],
    "name": "AnswerSubmitted",
    "type": "event"
  },
  {
    "anonymous": false,
    "inputs": [
      {"indexed": false, "internalType": "uint256[]", "name": "rankedAnswerIndices", "type": "uint256[]"}
    ],
    "name": "Evaluated",
    "type": "event"
  },
  {
    "anonymous": false,
    "inputs": [
      {"indexed": true, "internalType": "address", "name": "user", "type": "address"},
      {"indexed": false, "internalType": "uint256", "name": "amount", "type": "uint256"}
    ],
    "name": "RewardClaimed",
    "type": "event"
  },
  {
    "anonymous": false,
    "inputs": [
      {"indexed": true, "internalType": "address", "name": "funder", "type": "address"},
      {"indexed": false, "internalType": "uint256", "name": "amount", "type": "uint256"}
    ],
    "name": "Seeded",
    "type": "event"
  },
  {
    "anonymous": false,
    "inputs": [
      {"indexed": true, "internalType": "address", "name": "previousOwner", "type": "address"},
      {"indexed": true, "internalType": "address", "name": "newOwner", "type": "address"}
    ],
    "name": "OwnershipTransferred",
    "type": "event"
  }
] as const;

export default StoaQuestionABI;