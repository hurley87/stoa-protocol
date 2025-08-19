// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/StoaProtocol.sol";

/**
 * @title DeployStoaProtocolScript
 * @notice This script deploys the StoaProtocol contract.
 * @dev Simulate running it by entering:
 *      `forge script script/DeployStoaProtocol.s.sol --sender <the_caller_address> --fork-url $RPC_URL -vvvv`
 *      To deploy for real, add the --broadcast flag:
 *      `forge script script/DeployStoaProtocol.s.sol --fork-url $RPC_URL --broadcast --verify`
 */
contract DeployStoaProtocolScript is Script {
    function run() public {
        vm.broadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        StoaProtocol protocol = new StoaProtocol();

        console.log("StoaProtocol deployed at:", address(protocol));
        console.log("Owner:", protocol.owner());
        console.log("Question count:", protocol.getQuestionCount());
    }
}
