// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/StoaQuestionFactory.sol";

contract CreateQuestionScript is Script {
    function run() public {
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        
        StoaQuestionFactory factory = StoaQuestionFactory(0x56Ee1dAb5b0CB673D25C4893FBE8253b08112658);
        
        address questionAddress = factory.createQuestion(
            0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913, // USDC token
            0,                                             // No submission cost  
            86400,                                         // 1 day duration
            1,                                             // 1 max winner
            0                                              // No seed amount
        );
        
        console.log("Question created at:", questionAddress);
        
        vm.stopBroadcast();
    }
}