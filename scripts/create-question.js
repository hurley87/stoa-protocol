#!/usr/bin/env node

// Load environment variables
require('dotenv').config();

/**
 * Example script to create a question on-chain and sync with Supabase
 * 
 * Usage:
 * node create-question-example.js
 * 
 * Environment variables required:
 * - PRIVATE_KEY: Deployer private key
 * - BASE_RPC_URL: Base network RPC URL
 * - SUPABASE_URL: Your Supabase project URL
 * - SUPABASE_SERVICE_KEY: Supabase service role key
 * - TOKEN_ADDRESS: ERC20 token contract address
 */

const { createWalletClient, createPublicClient, http, parseUnits, formatUnits, decodeEventLog } = require('viem');
const { privateKeyToAccount } = require('viem/accounts');
const { base } = require('viem/chains');
const { createClient } = require('@supabase/supabase-js');

// Contract addresses (update with your deployed contracts)
const FACTORY_ADDRESS = '0x4C8c62Dcb1eBCC2A19963b64Ba02ee3132ce9F48';

// Contract ABI (minimal - add full ABI in production)
const FACTORY_ABI = [
  {
    "inputs": [
      {"internalType": "address", "name": "token", "type": "address"},
      {"internalType": "uint256", "name": "submissionCost", "type": "uint256"},
      {"internalType": "uint256", "name": "duration", "type": "uint256"},
      {"internalType": "uint8", "name": "maxWinners", "type": "uint8"},
      {"internalType": "uint256", "name": "seedAmount", "type": "uint256"}
    ],
    "name": "createQuestion",
    "outputs": [{"internalType": "address", "name": "", "type": "address"}],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "questionCount",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "anonymous": false,
    "inputs": [
      {"indexed": true, "internalType": "uint256", "name": "questionId", "type": "uint256"},
      {"indexed": true, "internalType": "address", "name": "question", "type": "address"},
      {"indexed": true, "internalType": "address", "name": "creator", "type": "address"},
      {"indexed": false, "internalType": "address", "name": "token", "type": "address"},
      {"indexed": false, "internalType": "uint256", "name": "submissionCost", "type": "uint256"},
      {"indexed": false, "internalType": "uint256", "name": "duration", "type": "uint256"},
      {"indexed": false, "internalType": "uint8", "name": "maxWinners", "type": "uint8"},
      {"indexed": false, "internalType": "uint256", "name": "seedAmount", "type": "uint256"}
    ],
    "name": "QuestionCreated",
    "type": "event"
  }
];

// Configuration
const config = {
  // Question content (off-chain)
  questionContent: "Will crypto go mainstream in the next year? What specific events or developments would drive mass adoption?",
  
  // Question parameters (on-chain)
  tokenAddress: process.env.TOKEN_ADDRESS || '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913', // USDC on Base
  submissionCost: parseUnits('1', 6), // 1 USDC (6 decimals)
  duration: 7 * 24 * 60 * 60, // 7 days in seconds
  maxWinners: 3,
  evaluatorAddress: process.env.EVALUATOR_ADDRESS || '0xBe523e724B9Ea7D618dD093f14618D90c4B19b0c',
  
  // Network
  rpcUrl: process.env.BASE_RPC_URL,
  privateKey: process.env.DEPLOYER_PRIVATE_KEY,
  
  // Supabase
  supabaseUrl: process.env.SUPABASE_URL,
  supabaseKey: process.env.SUPABASE_SERVICE_KEY
};

