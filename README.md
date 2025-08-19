# Stoa Protocol

A decentralized Q&A platform where users can ask questions, provide answers, and earn rewards based on the quality of their contributions. The protocol features a reputation system, creator economy incentives, and fair reward distribution.

## Architecture

The Stoa Protocol consists of three main smart contracts:

- **StoaProtocol**: Main protocol registry for question management  
- **StoaQuestionFactory**: Factory for creating and managing individual questions
- **StoaQuestion**: Individual question contracts with answer submission and reward distribution

### Key Features

- **Public Question Creation**: Anyone can create questions (no access restrictions)
- **Single Token Economy**: Simplified architecture using one ERC20 token for fees and rewards
- **Creator Incentives**: Question creators earn configurable percentage of submission fees
- **Fair Reward Distribution**: Rewards distributed proportionally based on answer quality scores
- **Emergency Recovery**: Users can claim refunds if evaluations are delayed beyond deadline
- **Gas Optimized**: Cached scoring system for efficient reward calculations

## Quick Start

1. Install Foundry:
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

2. Build the project:
```bash
forge build
```

3. Run tests:
```bash
forge test
```

## Deployment

The Stoa Protocol is deployed on **Base Mainnet** with the following addresses:

| Contract | Address | Basescan |
|----------|---------|----------|
| **StoaProtocol** | `0x28848AfD006aC2A1E571eba5079Ea6C6EC3504FB` | [View](https://basescan.org/address/0x28848afd006ac2a1e571eba5079ea6c6ec3504fb) |
| **StoaQuestionFactory** | `0x79e343Ab7144d0A2cE9e6515281BF13691797FC0` | [View](https://basescan.org/address/0x79e343ab7144d0a2ce9e6515281bf13691797fc0) |

### Deploy Your Own Instance

To deploy the Stoa Protocol to a new network, follow these steps in order:

#### Prerequisites
Set up your environment variables:
```bash
export DEPLOYER_PRIVATE_KEY="0x..."
export BASE_RPC_URL="https://api.developer.coinbase.com/rpc/v1/base/YOUR_API_KEY"
export BASESCAN_API_KEY="YOUR_BASESCAN_API_KEY"
```

#### Step 1: Deploy StoaProtocol
```bash
forge script script/DeployStoaProtocol.s.sol \
  --fork-url $BASE_RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $BASESCAN_API_KEY
```

#### Step 2: Update and Deploy StoaQuestionFactory
1. Update the contract addresses in `script/DeployStoaQuestionFactory.s.sol`:
```solidity
address constant PROTOCOL_REGISTRY = 0x...; // Address from Step 1
```

2. Deploy the factory:
```bash
forge script script/DeployStoaQuestionFactory.s.sol \
  --fork-url $BASE_RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $BASESCAN_API_KEY
```

For detailed deployment instructions, see [DEPLOYMENT.md](./DEPLOYMENT.md).

## Usage

### Creating a Question

Anyone can create a question by calling the factory contract:

```solidity
// Create a new question
questionFactory.createQuestion(
    tokenAddress,      // ERC20 token for fees/rewards
    submissionCost,    // Cost to submit an answer
    duration,          // Question duration in seconds
    maxWinners,        // Maximum number of winners
    evaluatorAddress   // Address that can evaluate answers
);
```

### Fee Structure

The protocol uses a dual-fee system:
- **Protocol Fee**: Default 10% (1000 basis points) - goes to treasury
- **Creator Fee**: Default 10% (1000 basis points) - goes to question creator
- **Reward Pool**: Remaining 80% - distributed to answer providers based on scores

Example: For a 10 token submission cost:
- 1 token → Protocol treasury
- 1 token → Question creator  
- 8 tokens → Added to reward pool

### Answer Lifecycle

1. **Submission**: Users pay submission cost to provide answers
2. **Evaluation**: Evaluator ranks answers after question deadline
3. **Reward Distribution**: Winners claim rewards proportional to their scores
4. **Emergency Refund**: Users can claim refunds if evaluation is delayed >7 days

## Testing

Run the full test suite:
```bash
forge test -vvv
```

Generate gas reports:
```bash
forge snapshot
```

Generate coverage reports:
```bash
forge coverage
```

## Documentation

- [DEPLOYMENT.md](./DEPLOYMENT.md) - Comprehensive deployment guide
- [Architecture Overview](./src/) - Smart contract documentation
