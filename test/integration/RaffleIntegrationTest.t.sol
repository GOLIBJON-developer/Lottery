// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Raffle} from "../../src/Raffle.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {VRFCoordinatorV2_5MockWrapper} from "../mocks/VRFCoordinatorV2_5Mock.sol";

contract RaffleIntegrationTest is Test {
    Raffle                 raffle;
    HelperConfig           helperConfig;
    VRFCoordinatorV2_5MockWrapper vrfCoordinator;
    HelperConfig.NetworkConfig cfg;
    address OWNER;

    uint256 constant NUM_PLAYERS = 5;
    address[5] players;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();
        cfg            = helperConfig.getConfig();
        vrfCoordinator = VRFCoordinatorV2_5MockWrapper(cfg.vrfCoordinatorV2);
        vrfCoordinator.fundSubscription(cfg.subscriptionId, 100 ether);
        OWNER          = raffle.owner();

        for (uint256 i = 0; i < NUM_PLAYERS; i++) {
            players[i] = makeAddr(string(abi.encodePacked("player", i)));
            vm.deal(players[i], 10 ether);
        }
    }

    function _doFullDraw() internal returns (uint256 reqId) {
        vm.warp(block.timestamp + cfg.interval + 1);
        vm.roll(block.number + 1);
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic = keccak256("RequestedRaffleWinner(uint256,uint256)");
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == topic) {
                reqId = uint256(logs[i].topics[1]);
                break;
            }
        }
        vrfCoordinator.fulfillRandomWords(reqId, address(raffle));
    }

    /* ================================================================
       Full happy-path: enter → draw → winner paid directly
    ================================================================ */
    function test_Integration_FullRound_PrizePotIsolation() external {
        for (uint256 i = 0; i < NUM_PLAYERS; i++) {
            vm.prank(players[i]);
            raffle.enterRaffle{value: cfg.entranceFee}();
        }

        uint256 pot         = raffle.getCurrentRoundPot();
        uint256 expectFee   = (pot * cfg.protocolFeeBps) / 10_000;
        uint256 expectPrize = pot - expectFee;

        assertEq(pot, cfg.entranceFee * NUM_PLAYERS);

        _doFullDraw();

        address winner = raffle.getRecentWinner();
        assertNotEq(winner, address(0));

        // Pot must be zero after draw
        assertEq(raffle.getCurrentRoundPot(), 0);

        // Pure pull: winner always in s_winnings
        assertEq(raffle.getWinnings(winner),       expectPrize, "winner prize mismatch");
        assertEq(raffle.getWinnings(cfg.treasury), expectFee,   "treasury fee mismatch");

        // Winner claims
        uint256 balBefore = winner.balance;
        vm.prank(winner);
        raffle.claimWinnings();
        assertEq(winner.balance, balBefore + expectPrize);
    }

    /* ================================================================
       Pot isolation across 2 rounds — old unclaimed never bleeds in
    ================================================================ */
    function test_Integration_PotIsolation_TwoRounds() external {
        // Round 1
        for (uint256 i = 0; i < NUM_PLAYERS; i++) {
            vm.prank(players[i]);
            raffle.enterRaffle{value: cfg.entranceFee}();
        }
        uint256 pot1 = raffle.getCurrentRoundPot();
        _doFullDraw();

        // Nobody claims after round 1

        // Round 2 — same players re-enter
        for (uint256 i = 0; i < NUM_PLAYERS; i++) {
            vm.prank(players[i]);
            raffle.enterRaffle{value: cfg.entranceFee}();
        }
        uint256 pot2 = raffle.getCurrentRoundPot();

        // Pot2 must equal ONLY round2 fees, not round1 leftovers
        assertEq(pot2, cfg.entranceFee * NUM_PLAYERS, "pot2 must not include round1 funds");
        assertEq(pot1, pot2, "both rounds same # players -> same pot");

        // vrfCoordinator.fundSubscription(cfg.subscriptionId, 100 ether);

        _doFullDraw();
        assertEq(raffle.getCurrentRoundPot(), 0);
        assertEq(raffle.getTotalRoundsPlayed(), 2);
    }

    /* ================================================================
       Pause → cancel → refund → re-enter (FIX-2)
    ================================================================ */
    function test_Integration_CancelRefundReenter() external {
        for (uint256 i = 0; i < NUM_PLAYERS; i++) {
            vm.prank(players[i]);
            raffle.enterRaffle{value: cfg.entranceFee}();
        }

        vm.prank(OWNER); raffle.pause();
        vm.prank(OWNER); raffle.cancelRaffle();

        // State must be CANCELLED while paused
        assertEq(uint256(raffle.getRaffleState()), uint256(Raffle.RaffleState.CANCELLED));

        // Refunds available
        for (uint256 i = 0; i < NUM_PLAYERS; i++) {
            assertEq(raffle.getRefund(players[i]), cfg.entranceFee);
        }

        vm.prank(OWNER); raffle.unpause();

        // State must now be OPEN
        assertEq(uint256(raffle.getRaffleState()), uint256(Raffle.RaffleState.OPEN));

        // [FIX-2] All players can re-enter (hasEntered was cleared)
        for (uint256 i = 0; i < NUM_PLAYERS; i++) {
            assertFalse(raffle.hasEntered(players[i]));
            vm.prank(players[i]);
            raffle.enterRaffle{value: cfg.entranceFee}();
        }
        assertEq(raffle.getNumberOfPlayers(), NUM_PLAYERS);

        // Players can also still claim their refunds
        for (uint256 i = 0; i < NUM_PLAYERS; i++) {
            uint256 balBefore = players[i].balance;
            vm.prank(players[i]);
            raffle.claimRefund();
            assertEq(players[i].balance, balBefore + cfg.entranceFee);
        }
    }

    /* ================================================================
       Emergency withdraw only takes orphaned ETH (FIX-5)
    ================================================================ */
    function test_Integration_EmergencyWithdraw_ProtectsPendingClaims() external {
        for (uint256 i = 0; i < NUM_PLAYERS; i++) {
            vm.prank(players[i]);
            raffle.enterRaffle{value: cfg.entranceFee}();
        }
        _doFullDraw();

        uint256 pending       = raffle.getPendingClaims();
        uint256 totalBalance  = address(raffle).balance;
        uint256 orphaned      = totalBalance > pending ? totalBalance - pending : 0;

        vm.prank(OWNER); raffle.pause();

        if (orphaned > 0) {
            uint256 ownerBefore = OWNER.balance;
            vm.prank(OWNER);
            raffle.emergencyWithdraw();
            assertEq(OWNER.balance, ownerBefore + orphaned);
            // Pending claims still safe in contract
            assertEq(address(raffle).balance, pending);
        } else {
            vm.prank(OWNER);
            vm.expectRevert(Raffle.Raffle__NothingToClaim.selector);
            raffle.emergencyWithdraw();
        }
    }

    /* ================================================================
       3 consecutive rounds — pot, roundId, history correct
    ================================================================ */
    function test_Integration_ThreeRoundsInSequence() external {
        for (uint256 round = 1; round <= 3; round++) {
            for (uint256 i = 0; i < NUM_PLAYERS; i++) {
                vm.prank(players[i]);
                raffle.enterRaffle{value: cfg.entranceFee}();
            }
            assertEq(raffle.getCurrentRoundPot(), cfg.entranceFee * NUM_PLAYERS);
            _doFullDraw();
            assertEq(raffle.getCurrentRoundPot(), 0);
            assertEq(raffle.getTotalRoundsPlayed(), round);
            assertEq(raffle.getRoundResult(round).playerCount, NUM_PLAYERS);
            assertFalse(raffle.getRoundResult(round).cancelled);
        }
        assertEq(raffle.getCurrentRoundId(), 4);
        assertEq(raffle.getWinnerHistory().length, 3);
    }

    /* ================================================================
       Config update (all gated by pause — FIX-4)
    ================================================================ */
    function test_Integration_ConfigUpdate_AllRequirePause() external {
        // None should work without pause
        vm.startPrank(OWNER);
        vm.expectRevert(Raffle.Raffle__MustBePaused.selector);
        raffle.setEntranceFee(0.05 ether);

        vm.expectRevert(Raffle.Raffle__MustBePaused.selector);
        raffle.setProtocolFee(300);

        vm.expectRevert(Raffle.Raffle__MustBePaused.selector);
        raffle.setTreasury(address(0xDEAD));
        vm.stopPrank();

        // With pause — all should work
        vm.prank(OWNER); raffle.pause();
        vm.prank(OWNER); raffle.setEntranceFee(0.02 ether);
        vm.prank(OWNER); raffle.setProtocolFee(300);
        vm.prank(OWNER); raffle.setTreasury(address(0xDEAD));
        vm.prank(OWNER); raffle.unpause();

        assertEq(raffle.getEntranceFee(),    0.02 ether);
        assertEq(raffle.getProtocolFeeBps(), 300);
        assertEq(raffle.getTreasury(),       address(0xDEAD));
    }
}