async function createQuestion() {
  try {
    console.log('🚀 Creating question on-chain and syncing with Supabase...\n');

    // 1. Setup blockchain connection
    console.log('1️⃣ Setting up blockchain connection...');
    const account = privateKeyToAccount(config.privateKey);
    
    const publicClient = createPublicClient({
      chain: base,
      transport: http(config.rpcUrl)
    });

    const walletClient = createWalletClient({
      account,
      chain: base,
      transport: http(config.rpcUrl)
    });
    
    console.log(`   Wallet: ${account.address}`);
    console.log(`   Factory: ${FACTORY_ADDRESS}\n`);

    // 2. Setup Supabase connection
    console.log('2️⃣ Setting up Supabase connection...');
    const supabase = createClient(config.supabaseUrl, config.supabaseKey);
    console.log(`   Supabase URL: ${config.supabaseUrl}\n`);

    // 3. Get current question count (for question_id)
    console.log('3️⃣ Getting current question count...');
    const questionCount = await publicClient.readContract({
      address: FACTORY_ADDRESS,
      abi: FACTORY_ABI,
      functionName: 'questionCount'
    });
    const questionId = questionCount; // Next question ID
    console.log(`   Next question ID: ${questionId}\n`);

    // 4. Create question on-chain
    console.log('4️⃣ Creating question on-chain...');
    console.log(`   Token: ${config.tokenAddress}`);
    console.log(`   Submission Cost: ${formatUnits(config.submissionCost, 6)} USDC`);
    console.log(`   Duration: ${config.duration / (24 * 60 * 60)} days`);
    console.log(`   Max Winners: ${config.maxWinners}`);
    console.log(`   Evaluator: ${config.evaluatorAddress}`);
    console.log(`   Args:`, [
      config.tokenAddress,
      config.submissionCost.toString(),
      config.duration,
      config.maxWinners,
      0 // seedAmount
    ]);

    console.log('   Attempting direct contract call...');
    const txHash = await walletClient.writeContract({
      address: FACTORY_ADDRESS,
      abi: FACTORY_ABI,
      functionName: 'createQuestion',
      args: [
        config.tokenAddress,
        config.submissionCost,
        BigInt(config.duration),
        config.maxWinners,
        0n // seedAmount - no initial seeding
      ]
    });
    console.log(`   Transaction hash: ${txHash}`);
    console.log('   Waiting for confirmation...');

    // Wait for transaction confirmation
    const receipt = await publicClient.waitForTransactionReceipt({ 
      hash: txHash 
    });
    console.log(`   ✅ Confirmed in block ${receipt.blockNumber}\n`);

    // 5. Parse the QuestionCreated event to get contract address
    console.log('5️⃣ Parsing QuestionCreated event...');
    const questionCreatedLog = receipt.logs.find(log => 
      log.address.toLowerCase() === FACTORY_ADDRESS.toLowerCase()
    );

    if (!questionCreatedLog) {
      throw new Error('QuestionCreated event not found in transaction logs');
    }

    // Decode the event log
    const decodedLog = decodeEventLog({
      abi: FACTORY_ABI,
      data: questionCreatedLog.data,
      topics: questionCreatedLog.topics
    });

    const questionContractAddress = decodedLog.args.question;
    console.log(`   Question contract deployed at: ${questionContractAddress}\n`);

    // 6. Get question details from event data
    console.log('6️⃣ Using question details from event...');
    
    const creator = decodedLog.args.creator;
    const token = decodedLog.args.token;
    const submissionCost = decodedLog.args.submissionCost;
    const duration = decodedLog.args.duration;
    const maxWinners = decodedLog.args.maxWinners;
    const evaluator = config.evaluatorAddress;

    const startTime = new Date();
    const endTime = new Date(startTime.getTime() + Number(duration) * 1000);
    const evaluationDeadline = new Date(endTime.getTime() + 7 * 24 * 60 * 60 * 1000);

    console.log(`   Creator: ${creator}`);
    console.log(`   Start time: ${startTime.toISOString()}`);
    console.log(`   End time: ${endTime.toISOString()}`);
    console.log(`   Evaluation deadline: ${evaluationDeadline.toISOString()}\n`);

    // 7. Insert question into Supabase
    console.log('7️⃣ Saving question to Supabase...');
    
    // First, ensure user exists
    const { error: userError } = await supabase
      .from('users')
      .upsert({
        wallet: creator.toLowerCase(),
        joined_at: new Date().toISOString()
      }, {
        onConflict: 'wallet',
        ignoreDuplicates: true
      });

    if (userError) {
      console.warn(`   Warning: Could not upsert user: ${userError.message}`);
    }

    // Insert question
    const { data: questionData, error: questionError } = await supabase
      .from('questions')
      .insert({
        question_id: Number(questionId),
        contract_address: questionContractAddress.toLowerCase(),
        creator: creator.toLowerCase(),
        content: config.questionContent,
        token_address: token.toLowerCase(),
        submission_cost: submissionCost.toString(),
        max_winners: Number(maxWinners),
        duration: Number(duration),
        evaluator: evaluator.toLowerCase(),
        start_time: startTime.toISOString(),
        end_time: endTime.toISOString(),
        evaluation_deadline: evaluationDeadline.toISOString(),
        seeded_amount: '0',
        total_reward_pool: '0',
        total_submissions: 0,
        protocol_fees_collected: '0',
        creator_fees_collected: '0',
        status: 'active',
        creation_tx_hash: txHash
      })
      .select()
      .single();

    if (questionError) {
      throw new Error(`Failed to save question to Supabase: ${questionError.message}`);
    }

    console.log(`   ✅ Question saved to Supabase with ID: ${questionData.id}\n`);

    // 8. Save contract event for audit trail
    console.log('8️⃣ Saving contract event...');
    const { error: eventError } = await supabase
      .from('contract_events')
      .insert({
        contract_address: FACTORY_ADDRESS.toLowerCase(),
        event_name: 'QuestionCreated',
        block_number: Number(receipt.blockNumber),
        tx_hash: txHash,
        event_data: {
          questionId: Number(questionId),
          creator: creator.toLowerCase(),
          questionContract: questionContractAddress.toLowerCase(),
          token: token.toLowerCase(),
          submissionCost: submissionCost.toString(),
          duration: Number(duration),
          maxWinners: Number(maxWinners),
          evaluator: evaluator.toLowerCase()
        },
        processed: true
      });

    if (eventError) {
      console.warn(`   Warning: Could not save event: ${eventError.message}`);
    } else {
      console.log(`   ✅ Contract event saved\n`);
    }

    // 9. Summary
    console.log('🎉 Question created successfully!');
    console.log('═══════════════════════════════════════');
    console.log(`Question ID: ${questionId}`);
    console.log(`Contract Address: ${questionContractAddress}`);
    console.log(`Transaction: https://basescan.org/tx/${txHash}`);
    console.log(`Creator: ${creator}`);
    console.log(`Submission Cost: ${formatUnits(submissionCost, 6)} USDC`);
    console.log(`Duration: ${Number(duration) / (24 * 60 * 60)} days`);
    console.log(`Ends At: ${endTime.toLocaleString()}`);
    console.log(`Evaluation Deadline: ${evaluationDeadline.toLocaleString()}`);
    console.log('═══════════════════════════════════════');

    return {
      questionId: Number(questionId),
      contractAddress: questionContractAddress,
      txHash,
      supabaseId: questionData.id
    };

  } catch (error) {
    console.error('❌ Error creating question:', error.message);
    console.error(error);
    process.exit(1);
  }
}

