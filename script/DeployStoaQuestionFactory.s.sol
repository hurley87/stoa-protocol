// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/StoaQuestionFactory.sol";

/**
 * @title DeployStoaQuestionFactoryScript
 * @notice This script deploys the StoaQuestionFactory contract with the specified parameters.
 * @dev Simulate running it by entering:
 *      `forge script script/DeployStoaQuestionFactory.s.sol --sender <the_caller_address> --fork-url $RPC_URL -vvvv`
 *      To deploy for real, add the --broadcast flag:
 *      `forge script script/DeployStoaQuestionFactory.s.sol --fork-url $RPC_URL --broadcast --verify`
 */
contract DeployStoaQuestionFactoryScript is Script {
    // Contract addresses
    address constant EVALUATOR = 0xBe523e724B9Ea7D618dD093f14618D90c4B19b0c;
    address constant TREASURY = 0xbD78783a26252bAf756e22f0DE764dfDcDa7733c;
    address constant PROTOCOL_REGISTRY = 0x50e68d23a211d01E68C9812c9fcb1B84C94dc02B;

    function run() public {
        vm.broadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        StoaQuestionFactory questionFactory = new StoaQuestionFactory(EVALUATOR, TREASURY, PROTOCOL_REGISTRY);

        console.log("StoaQuestionFactory deployed at:", address(questionFactory));
        console.log("Evaluator:", questionFactory.evaluator());
        console.log("Treasury:", questionFactory.treasury());
        console.log("Protocol Registry:", address(questionFactory.protocolRegistry()));
        console.log("Owner:", questionFactory.owner());
        console.log("Question Count:", questionFactory.questionCount());
    }
}
