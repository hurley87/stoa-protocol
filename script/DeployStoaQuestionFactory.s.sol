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
    address constant TREASURY = 0xBe523e724B9Ea7D618dD093f14618D90c4B19b0c;
    address constant PROTOCOL_REGISTRY = 0xFB20AD3ad36b197a3e0a36CC2C8edcf09767c13f;

    function run() public {
        vm.broadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        StoaQuestionFactory questionFactory = new StoaQuestionFactory(TREASURY, PROTOCOL_REGISTRY);

        console.log("StoaQuestionFactory deployed at:", address(questionFactory));
        console.log("Treasury:", questionFactory.treasury());
        console.log("Protocol Registry:", address(questionFactory.protocolRegistry()));
        console.log("Owner:", questionFactory.owner());
        console.log("Question Count:", questionFactory.questionCount());
    }
}
