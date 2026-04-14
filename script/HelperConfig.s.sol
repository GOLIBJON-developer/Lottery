// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {VRFCoordinatorV2_5MockWrapper} from "../test/mocks/VRFCoordinatorV2_5Mock.sol";
/**
 * @title  HelperConfig
 * @notice Returns the correct network config depending on which chain we are on.
 *         Anvil (local) → deploy mocks and return their addresses.
 *         Sepolia        → return real Chainlink addresses.
 *
 * Usage in deploy scripts:
 *   HelperConfig helperConfig = new HelperConfig();
 *   HelperConfig.NetworkConfig memory cfg = helperConfig.getConfig();
 */
contract HelperConfig is Script {
    uint96 public constant MOCK_BASE_FEE = 0.25 ether;
    uint96 public constant MOCK_GAS_PRICE_LINK = 1e9;
    // LINK / ETH price
    int256 public constant MOCK_WEI_PER_UINT_LINK = 4e15;
    /* ── Types ─────────────────────────────────────────────────── */

    struct NetworkConfig {
        uint256 subscriptionId;
        bytes32 gasLane;
        uint256 interval;
        uint256 entranceFee;
        uint32  callbackGasLimit;
        address vrfCoordinatorV2;
        address treasury;
        uint256 protocolFeeBps;
        // address link
    }

    /* ── Chain IDs ─────────────────────────────────────────────── */

    uint256 public constant ANVIL_CHAIN_ID   = 31337;
    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;

    /* ── State ─────────────────────────────────────────────────── */

    NetworkConfig private s_activeConfig;
    VRFCoordinatorV2_5MockWrapper public vrfMock; // exposed for tests

    /* ── Constructor ───────────────────────────────────────────── */

    constructor() {
        if (block.chainid == SEPOLIA_CHAIN_ID) {
            s_activeConfig = _getSepoliaConfig();
        } else {
            s_activeConfig = _getOrCreateAnvilConfig();
        }
    }

    /* ── Public getter ─────────────────────────────────────────── */

    function getConfig() external view returns (NetworkConfig memory) {
        return s_activeConfig;
    }

    /* ── Sepolia ───────────────────────────────────────────────── */

    function _getSepoliaConfig() private view returns (NetworkConfig memory) {
        // Read subId from environment — must be set after running CreateSubscription
        // Returns 0 if not set (DeployRaffle will require() it to be non-zero)
        uint256 subId;
        try vm.envUint("VRF_SUBSCRIPTION_ID") returns (uint256 id) {
            subId = id;
        } catch {
            subId = 0;
        }

        address treasury;
        try vm.envAddress("TREASURY_ADDRESS") returns (address t) {
            treasury = t;
        } catch {
            treasury = msg.sender; // fallback: deployer is treasury
        }

        return NetworkConfig({
            vrfCoordinatorV2: 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B,
            gasLane:          0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
            callbackGasLimit: 500_000,
            subscriptionId:   subId,
            interval:         3_600,      // 1 hour
            entranceFee:      0.01 ether,
            treasury:         treasury,
            protocolFeeBps:   200         // 2%
        });
    }

    /* ── Anvil (local) ─────────────────────────────────────────── */

    /**
     * @dev Deploys a VRFCoordinatorV2_5MockWrapper, creates a subscription,
     *      funds it with fake LINK so tests can call requestRandomWords.
     */
    function _getOrCreateAnvilConfig() private returns (NetworkConfig memory) {
        // Already deployed in this run? Return cached config.
        if (s_activeConfig.vrfCoordinatorV2 != address(0)) {
            return s_activeConfig;
        }

        vm.startBroadcast();

        // 1. Deploy mock coordinator
        vrfMock = new VRFCoordinatorV2_5MockWrapper(
                MOCK_BASE_FEE,
                MOCK_GAS_PRICE_LINK,
                MOCK_WEI_PER_UINT_LINK
        );

        // 2. Create + fund a subscription
        uint256 subId = vrfMock.createSubscription();
        vrfMock.fundSubscription(subId, 100 ether); // fake LINK

        vm.stopBroadcast();

        return NetworkConfig({
            vrfCoordinatorV2: address(vrfMock),
            gasLane:          0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c,
            callbackGasLimit: 500_000,
            subscriptionId:   subId,
            interval:         30,         // 30 seconds — fast for local tests
            entranceFee:      0.01 ether,
            treasury:         address(0xBEEF), // test treasury
            protocolFeeBps:   200
        });
    }
}
