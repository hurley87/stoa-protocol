#!/usr/bin/env node

require('dotenv').config();

const { createPublicClient, http } = require('viem');
const { base } = require('viem/chains');

// Contract addresses
const FACTORY_ADDRESS = '0x0b792fCfc7518a81981890FfEBbA8864937EcD89';
const PROTOCOL_ADDRESS = '0xa5786e202bba72503C14637C5279F15Af335AFCF';

const OWNABLE_ABI = [
  {
    "inputs": [],
    "name": "owner",
    "outputs": [{"internalType": "address", "name": "", "type": "address"}],
    "stateMutability": "view",
    "type": "function"
  }
];

async function checkOwnership() {
  const publicClient = createPublicClient({
    chain: base,
    transport: http(process.env.BASE_RPC_URL)
  });

  console.log('🔍 Checking contract ownership...\n');

  // Check factory owner
  const factoryOwner = await publicClient.readContract({
    address: FACTORY_ADDRESS,
    abi: OWNABLE_ABI,
    functionName: 'owner'
  });

  // Check protocol owner  
  const protocolOwner = await publicClient.readContract({
    address: PROTOCOL_ADDRESS,
    abi: OWNABLE_ABI,
    functionName: 'owner'
  });

  console.log(`StoaQuestionFactory (${FACTORY_ADDRESS}) owner: ${factoryOwner}`);
  console.log(`StoaProtocol (${PROTOCOL_ADDRESS}) owner: ${protocolOwner}`);
  console.log(`\nOur wallet: ${process.env.PRIVATE_KEY ? '0xBe523e724B9Ea7D618dD093f14618D90c4B19b0c' : 'PRIVATE_KEY not set'}`);
  
  console.log('\n🔧 Analysis:');
  if (factoryOwner === protocolOwner) {
    console.log('✅ Both contracts have the same owner');
  } else {
    console.log('❌ Contracts have different owners');
    console.log('   The factory needs to be able to call registerQuestion on the protocol');
    console.log('   Either transfer protocol ownership to factory, or update the protocol');
  }
}

checkOwnership().catch(console.error);