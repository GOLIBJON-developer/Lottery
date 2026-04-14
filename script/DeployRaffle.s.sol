// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {Raffle} from "../src/Raffle.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {VRFCoordinatorV2_5MockWrapper} from "../test/mocks/VRFCoordinatorV2_5Mock.sol";
/**
 * @dev Minimal interface for Chainlink VRF Coordinator v2.5 subscription mgmt.
 *      We avoid importing IVRFCoordinatorV2Plus because it does NOT include
 *      createSubscription() — that function lives only on the concrete
 *      VRFCoordinatorV2_5 contract, not in the shared interface.
 */
interface IVRFAddConsumer {
    function addConsumer(uint256 subId, address consumer) external;
}

interface IERC677 {
    function transferAndCall(address to, uint256 value, bytes calldata data)
        external returns (bool);
}

/**
 * @title  DeployRaffle
 * @notice Single-command deploy.
 *         Sepolia: creates VRF subscription → funds it with LINK
 *                  → deploys Raffle → adds as consumer (one broadcast).
 *         Anvil:   uses mock coordinator already set up by HelperConfig.
 *
 * ── Sepolia prerequisites ─────────────────────────────────────────
 *  1. Wallet holds SepoliaETH (gas) + LINK (subscription funding).
 *     Get testnet LINK at https://faucets.chain.link
 *  2. Run:
 *     forge script script/DeployRaffle.s.sol \
 *         --rpc-url $SEPOLIA_RPC_URL \
 *         --account <keystore-name> \
 *         --broadcast --verify \
 *         --etherscan-api-key $ETHERSCAN_API_KEY -vvvv
 * ─────────────────────────────────────────────────────────────────
 */
contract DeployRaffle is Script {

    address private constant LINK_SEPOLIA  = 0x779877A7B0D9E8603169DdbD7836e478b4624789;
    uint256 private constant LINK_FUND_AMT = 3 ether; // 3 LINK

    function run() external returns (Raffle raffle, HelperConfig helperConfig) {
        helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory cfg = helperConfig.getConfig();

        if (block.chainid == 31337) {
            raffle = _deployAnvil(cfg);
        } else {
            raffle = _deploySepolia(cfg);
        }

        _log(raffle, cfg);
        return (raffle, helperConfig);
    }

    /* ── Anvil ────────────────────────────────────────────────── */
    function _deployAnvil(
        HelperConfig.NetworkConfig memory cfg
    ) private returns (Raffle raffle) {
        // HelperConfig already created + funded the mock subscription.
        vm.startBroadcast();

        raffle = new Raffle(
            cfg.subscriptionId,
            cfg.gasLane,
            cfg.interval,
            cfg.entranceFee,
            cfg.callbackGasLimit,
            cfg.vrfCoordinatorV2,
            cfg.treasury,
            cfg.protocolFeeBps
        );

        // Register as VRF consumer on the mock
        VRFCoordinatorV2_5MockWrapper(cfg.vrfCoordinatorV2)
            .addConsumer(cfg.subscriptionId, address(raffle));

        vm.stopBroadcast();
    }

    /* ── Sepolia ────────────────────────────────────────────────
       WHY --skip-simulation is REQUIRED:
       createSubscription() returns a different subId on every call.
       Foundry runs the script twice: (1) locally to collect txs,
       (2) on a fork to simulate them. In run (2) a NEW subId is
       generated but the transferAndCall calldata still contains the
       subId from run (1) → InvalidSubscription() in simulation.
       --skip-simulation skips run (2) and broadcasts run (1) directly.

       KEY INSIGHT: each operation is its own vm.startBroadcast /
       vm.stopBroadcast block. This guarantees Foundry sends the
       transactions in strict nonce order (1→2→3→4). A single
       broadcast block can silently reorder txs — which caused
       transferAndCall to land before createSubscription, making
       the subscription unknown and reverting.

       The subId is kept in a local Solidity variable between
       broadcasts, so it stays consistent across all four calls.
    ────────────────────────────────────────────────────────────── */
     function _deploySepolia(
        HelperConfig.NetworkConfig memory cfg
    ) private returns (Raffle raffle) {

         // subId is read from .env — a FIXED constant, not a return value.
        // This is what makes it safe: same value in local exec and on-chain.
        uint256 subId = cfg.subscriptionId;
        require(subId != 0,
            "SUBSCRIPTION_ID missing from .env. Run CreateSubscription.s.sol first.");

        // ── Tx 1: Fund subscription with LINK ──────────────────
        // subId is a fixed constant here, so calldata is deterministic.
        vm.startBroadcast();
        IERC677(LINK_SEPOLIA).transferAndCall(
            cfg.vrfCoordinatorV2,
            LINK_FUND_AMT,
            abi.encode(subId)
        );
        vm.stopBroadcast();
        console.log("[1/3] Subscription funded with 3 LINK. SubId:", subId);

        // ── Tx 2: Deploy Raffle ────────────────────────────────
        vm.startBroadcast();
        raffle = new Raffle(
            subId,
            cfg.gasLane,
            cfg.interval,
            cfg.entranceFee,
            cfg.callbackGasLimit,
            cfg.vrfCoordinatorV2,
            cfg.treasury,
            cfg.protocolFeeBps
        );
        vm.stopBroadcast();
        console.log("[2/3] Raffle deployed:", address(raffle));

        // ── Tx 3: Add Raffle as VRF consumer ───────────────────
        vm.startBroadcast();
        IVRFAddConsumer(cfg.vrfCoordinatorV2)
            .addConsumer(subId, address(raffle));
        vm.stopBroadcast();
        console.log("[3/3] Raffle added as consumer. Done.");
    }

    function _log(
        Raffle raffle,
        HelperConfig.NetworkConfig memory cfg
    ) private view {
        console.log("=== Raffle deployed ===");
        console.log("Address     :", address(raffle));
        console.log("Network     :", block.chainid);
        console.log("SubId       :", cfg.subscriptionId);
        console.log("EntranceFee :", cfg.entranceFee, "wei");
        console.log("Interval    :", cfg.interval, "seconds");
        console.log("Treasury    :", cfg.treasury);
        console.log("ProtocolFee :", cfg.protocolFeeBps, "bps");
    }
}
