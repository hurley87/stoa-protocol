#!/usr/bin/env node

// Load environment variables
require('dotenv').config();

const { createWalletClient, createPublicClient, http } = require('viem');
const { privateKeyToAccount } = require('viem/accounts');
const { base } = require('viem/chains');

// Contract addresses
const FACTORY_ADDRESS = '0x0b792fCfc7518a81981890FfEBbA8864937EcD89';

// Creator to whitelist
const CREATOR_ADDRESS = '0xBe523e724B9Ea7D618dD093f14618D90c4B19b0c';

// Contract ABI
const FACTORY_ABI = [
  {
    "inputs": [
      {"internalType": "address", "name": "user", "type": "address"},
      {"internalType": "bool", "name": "allowed", "type": "bool"}
    ],
    "name": "whitelistCreator",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [{"internalType": "address", "name": "", "type": "address"}],
    "name": "isWhitelisted",
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
  }
];

async function whitelistCreator() {
  try {
    console.log('🔐 Whitelisting creator...\n');

    // Setup blockchain connection
    const account = privateKeyToAccount(process.env.PRIVATE_KEY);
    
    const publicClient = createPublicClient({
      chain: base,
      transport: http(process.env.BASE_RPC_URL)
    });

    const walletClient = createWalletClient({
      account,
      chain: base,
      transport: http(process.env.BASE_RPC_URL)
    });
    
    console.log(`Wallet: ${account.address}`);
    console.log(`Factory: ${FACTORY_ADDRESS}`);
    console.log(`Creator to whitelist: ${CREATOR_ADDRESS}\n`);

    // Check current owner
    const owner = await publicClient.readContract({
      address: FACTORY_ADDRESS,
      abi: FACTORY_ABI,
      functionName: 'owner'
    });
    console.log(`Factory owner: ${owner}`);

    // Check if already whitelisted
    const isCurrentlyWhitelisted = await publicClient.readContract({
      address: FACTORY_ADDRESS,
      abi: FACTORY_ABI,
      functionName: 'isWhitelisted',
      args: [CREATOR_ADDRESS]
    });
    console.log(`Currently whitelisted: ${isCurrentlyWhitelisted}\n`);

    if (isCurrentlyWhitelisted) {
      console.log('✅ Creator is already whitelisted!');
      return;
    }

    // Whitelist the creator
    console.log('📝 Whitelisting creator...');
    const txHash = await walletClient.writeContract({
      address: FACTORY_ADDRESS,
      abi: FACTORY_ABI,
      functionName: 'whitelistCreator',
      args: [CREATOR_ADDRESS, true]
    });

    console.log(`Transaction hash: ${txHash}`);
    console.log('Waiting for confirmation...');

    // Wait for confirmation
    const receipt = await publicClient.waitForTransactionReceipt({ 
      hash: txHash 
    });
    console.log(`✅ Confirmed in block ${receipt.blockNumber}\n`);

    // Verify whitelist status
    const isNowWhitelisted = await publicClient.readContract({
      address: FACTORY_ADDRESS,
      abi: FACTORY_ABI,
      functionName: 'isWhitelisted',
      args: [CREATOR_ADDRESS]
    });

    console.log('🎉 Whitelist operation completed!');
    console.log('═══════════════════════════════════════');
    console.log(`Creator: ${CREATOR_ADDRESS}`);
    console.log(`Is Whitelisted: ${isNowWhitelisted}`);
    console.log(`Transaction: https://basescan.org/tx/${txHash}`);
    console.log('═══════════════════════════════════════');

  } catch (error) {
    console.error('❌ Error whitelisting creator:', error.message);
    console.error(error);
    process.exit(1);
  }
}

// Run the script
if (require.main === module) {
  whitelistCreator();
}

module.exports = { whitelistCreator };