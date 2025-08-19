# Stoa Protocol Deployment Guide

## Overview

The Stoa Protocol consists of three main contracts that need to be deployed in a specific order due to their dependencies. This guide provides step-by-step instructions for deploying the entire protocol.

## Contract Architecture

1. **StoaReputation** - Reputation tracking system (standalone)
2. **StoaProtocol** - Main protocol registry (standalone)  
3. **StoaQuestionFactory** - Question creation factory (depends on StoaReputation and StoaProtocol)

## Prerequisites

- Forge/Foundry installed
- Private key for deployment wallet set as `DEPLOYER_PRIVATE_KEY` environment variable
- RPC URL for target network set as `RPC_URL` environment variable
- Sufficient ETH/native tokens for gas fees
- ERC20 token addresses for the protocol (if using existing tokens)

## Deployment Order

### Step 1: Deploy StoaReputation

The reputation system is independent and should be deployed first.

```bash
# Simulate deployment (recommended first)
forge script script/DeployStoaReputation.s.sol --fork-url $RPC_URL -vvvv

# Deploy for real
forge script script/DeployStoaReputation.s.sol --fork-url $RPC_URL --broadcast --verify
```

**Expected Output:**
- Contract address for StoaReputation
- Initial decay rate (should be 9500)
- Owner address (deployer)

**Save the StoaReputation address** - you'll need it for Step 3.

### Step 2: Deploy StoaProtocol

The main protocol registry is also independent.

```bash
# Simulate deployment
forge script script/DeployStoaProtocol.s.sol --fork-url $RPC_URL -vvvv

# Deploy for real
forge script script/DeployStoaProtocol.s.sol --fork-url $RPC_URL --broadcast --verify
```

**Expected Output:**
- Contract address for StoaProtocol
- Owner address (deployer)
- Initial question count (should be 0)

**Save the StoaProtocol address** - you'll need it for Step 3.

### Step 3: Deploy StoaQuestionFactory

The factory depends on both previous contracts and requires updating the script with their addresses.

1. **Update the deployment script** with the addresses from Steps 1 and 2:

```solidity
// In script/DeployStoaQuestionFactory.s.sol
address constant REPUTATION = 0x...; // Address from Step 1
address constant PROTOCOL_REGISTRY = 0x...; // Address from Step 2
```

2. **Deploy the factory:**

```bash
# Simulate deployment
forge script script/DeployStoaQuestionFactory.s.sol --fork-url $RPC_URL -vvvv

# Deploy for real
forge script script/DeployStoaQuestionFactory.s.sol --fork-url $RPC_URL --broadcast --verify
```

**Expected Output:**
- Contract address for StoaQuestionFactory
- Evaluator address
- Treasury address  
- Reputation contract address
- Protocol registry address
- Owner address (deployer)
- Initial question count (should be 0)

## Post-Deployment Configuration

### Required Actions

1. **Set up reputation system ownership:**
   ```bash
   # Transfer StoaReputation ownership to StoaQuestionFactory if questions should manage reputation
   cast send $REPUTATION_ADDRESS "transferOwnership(address)" $QUESTION_FACTORY_ADDRESS --private-key $DEPLOYER_PRIVATE_KEY --rpc-url $RPC_URL
   ```

2. **Configure fees (optional):**
   ```bash
   # Update protocol fee (default is 10%)
   cast send $QUESTION_FACTORY_ADDRESS "setFeeBps(uint256)" 500 --private-key $DEPLOYER_PRIVATE_KEY --rpc-url $RPC_URL
   
   # Update creator fee (default is 10%)
   cast send $QUESTION_FACTORY_ADDRESS "setCreatorFeeBps(uint256)" 500 --private-key $DEPLOYER_PRIVATE_KEY --rpc-url $RPC_URL
   ```

3. **Update treasury address (if needed):**
   ```bash
   cast send $QUESTION_FACTORY_ADDRESS "setTreasury(address)" $NEW_TREASURY_ADDRESS --private-key $DEPLOYER_PRIVATE_KEY --rpc-url $RPC_URL
   ```

### Verification Steps

After deployment, verify the setup:

1. **Check question creation works:**
   ```bash
   # Anyone should be able to create questions (no onlyOwner restriction)
   cast send $QUESTION_FACTORY_ADDRESS "createQuestion(address,uint256,uint256,uint8,address)" $TOKEN_ADDRESS $SUBMISSION_COST $DURATION $MAX_WINNERS $EVALUATOR_ADDRESS --private-key $USER_PRIVATE_KEY --rpc-url $RPC_URL
   ```

2. **Verify fee configuration:**
   ```bash
   cast call $QUESTION_FACTORY_ADDRESS "feeBps()" --rpc-url $RPC_URL
   cast call $QUESTION_FACTORY_ADDRESS "creatorFeeBps()" --rpc-url $RPC_URL
   ```

3. **Test single token architecture:**
   - Ensure questions only require one token parameter
   - Verify creator fees are paid correctly
   - Confirm protocol fees go to treasury

## Environment Variables Reference

```bash
# Required
export DEPLOYER_PRIVATE_KEY="0x..."
export RPC_URL="https://..."

# Contract addresses (update during deployment)
export REPUTATION_ADDRESS="0x..."
export PROTOCOL_ADDRESS="0x..."
export FACTORY_ADDRESS="0x..."

# Configuration addresses (update as needed)
export EVALUATOR_ADDRESS="0x..."
export TREASURY_ADDRESS="0x..."
```

## Common Issues

### Script Address Mismatches
- Always update hardcoded addresses in `DeployStoaQuestionFactory.s.sol`
- Verify addresses are correct before broadcasting

### Gas Estimation Failures
- Ensure deployer wallet has sufficient native tokens
- Check network congestion and adjust gas price if needed

### Verification Failures
- Ensure contract source matches deployed bytecode
- Check that all constructor parameters are correct
- Verify network supports contract verification

## Security Considerations

1. **Access Control:**
   - Question creation is public (anyone can create)
   - Only evaluators can evaluate specific questions
   - Only contract owners can modify fees and treasury

2. **Fee Structure:**
   - Protocol fees go to treasury
   - Creator fees go to question creators
   - Remaining funds form the reward pool

3. **Emergency Features:**
   - Users can claim emergency refunds if evaluation deadline passes
   - 7-day grace period for evaluations after question ends

## Contract Addresses Template

After successful deployment, record your addresses:

```
Network: [NETWORK_NAME]
StoaReputation: 0x...
StoaProtocol: 0x...
StoaQuestionFactory: 0x...
Deployment Block: [BLOCK_NUMBER]
Deployer: 0x...
```