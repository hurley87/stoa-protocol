// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/StoaReputation.sol";

/**
 * @title DeployStoaReputationScript
 * @notice This script deploys the StoaReputation contract.
 * @dev Simulate running it by entering:
 *      `forge script script/DeployStoaReputation.s.sol --sender <the_caller_address> --fork-url $RPC_URL -vvvv`
 *      To deploy for real, add the --broadcast flag:
 *      `forge script script/DeployStoaReputation.s.sol --fork-url $RPC_URL --broadcast --verify`
 */
contract DeployStoaReputationScript is Script {
    function run() public {
        vm.broadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        StoaReputation reputation = new StoaReputation();

        console.log("StoaReputation deployed at:", address(reputation));
        console.log("Initial decay rate:", reputation.decayRate());
        console.log("Owner:", reputation.owner());
    }
}