// Helper function to validate environment
function validateEnvironment() {
  const required = ['BASE_RPC_URL', 'PRIVATE_KEY', 'SUPABASE_URL', 'SUPABASE_SERVICE_KEY'];
  const missing = required.filter(env => !process.env[env]);
  
  if (missing.length > 0) {
    console.error('❌ Missing required environment variables:');
    missing.forEach(env => console.error(`   - ${env}`));
    console.error('\nSet them in your .env file or export them:');
    console.error('export BASE_RPC_URL="https://api.developer.coinbase.com/rpc/v1/base/YOUR_KEY"');
    console.error('export PRIVATE_KEY="0x..."');
    console.error('export SUPABASE_URL="https://your-project.supabase.co"');
    console.error('export SUPABASE_SERVICE_KEY="your-service-key"');
    process.exit(1);
  }
}

// Package.json dependencies needed:
console.log(`
📦 Install required dependencies:
npm install viem @supabase/supabase-js

🔧 Environment variables needed:
export BASE_RPC_URL="https://api.developer.coinbase.com/rpc/v1/base/YOUR_KEY"
export PRIVATE_KEY="0x..."
export SUPABASE_URL="https://your-project.supabase.co"
export SUPABASE_SERVICE_KEY="your-service-key"
export TOKEN_ADDRESS="0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913" # USDC on Base
export EVALUATOR_ADDRESS="0xBe523e724B9Ea7D618dD093f14618D90c4B19b0c"
`);

// Run the script
if (require.main === module) {
  validateEnvironment();
  createQuestion();
}

module.exports = { createQuestion };