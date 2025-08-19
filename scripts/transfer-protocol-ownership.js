#!/usr/bin/env node

require('dotenv').config();

const { createWalletClient, createPublicClient, http } = require('viem');
const { privateKeyToAccount } = require('viem/accounts');
const { base } = require('viem/chains');

// Contract addresses
const PROTOCOL_ADDRESS = '0xa5786e202bba72503C14637C5279F15Af335AFCF';
const FACTORY_ADDRESS = '0x0b792fCfc7518a81981890FfEBbA8864937EcD89';

const OWNABLE_ABI = [
  {
    "inputs": [{"internalType": "address", "name": "newOwner", "type": "address"}],
    "name": "transferOwnership",
    "outputs": [],
    "stateMutability": "nonpayable",
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

async function transferOwnership() {
  try {
    console.log('🔄 Transferring StoaProtocol ownership to StoaQuestionFactory...\n');

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

    // Check current owner
    const currentOwner = await publicClient.readContract({
      address: PROTOCOL_ADDRESS,
      abi: OWNABLE_ABI,
      functionName: 'owner'
    });

    console.log(`Current StoaProtocol owner: ${currentOwner}`);
    console.log(`Our wallet: ${account.address}`);
    console.log(`New owner (Factory): ${FACTORY_ADDRESS}\n`);

    if (currentOwner !== account.address) {
      throw new Error('You are not the current owner of the protocol contract');
    }

    // Transfer ownership
    console.log('📝 Transferring ownership...');
    const txHash = await walletClient.writeContract({
      address: PROTOCOL_ADDRESS,
      abi: OWNABLE_ABI,
      functionName: 'transferOwnership',
      args: [FACTORY_ADDRESS]
    });

    console.log(`Transaction hash: ${txHash}`);
    console.log('Waiting for confirmation...');

    const receipt = await publicClient.waitForTransactionReceipt({ 
      hash: txHash 
    });
    console.log(`✅ Confirmed in block ${receipt.blockNumber}\n`);

    // Verify new owner
    const newOwner = await publicClient.readContract({
      address: PROTOCOL_ADDRESS,
      abi: OWNABLE_ABI,
      functionName: 'owner'
    });

    console.log('🎉 Ownership transfer completed!');
    console.log('═══════════════════════════════════════');
    console.log(`StoaProtocol: ${PROTOCOL_ADDRESS}`);
    console.log(`New Owner: ${newOwner}`);
    console.log(`Factory: ${FACTORY_ADDRESS}`);
    console.log(`Match: ${newOwner === FACTORY_ADDRESS ? '✅' : '❌'}`);
    console.log(`Transaction: https://basescan.org/tx/${txHash}`);
    console.log('═══════════════════════════════════════');

  } catch (error) {
    console.error('❌ Error transferring ownership:', error.message);
    process.exit(1);
  }
}

if (require.main === module) {
  transferOwnership();
}