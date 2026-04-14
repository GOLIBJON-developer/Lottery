// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

interface IVRFCreateSub {
    function createSubscription() external returns (uint256 subId);
}

/**
 * @title  CreateSubscription
 * @notice Step 1 of 2-step Sepolia deploy.
 *         Creates a VRF subscription and prints its ID.
 *
 * Usage:
 *   forge script script/CreateSubscription.s.sol \
 *       --rpc-url $SEPOLIA_RPC_URL \
 *       --account <keystore> \
 *       --broadcast --slow -vvvv
 *
 * After running, copy the printed subId into .env:
 *   SUBSCRIPTION_ID=<subId>
 *
 * Then run DeployRaffle.s.sol (Step 2).
 */
contract CreateSubscription is Script {
    function run() external returns (uint256 subId) {
        HelperConfig helperConfig = new HelperConfig();
        address coordinator = helperConfig.getConfig().vrfCoordinatorV2;

        vm.startBroadcast();
        subId = IVRFCreateSub(coordinator).createSubscription();
        vm.stopBroadcast();

        console.log("=========================================");
        console.log("VRF Subscription created!");
        console.log("SubId:", subId);
        console.log("-----------------------------------------");
        console.log("ACTION REQUIRED:");
        console.log("Add this line to your .env file:");
        console.log("SUBSCRIPTION_ID=", subId);
        console.log("=========================================");
    }
}
