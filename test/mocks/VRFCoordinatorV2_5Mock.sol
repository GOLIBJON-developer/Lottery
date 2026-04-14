// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

/**
 * @notice Thin wrapper so the import path is clean in tests.
 *         All logic lives in the upstream Chainlink mock.
 *
 * Constructor args (from Chainlink docs):
 *   _baseFee          — flat fee per request  (e.g. 0.1 LINK = 1e17)
 *   _gasPriceLink     — per-gas fee in LINK    (e.g. 1e9)
 *   _weiPerUnitLink   — LINK/ETH price         (e.g. 4e15 = $0.004/LINK)
 */
contract VRFCoordinatorV2_5MockWrapper is VRFCoordinatorV2_5Mock {
    constructor(uint96 _baseFee, uint96 _gasPriceLink, int256 _weiPerUnitLink)
        VRFCoordinatorV2_5Mock(
            _baseFee,   // baseFee
            _gasPriceLink,         // gasPriceLink
            _weiPerUnitLink         // weiPerUnitLink
        )
    {}
}
