// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Raffle} from "../../src/Raffle.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {VRFCoordinatorV2_5MockWrapper} from "../mocks/VRFCoordinatorV2_5Mock.sol";

/**
 * @title  RaffleTest — complete unit test suite
 * @notice run: forge test --match-path test/unit/RaffleTest.t.sol -v
 *         gas: forge test --match-path test/unit/RaffleTest.t.sol --gas-report
 */
contract RaffleTest is Test {
    /* ── Events (mirror Raffle.sol) ─────────────────────────────── */
    event RaffleEnter(address indexed player, uint256 totalPlayers);
    event RequestedRaffleWinner(uint256 indexed requestId, uint256 indexed roundId);
    event WinnerPicked(address indexed winner, uint256 prize, uint256 timestamp, uint256 indexed roundId);
    event WinningsClaimed(address indexed winner, uint256 amount);
    event RefundClaimed(address indexed player, uint256 amount);
    event RaffleCancelled(uint256 indexed roundId, uint256 timestamp);
    event ExcessRefunded(address indexed player, uint256 amount);
    event EntranceFeeUpdated(uint256 oldFee, uint256 newFee);
    event ProtocolFeeUpdated(uint256 oldBps, uint256 newBps);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event EmergencyWithdraw(address indexed to, uint256 amount);
    event RafflePausedByOwner(address indexed by);
    event RaffleUnpausedByOwner(address indexed by);

    /* ── State ──────────────────────────────────────────────────── */
    Raffle                        public raffle;
    HelperConfig                  public helperConfig;
    VRFCoordinatorV2_5MockWrapper public vrfCoordinator;
    HelperConfig.NetworkConfig    cfg;

    address public OWNER;
    address public PLAYER   = makeAddr("player");
    address public PLAYER_2 = makeAddr("player2");
    address public PLAYER_3 = makeAddr("player3");
    uint256 public constant STARTING_BALANCE = 10 ether;

    /* ── Setup ──────────────────────────────────────────────────── */
    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();
        cfg            = helperConfig.getConfig();
        vrfCoordinator = VRFCoordinatorV2_5MockWrapper(cfg.vrfCoordinatorV2);
        OWNER          = raffle.owner();

        // Fund mock subscription with plenty of fake LINK before each test.
        // Chainlink's mock deducts LINK on every fulfillRandomWords call.
        // Without this, multi-round tests fail with InsufficientBalance().
        vrfCoordinator.fundSubscription(cfg.subscriptionId, 100 ether);

        vm.deal(PLAYER,   STARTING_BALANCE);
        vm.deal(PLAYER_2, STARTING_BALANCE);
        vm.deal(PLAYER_3, STARTING_BALANCE);
    }

    /* ── Internal helpers ───────────────────────────────────────── */

    function _enterPlayers(uint256 n) internal {
        address[3] memory named = [PLAYER, PLAYER_2, PLAYER_3];
        for (uint256 i = 0; i < n; i++) {
            address p = i < 3
                ? named[i]
                : makeAddr(string(abi.encodePacked("bulk", i)));
            vm.deal(p, STARTING_BALANCE);
            vm.prank(p);
            raffle.enterRaffle{value: cfg.entranceFee}();
        }
    }

    function _triggerDraw() internal returns (uint256 requestId) {
        vm.warp(block.timestamp + cfg.interval + 1);
        vm.roll(block.number + 1);
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic = keccak256("RequestedRaffleWinner(uint256,uint256)");
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == topic) {
                requestId = uint256(logs[i].topics[1]);
                break;
            }
        }
    }

    function _fullDraw(uint256 n) internal returns (address winner) {
        if (n > 0) _enterPlayers(n);
        uint256 reqId = _triggerDraw();
        vrfCoordinator.fulfillRandomWords(reqId, address(raffle));
        winner = raffle.getRecentWinner();
    }

    /* ================================================================
       1. CONSTRUCTOR
    ================================================================ */

    function test_Constructor_SetsStateCorrectly() external view {
        assertEq(raffle.getEntranceFee(),    cfg.entranceFee);
        assertEq(raffle.getInterval(),       cfg.interval);
        assertEq(raffle.getTreasury(),       cfg.treasury);
        assertEq(raffle.getProtocolFeeBps(), cfg.protocolFeeBps);
        assertEq(raffle.getCurrentRoundId(), 1);
        assertEq(raffle.getCurrentRoundPot(), 0);
        assertEq(raffle.getPendingClaims(),  0);
        assertEq(uint256(raffle.getRaffleState()), uint256(Raffle.RaffleState.OPEN));
    }

    function test_Constructor_RevertsIfTreasuryZero() external {
        vm.expectRevert(Raffle.Raffle__InvalidTreasury.selector);
        new Raffle(cfg.subscriptionId, cfg.gasLane, cfg.interval,
            cfg.entranceFee, cfg.callbackGasLimit, cfg.vrfCoordinatorV2,
            address(0), cfg.protocolFeeBps);
    }

    function test_Constructor_RevertsIfBpsTooHigh() external {
        vm.expectRevert(Raffle.Raffle__InvalidBPS.selector);
        new Raffle(cfg.subscriptionId, cfg.gasLane, cfg.interval,
            cfg.entranceFee, cfg.callbackGasLimit, cfg.vrfCoordinatorV2,
            cfg.treasury, 1_001);
    }

    function test_Constructor_RevertsIfEntranceFeeTooLow() external {
        vm.expectRevert(Raffle.Raffle__FeeTooLow.selector);
        new Raffle(cfg.subscriptionId, cfg.gasLane, cfg.interval,
            0, cfg.callbackGasLimit, cfg.vrfCoordinatorV2,
            cfg.treasury, cfg.protocolFeeBps);
    }

    function test_Constructor_SetsOwnerCorrectly() external view {
        // Owner must be a real address (not zero)
        assertTrue(OWNER != address(0));
        assertEq(raffle.owner(), OWNER);
    }

    /* ================================================================
       2. ENTER RAFFLE
    ================================================================ */

    function test_EnterRaffle_AddsPlayer() external {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: cfg.entranceFee}();
        assertEq(raffle.getNumberOfPlayers(), 1);
        assertEq(raffle.getPlayer(0), PLAYER);
    }

    function test_EnterRaffle_SetsHasEntered() external {
        assertFalse(raffle.hasEntered(PLAYER));
        vm.prank(PLAYER);
        raffle.enterRaffle{value: cfg.entranceFee}();
        assertTrue(raffle.hasEntered(PLAYER));
    }

    function test_EnterRaffle_UpdatesRoundPot() external {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: cfg.entranceFee}();
        assertEq(raffle.getCurrentRoundPot(), cfg.entranceFee);
    }

    function test_EnterRaffle_PotGrowsWithEachPlayer() external {
        _enterPlayers(3);
        assertEq(raffle.getCurrentRoundPot(), cfg.entranceFee * 3);
    }

    function test_EnterRaffle_EmitsEvent() external {
        vm.expectEmit(true, false, false, true);
        emit RaffleEnter(PLAYER, 1);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: cfg.entranceFee}();
    }

    function test_EnterRaffle_RefundsExcessETH() external {
        uint256 excess = 0.05 ether;
        vm.deal(PLAYER, cfg.entranceFee + excess);

        vm.expectEmit(true, false, false, true);
        emit ExcessRefunded(PLAYER, excess);

        vm.prank(PLAYER);
        raffle.enterRaffle{value: cfg.entranceFee + excess}();

        assertEq(PLAYER.balance,              excess,            "only fee deducted");
        assertEq(raffle.getCurrentRoundPot(), cfg.entranceFee,   "pot = fee only");
    }

    function test_EnterRaffle_RevertsIfNotEnoughFee() external {
        vm.prank(PLAYER);
        vm.expectRevert(Raffle.Raffle__SendMoreToEnterRaffle.selector);
        raffle.enterRaffle{value: cfg.entranceFee - 1}();
    }

    function test_EnterRaffle_RevertsIfCalculating() external {
        _enterPlayers(2);
        _triggerDraw(); // state → CALCULATING
        vm.prank(PLAYER_3);
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        raffle.enterRaffle{value: cfg.entranceFee}();
    }

    function test_EnterRaffle_RevertsIfPaused() external {
        vm.prank(OWNER); raffle.pause();
        vm.prank(PLAYER);
        vm.expectRevert();
        raffle.enterRaffle{value: cfg.entranceFee}();
    }

    function test_EnterRaffle_RevertsIfDuplicate() external {
        vm.startPrank(PLAYER);
        raffle.enterRaffle{value: cfg.entranceFee}();
        vm.expectRevert(Raffle.Raffle__AlreadyEntered.selector);
        raffle.enterRaffle{value: cfg.entranceFee}();
        vm.stopPrank();
    }

    function test_EnterRaffle_RevertsIfMaxPlayers() external {
        // Fill up to MAX_PLAYERS
        for (uint256 i = 0; i < raffle.MAX_PLAYERS(); i++) {
            address p = makeAddr(string(abi.encodePacked("max", i)));
            vm.deal(p, cfg.entranceFee);
            vm.prank(p);
            raffle.enterRaffle{value: cfg.entranceFee}();
        }
        address overflow = makeAddr("overflow");
        vm.deal(overflow, cfg.entranceFee);
        vm.prank(overflow);
        vm.expectRevert(Raffle.Raffle__MaxPlayersReached.selector);
        raffle.enterRaffle{value: cfg.entranceFee}();
    }

    /* ================================================================
       3. CHECKUPKEEP
    ================================================================ */

    function test_CheckUpkeep_ReturnsFalseIfNoPot() external {
        vm.warp(block.timestamp + cfg.interval + 1);
        (bool needed,) = raffle.checkUpkeep("");
        assertFalse(needed);
    }

    function test_CheckUpkeep_ReturnsFalseIfNotEnoughTime() external {
        _enterPlayers(2);
        (bool needed,) = raffle.checkUpkeep("");
        assertFalse(needed);
    }

    function test_CheckUpkeep_ReturnsFalseIfPaused() external {
        _enterPlayers(2);
        vm.prank(OWNER); raffle.pause();
        vm.warp(block.timestamp + cfg.interval + 1);
        (bool needed,) = raffle.checkUpkeep("");
        assertFalse(needed);
    }

    function test_CheckUpkeep_ReturnsFalseWithOnePlayer() external {
        _enterPlayers(1); // below MIN_PLAYERS
        vm.warp(block.timestamp + cfg.interval + 1);
        (bool needed,) = raffle.checkUpkeep("");
        assertFalse(needed);
    }

    function test_CheckUpkeep_ReturnsFalseIfCalculating() external {
        _enterPlayers(2);
        _triggerDraw(); // state = CALCULATING
        (bool needed,) = raffle.checkUpkeep("");
        assertFalse(needed);
    }

    function test_CheckUpkeep_ReturnsTrueWhenAllConditionsMet() external {
        _enterPlayers(2);
        vm.warp(block.timestamp + cfg.interval + 1);
        (bool needed,) = raffle.checkUpkeep("");
        assertTrue(needed);
    }

    function test_CheckUpkeep_ReturnsFalseRightAtInterval() external {
        // Exactly at interval (not past it) should be false
        _enterPlayers(2);
        vm.warp(block.timestamp + cfg.interval); // = not >
        (bool needed,) = raffle.checkUpkeep("");
        assertFalse(needed);
    }

    /* ================================================================
       4. PERFORM UPKEEP
    ================================================================ */

    function test_PerformUpkeep_SetsCalculatingState() external {
        _enterPlayers(2);
        vm.warp(block.timestamp + cfg.interval + 1);
        raffle.performUpkeep("");
        assertEq(uint256(raffle.getRaffleState()), uint256(Raffle.RaffleState.CALCULATING));
    }

    function test_PerformUpkeep_EmitsRequestEvent() external {
        _enterPlayers(2);
        vm.warp(block.timestamp + cfg.interval + 1);
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic = keccak256("RequestedRaffleWinner(uint256,uint256)");
        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == topic) found = true;
        }
        assertTrue(found, "RequestedRaffleWinner event must be emitted");
    }

    function test_PerformUpkeep_RevertsIfUpkeepNotNeeded() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                raffle.getCurrentRoundPot(),
                raffle.getNumberOfPlayers(),
                uint256(raffle.getRaffleState())
            )
        );
        raffle.performUpkeep("");
    }

    function test_PerformUpkeep_CanBeCalledByAnyone() external {
        // performUpkeep has no access control — Chainlink calls it
        _enterPlayers(2);
        vm.warp(block.timestamp + cfg.interval + 1);
        vm.prank(PLAYER); // non-owner
        raffle.performUpkeep(""); // must not revert
    }

    /* ================================================================
       5. FULFILL RANDOM WORDS
    ================================================================ */

    function test_FulfillRandomWords_ResetsPotToZero() external {
        _enterPlayers(2);
        uint256 reqId = _triggerDraw();
        vrfCoordinator.fulfillRandomWords(reqId, address(raffle));
        assertEq(raffle.getCurrentRoundPot(), 0);
    }

    function test_FulfillRandomWords_ResetsPlayersArray() external {
        _enterPlayers(3);
        uint256 reqId = _triggerDraw();
        vrfCoordinator.fulfillRandomWords(reqId, address(raffle));
        assertEq(raffle.getNumberOfPlayers(), 0);
    }

    function test_FulfillRandomWords_ResetsHasEntered() external {
        _enterPlayers(2);
        assertTrue(raffle.hasEntered(PLAYER));
        uint256 reqId = _triggerDraw();
        vrfCoordinator.fulfillRandomWords(reqId, address(raffle));
        assertFalse(raffle.hasEntered(PLAYER));
    }

    function test_FulfillRandomWords_ResetsStateToOpen() external {
        _enterPlayers(2);
        uint256 reqId = _triggerDraw();
        vrfCoordinator.fulfillRandomWords(reqId, address(raffle));
        assertEq(uint256(raffle.getRaffleState()), uint256(Raffle.RaffleState.OPEN));
    }

    function test_FulfillRandomWords_IncrementsRoundId() external {
        assertEq(raffle.getCurrentRoundId(), 1);
        _fullDraw(2);
        assertEq(raffle.getCurrentRoundId(), 2);
    }

    function test_FulfillRandomWords_AddsToWinnerHistory() external {
        assertEq(raffle.getWinnerHistory().length, 0);
        _fullDraw(2);
        assertEq(raffle.getWinnerHistory().length, 1);
        assertEq(raffle.getTotalRoundsPlayed(), 1);
    }

    function test_FulfillRandomWords_WinnerIsOneOfPlayers() external {
        _enterPlayers(3);
        uint256 reqId = _triggerDraw();
        vrfCoordinator.fulfillRandomWords(reqId, address(raffle));
        address winner = raffle.getRecentWinner();
        bool isPlayer = winner == PLAYER || winner == PLAYER_2 || winner == PLAYER_3;
        assertTrue(isPlayer, "winner must be one of the entered players");
    }

    function test_FulfillRandomWords_WinnerAlwaysInSWinnings() external {
        address winner = _fullDraw(2);
        uint256 fee    = (cfg.entranceFee * 2 * cfg.protocolFeeBps) / 10_000;
        uint256 prize  = cfg.entranceFee * 2 - fee;
        assertEq(raffle.getWinnings(winner),       prize, "winner s_winnings mismatch");
        assertEq(raffle.getWinnings(cfg.treasury), fee,   "treasury fee mismatch");
    }

    function test_FulfillRandomWords_PendingClaimsCorrect() external {
        _fullDraw(2);
        uint256 pot     = cfg.entranceFee * 2;
        uint256 fee     = (pot * cfg.protocolFeeBps) / 10_000;
        uint256 prize   = pot - fee;
        // pendingClaims = winner prize + treasury fee = total pot
        assertEq(raffle.getPendingClaims(), pot);
        // All of pot should be pending (winner + treasury)
        assertEq(raffle.getPendingClaims(), prize + fee);
    }

    function test_FulfillRandomWords_RecordsRoundResult() external {
        _enterPlayers(2);
        uint256 reqId = _triggerDraw();
        vrfCoordinator.fulfillRandomWords(reqId, address(raffle));
        Raffle.RoundResult memory r = raffle.getRoundResult(1);
        assertEq(r.roundId,     1);
        assertEq(r.playerCount, 2);
        assertFalse(r.cancelled);
        assertTrue(r.winner != address(0));
        assertTrue(r.prize  > 0);
        assertTrue(r.timestamp > 0);
    }

    function test_FulfillRandomWords_EmitsWinnerPicked() external {
        _enterPlayers(2);
        uint256 reqId = _triggerDraw();
        vm.recordLogs();
        vrfCoordinator.fulfillRandomWords(reqId, address(raffle));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic = keccak256("WinnerPicked(address,uint256,uint256,uint256)");
        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == topic) found = true;
        }
        assertTrue(found, "WinnerPicked must be emitted");
    }

    function test_FulfillRandomWords_UsesRoundPotNotTotalBalance() external {
        // Round 1: 2 players, nobody claims
        _enterPlayers(2);
        uint256 pot1  = raffle.getCurrentRoundPot();
        uint256 fee1  = (pot1 * cfg.protocolFeeBps) / 10_000;
        uint256 prize1 = pot1 - fee1;
        uint256 reqId1 = _triggerDraw();
        vrfCoordinator.fulfillRandomWords(reqId1, address(raffle));
        address r1winner = raffle.getRecentWinner();
        assertEq(raffle.getWinnings(r1winner), prize1, "round1 prize correct");

        // Round 2: 3 players
        vm.prank(PLAYER);   raffle.enterRaffle{value: cfg.entranceFee}();
        vm.prank(PLAYER_2); raffle.enterRaffle{value: cfg.entranceFee}();
        vm.prank(PLAYER_3); raffle.enterRaffle{value: cfg.entranceFee}();

        uint256 pot2 = raffle.getCurrentRoundPot();
        assertEq(pot2, cfg.entranceFee * 3, "pot2 = only round2 fees");

        uint256 reqId2 = _triggerDraw();
        vrfCoordinator.fulfillRandomWords(reqId2, address(raffle));
        address r2winner = raffle.getRecentWinner();
        uint256 fee2   = (pot2 * cfg.protocolFeeBps) / 10_000;
        uint256 prize2 = pot2 - fee2;

        // r1winner winnings unchanged unless they also won round2
        if (r1winner != r2winner) {
            assertEq(raffle.getWinnings(r1winner), prize1, "round1 winnings unaffected by round2");
        }
        // r2winner gets prize2 (plus prize1 if same winner)
        uint256 expectedR2 = prize2 + (r1winner == r2winner ? prize1 : 0);
        assertEq(raffle.getWinnings(r2winner), expectedR2, "round2 winner prize correct");
    }

    /* ================================================================
       6. CLAIM WINNINGS
    ================================================================ */

    function test_ClaimWinnings_TransfersETH() external {
        address winner = _fullDraw(2);
        uint256 amount = raffle.getWinnings(winner);
        assertTrue(amount > 0, "winner must have pending winnings");
        uint256 balBefore = winner.balance;
        vm.prank(winner);
        raffle.claimWinnings();
        assertEq(winner.balance, balBefore + amount);
        assertEq(raffle.getWinnings(winner), 0);
    }

    function test_ClaimWinnings_EmitsEvent() external {
        address winner = _fullDraw(2);
        uint256 amount = raffle.getWinnings(winner);
        vm.expectEmit(true, false, false, true);
        emit WinningsClaimed(winner, amount);
        vm.prank(winner);
        raffle.claimWinnings();
    }

    function test_ClaimWinnings_DecreasesPendingClaims() external {
        address winner = _fullDraw(2);
        uint256 amount  = raffle.getWinnings(winner);
        uint256 pending = raffle.getPendingClaims();
        vm.prank(winner);
        raffle.claimWinnings();
        assertEq(raffle.getPendingClaims(), pending - amount);
    }

    function test_ClaimWinnings_RevertsIfNothingToClaim() external {
        vm.prank(PLAYER);
        vm.expectRevert(Raffle.Raffle__NothingToClaim.selector);
        raffle.claimWinnings();
    }

    function test_ClaimWinnings_CannotClaimTwice() external {
        address winner = _fullDraw(2);
        vm.startPrank(winner);
        raffle.claimWinnings();
        vm.expectRevert(Raffle.Raffle__NothingToClaim.selector);
        raffle.claimWinnings();
        vm.stopPrank();
    }

    function test_TreasuryClaims_Fee() external {
        _fullDraw(2);
        uint256 fee = raffle.getWinnings(cfg.treasury);
        assertTrue(fee > 0, "treasury must have fee");
        uint256 tBefore = cfg.treasury.balance;
        vm.prank(cfg.treasury);
        raffle.claimWinnings();
        assertEq(cfg.treasury.balance, tBefore + fee);
    }

    /* ================================================================
       7. PAUSE / UNPAUSE
    ================================================================ */

    function test_Pause_BlocksEntry() external {
        vm.prank(OWNER); raffle.pause();
        assertTrue(raffle.isPaused());
        vm.prank(PLAYER);
        vm.expectRevert();
        raffle.enterRaffle{value: cfg.entranceFee}();
    }

    function test_Pause_BlocksUpkeep() external {
        _enterPlayers(2);
        vm.prank(OWNER); raffle.pause();
        vm.warp(block.timestamp + cfg.interval + 1);
        (bool needed,) = raffle.checkUpkeep("");
        assertFalse(needed);
    }

    function test_Pause_EmitsEvent() external {
        vm.expectEmit(true, false, false, false);
        emit RafflePausedByOwner(OWNER);
        vm.prank(OWNER); raffle.pause();
    }

    function test_Pause_RevertsIfNotOwner() external {
        vm.prank(PLAYER);
        vm.expectRevert(); // Chainlink onlyOwner
        raffle.pause();
    }

    function test_Unpause_AllowsEntry() external {
        vm.prank(OWNER); raffle.pause();
        vm.prank(OWNER); raffle.unpause();
        assertFalse(raffle.isPaused());
        vm.prank(PLAYER);
        raffle.enterRaffle{value: cfg.entranceFee}();
        assertEq(raffle.getNumberOfPlayers(), 1);
    }

    function test_Unpause_ResetsTimestamp() external {
        _enterPlayers(2);
        vm.warp(block.timestamp + cfg.interval + 1);
        vm.prank(OWNER); raffle.pause();
        vm.warp(block.timestamp + 100);
        vm.prank(OWNER); raffle.unpause();
        (bool needed,) = raffle.checkUpkeep("");
        assertFalse(needed, "interval must restart after unpause");
    }

    function test_Unpause_SetsStateToOpen() external {
        _enterPlayers(2);
        vm.prank(OWNER); raffle.pause();
        vm.prank(OWNER); raffle.cancelRaffle(); // puts into CANCELLED
        vm.prank(OWNER); raffle.unpause();
        assertEq(uint256(raffle.getRaffleState()), uint256(Raffle.RaffleState.OPEN));
    }

    /* ================================================================
       8. CANCEL RAFFLE
    ================================================================ */

    function test_CancelRaffle_CreditsRefunds() external {
        _enterPlayers(2);
        vm.prank(OWNER); raffle.pause();
        vm.prank(OWNER); raffle.cancelRaffle();
        assertEq(raffle.getRefund(PLAYER),   cfg.entranceFee);
        assertEq(raffle.getRefund(PLAYER_2), cfg.entranceFee);
    }

    function test_CancelRaffle_ClearsHasEntered() external {
        _enterPlayers(2);
        vm.prank(OWNER); raffle.pause();
        vm.prank(OWNER); raffle.cancelRaffle();
        assertFalse(raffle.hasEntered(PLAYER));
        assertFalse(raffle.hasEntered(PLAYER_2));
    }

    function test_CancelRaffle_ClearsPlayersArray() external {
        _enterPlayers(2);
        vm.prank(OWNER); raffle.pause();
        vm.prank(OWNER); raffle.cancelRaffle();
        assertEq(raffle.getNumberOfPlayers(), 0);
    }

    function test_CancelRaffle_ResetsPot() external {
        _enterPlayers(2);
        assertGt(raffle.getCurrentRoundPot(), 0);
        vm.prank(OWNER); raffle.pause();
        vm.prank(OWNER); raffle.cancelRaffle();
        assertEq(raffle.getCurrentRoundPot(), 0);
    }

    function test_CancelRaffle_IncrementsRoundId() external {
        assertEq(raffle.getCurrentRoundId(), 1);
        _enterPlayers(2);
        vm.prank(OWNER); raffle.pause();
        vm.prank(OWNER); raffle.cancelRaffle();
        assertEq(raffle.getCurrentRoundId(), 2);
    }

    function test_CancelRaffle_StateStaysCANCELLED() external {
        _enterPlayers(2);
        vm.prank(OWNER); raffle.pause();
        vm.prank(OWNER); raffle.cancelRaffle();
        assertEq(uint256(raffle.getRaffleState()), uint256(Raffle.RaffleState.CANCELLED));
    }

    function test_CancelRaffle_StateBecomesOpenAfterUnpause() external {
        _enterPlayers(2);
        vm.prank(OWNER); raffle.pause();
        vm.prank(OWNER); raffle.cancelRaffle();
        vm.prank(OWNER); raffle.unpause();
        assertEq(uint256(raffle.getRaffleState()), uint256(Raffle.RaffleState.OPEN));
    }

    function test_CancelRaffle_PlayersCanEnterNextRound() external {
        _enterPlayers(2);
        vm.prank(OWNER); raffle.pause();
        vm.prank(OWNER); raffle.cancelRaffle();
        vm.prank(OWNER); raffle.unpause();
        vm.prank(PLAYER);
        raffle.enterRaffle{value: cfg.entranceFee}();
        assertEq(raffle.getNumberOfPlayers(), 1);
    }

    function test_CancelRaffle_RecordsCancelledRound() external {
        _enterPlayers(2);
        vm.prank(OWNER); raffle.pause();
        vm.prank(OWNER); raffle.cancelRaffle();
        Raffle.RoundResult memory r = raffle.getRoundResult(1);
        assertTrue(r.cancelled);
        assertEq(r.winner,      address(0));
        assertEq(r.prize,       0);
        assertEq(r.playerCount, 2);
    }

    function test_CancelRaffle_EmitsEvent() external {
        _enterPlayers(2);
        vm.prank(OWNER); raffle.pause();
        vm.expectEmit(true, false, false, false);
        emit RaffleCancelled(1, block.timestamp);
        vm.prank(OWNER); raffle.cancelRaffle();
    }

    function test_CancelRaffle_RevertsIfNotPaused() external {
        _enterPlayers(2);
        vm.prank(OWNER);
        vm.expectRevert(Raffle.Raffle__MustBePaused.selector);
        raffle.cancelRaffle();
    }

    function test_CancelRaffle_RevertsIfCalculating() external {
        _enterPlayers(2);
        _triggerDraw(); // CALCULATING
        vm.prank(OWNER); raffle.pause();
        vm.prank(OWNER);
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        raffle.cancelRaffle();
    }

    /* ================================================================
       9. CLAIM REFUND
    ================================================================ */

    function test_ClaimRefund_TransfersETH() external {
        _enterPlayers(2);
        vm.prank(OWNER); raffle.pause();
        vm.prank(OWNER); raffle.cancelRaffle();
        uint256 balBefore = PLAYER.balance;
        vm.prank(PLAYER);
        raffle.claimRefund();
        assertEq(PLAYER.balance,            balBefore + cfg.entranceFee);
        assertEq(raffle.getRefund(PLAYER),  0);
    }

    function test_ClaimRefund_EmitsEvent() external {
        _enterPlayers(1);
        vm.prank(OWNER); raffle.pause();
        vm.prank(OWNER); raffle.cancelRaffle();
        vm.expectEmit(true, false, false, true);
        emit RefundClaimed(PLAYER, cfg.entranceFee);
        vm.prank(PLAYER);
        raffle.claimRefund();
    }

    function test_ClaimRefund_DecreasesPendingClaims() external {
        _enterPlayers(2);
        vm.prank(OWNER); raffle.pause();
        vm.prank(OWNER); raffle.cancelRaffle();
        uint256 pending = raffle.getPendingClaims();
        vm.prank(PLAYER);
        raffle.claimRefund();
        assertEq(raffle.getPendingClaims(), pending - cfg.entranceFee);
    }

    function test_ClaimRefund_RevertsIfNothingToRefund() external {
        vm.prank(PLAYER);
        vm.expectRevert(Raffle.Raffle__NothingToRefund.selector);
        raffle.claimRefund();
    }

    function test_ClaimRefund_CannotClaimTwice() external {
        _enterPlayers(1);
        vm.prank(OWNER); raffle.pause();
        vm.prank(OWNER); raffle.cancelRaffle();
        vm.startPrank(PLAYER);
        raffle.claimRefund();
        vm.expectRevert(Raffle.Raffle__NothingToRefund.selector);
        raffle.claimRefund();
        vm.stopPrank();
    }

    /* ================================================================
       10. EMERGENCY WITHDRAW
    ================================================================ */

    function test_EmergencyWithdraw_OnlyWithdrawsOrphanedFunds() external {
        _enterPlayers(2);
        uint256 reqId = _triggerDraw();
        vrfCoordinator.fulfillRandomWords(reqId, address(raffle));
        uint256 pending    = raffle.getPendingClaims();
        uint256 balance    = address(raffle).balance;
        uint256 orphaned   = balance > pending ? balance - pending : 0;
        vm.prank(OWNER); raffle.pause();
        if (orphaned > 0) {
            uint256 ownerBefore = OWNER.balance;
            vm.prank(OWNER);
            raffle.emergencyWithdraw();
            assertEq(OWNER.balance,             ownerBefore + orphaned);
            assertEq(address(raffle).balance,   pending);
        }
    }

    function test_EmergencyWithdraw_EmitsEvent() external {
        // Send some extra ETH to create orphaned funds
        vm.deal(address(raffle), 1 ether);
        vm.prank(OWNER); raffle.pause();
        uint256 orphaned = address(raffle).balance - raffle.getPendingClaims();
        vm.expectEmit(true, false, false, true);
        emit EmergencyWithdraw(OWNER, orphaned);
        vm.prank(OWNER);
        raffle.emergencyWithdraw();
    }

    function test_EmergencyWithdraw_RevertsIfNotPaused() external {
        vm.prank(OWNER);
        vm.expectRevert(Raffle.Raffle__MustBePaused.selector);
        raffle.emergencyWithdraw();
    }

    function test_EmergencyWithdraw_RevertsIfNotOwner() external {
        vm.prank(OWNER); raffle.pause();
        vm.prank(PLAYER);
        vm.expectRevert();
        raffle.emergencyWithdraw();
    }

    function test_EmergencyWithdraw_RevertsIfOnlyPendingFunds() external {
        _enterPlayers(2);
        uint256 reqId = _triggerDraw();
        vrfCoordinator.fulfillRandomWords(reqId, address(raffle));
        vm.prank(OWNER); raffle.pause();
        vm.prank(OWNER);
        vm.expectRevert(Raffle.Raffle__NothingToClaim.selector);
        raffle.emergencyWithdraw();
    }

    /* ================================================================
       11. CONFIGURATION
    ================================================================ */

    function test_SetEntranceFee_UpdatesFee() external {
        vm.prank(OWNER); raffle.pause();
        vm.expectEmit(false, false, false, true);
        emit EntranceFeeUpdated(cfg.entranceFee, 0.05 ether);
        vm.prank(OWNER); raffle.setEntranceFee(0.05 ether);
        assertEq(raffle.getEntranceFee(), 0.05 ether);
    }

    function test_SetEntranceFee_RevertsIfNotPaused() external {
        vm.prank(OWNER);
        vm.expectRevert(Raffle.Raffle__MustBePaused.selector);
        raffle.setEntranceFee(0.05 ether);
    }

    function test_SetEntranceFee_RevertsIfNotOwner() external {
        vm.prank(OWNER); raffle.pause();
        vm.prank(PLAYER);
        vm.expectRevert();
        raffle.setEntranceFee(0.05 ether);
    }

    function test_SetProtocolFee_UpdatesBps() external {
        vm.prank(OWNER); raffle.pause();
        vm.expectEmit(false, false, false, true);
        emit ProtocolFeeUpdated(cfg.protocolFeeBps, 500);
        vm.prank(OWNER); raffle.setProtocolFee(500);
        assertEq(raffle.getProtocolFeeBps(), 500);
    }

    function test_SetProtocolFee_AllowsZero() external {
        vm.prank(OWNER); raffle.pause();
        vm.prank(OWNER); raffle.setProtocolFee(0);
        assertEq(raffle.getProtocolFeeBps(), 0);
    }

    function test_SetProtocolFee_RequiresPause() external {
        vm.prank(OWNER);
        vm.expectRevert(Raffle.Raffle__MustBePaused.selector);
        raffle.setProtocolFee(500);
    }

    function test_SetTreasury_UpdatesAddress() external {
        vm.prank(OWNER); raffle.pause();
        vm.expectEmit(true, true, false, false);
        emit TreasuryUpdated(cfg.treasury, address(0xDEAD));
        vm.prank(OWNER); raffle.setTreasury(address(0xDEAD));
        assertEq(raffle.getTreasury(), address(0xDEAD));
    }

    function test_SetTreasury_RevertsIfZero() external {
        vm.prank(OWNER); raffle.pause();
        vm.prank(OWNER);
        vm.expectRevert(Raffle.Raffle__InvalidTreasury.selector);
        raffle.setTreasury(address(0));
    }

    function test_SetTreasury_RequiresPause() external {
        vm.prank(OWNER);
        vm.expectRevert(Raffle.Raffle__MustBePaused.selector);
        raffle.setTreasury(address(0xDEAD));
    }

    /* ================================================================
       12. GETTERS / PURE VIEW
    ================================================================ */

    function test_Getters_Constants() external view {
        assertEq(raffle.getNumWords(),             1);
        assertEq(raffle.getRequestConfirmations(), 3);
        assertEq(raffle.getMaxPlayers(),           500);
        assertEq(raffle.getMinPlayers(),           2);
    }

    function test_Getters_RoundResult_CancelledRound() external {
        _enterPlayers(2);
        vm.prank(OWNER); raffle.pause();
        vm.prank(OWNER); raffle.cancelRaffle();
        Raffle.RoundResult memory r = raffle.getRoundResult(1);
        assertTrue(r.cancelled);
        assertEq(r.winner, address(0));
    }

    /* ================================================================
       13. FUZZ TESTS
    ================================================================ */

    /// @dev Any EOA with exact fee can enter
    function testFuzz_EnterRaffle_AnyEOA(address user) external {
        vm.assume(user != address(0));
        vm.assume(user.code.length == 0);
        vm.deal(user, cfg.entranceFee);
        vm.prank(user);
        raffle.enterRaffle{value: cfg.entranceFee}();
        assertEq(raffle.getNumberOfPlayers(), 1);
        assertTrue(raffle.hasEntered(user));
    }

    /// @dev Excess ETH is always fully refunded
    function testFuzz_ExcessRefund(uint256 extra) external {
        extra = bound(extra, 1, 10 ether);
        vm.deal(PLAYER, cfg.entranceFee + extra);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: cfg.entranceFee + extra}();
        assertEq(PLAYER.balance,              extra,           "excess fully refunded");
        assertEq(raffle.getCurrentRoundPot(), cfg.entranceFee, "pot = fee only");
    }

    /// @dev Prize + fee always equals total pot
    function testFuzz_ProtocolSplit_AlwaysAddsUp(uint256 bps) external view {
        bps = bound(bps, 0, raffle.MAX_PROTOCOL_BPS());
        uint256 total = 1 ether;
        uint256 fee   = (total * bps) / 10_000;
        assertEq(fee + (total - fee), total);
    }

    /// @dev Pot grows exactly with each player — no dust
    function testFuzz_PotAccounting(uint8 n) external {
        uint256 playerCount = bound(n, 2, 20);
        for (uint256 i = 0; i < playerCount; i++) {
            address p = makeAddr(string(abi.encodePacked("fuzz", i)));
            vm.deal(p, cfg.entranceFee);
            vm.prank(p);
            raffle.enterRaffle{value: cfg.entranceFee}();
        }
        assertEq(
            raffle.getCurrentRoundPot(),
            cfg.entranceFee * playerCount,
            "pot must equal sum of entrance fees"
        );
    }

    /// @dev After draw, pendingClaims == prize + fee == pot
    function testFuzz_PendingClaims_EqualsPot(uint8 n) external {
        uint256 playerCount = bound(n, 2, 10);
        for (uint256 i = 0; i < playerCount; i++) {
            address p = makeAddr(string(abi.encodePacked("pc", i)));
            vm.deal(p, cfg.entranceFee);
            vm.prank(p);
            raffle.enterRaffle{value: cfg.entranceFee}();
        }
        uint256 pot   = raffle.getCurrentRoundPot();
        uint256 reqId = _triggerDraw();
        vrfCoordinator.fulfillRandomWords(reqId, address(raffle));
        assertEq(raffle.getPendingClaims(), pot, "pendingClaims must equal pot");
    }

    /// @dev setProtocolFee accepts any value 0..MAX_PROTOCOL_BPS
    function testFuzz_SetProtocolFee_ValidRange(uint256 bps) external {
        bps = bound(bps, 0, raffle.MAX_PROTOCOL_BPS());
        vm.prank(OWNER); raffle.pause();
        vm.prank(OWNER); raffle.setProtocolFee(bps);
        assertEq(raffle.getProtocolFeeBps(), bps);
    }

    /// @dev setEntranceFee accepts any value >= MIN_ENTRANCE_FEE
    function testFuzz_SetEntranceFee_ValidRange(uint256 fee) external {
        fee = bound(fee, raffle.MIN_ENTRANCE_FEE(), 100 ether);
        vm.prank(OWNER); raffle.pause();
        vm.prank(OWNER); raffle.setEntranceFee(fee);
        assertEq(raffle.getEntranceFee(), fee);
    }

    /// @dev Winner is always one of the entered players (random distribution)
    function testFuzz_WinnerIsAlwaysAPlayer(uint256 seed) external {
        uint256 n = bound(seed, 2, 5);
        address[] memory players_ = new address[](n);
        for (uint256 i = 0; i < n; i++) {
            players_[i] = makeAddr(string(abi.encodePacked("fwinner", i, seed)));
            vm.deal(players_[i], cfg.entranceFee);
            vm.prank(players_[i]);
            raffle.enterRaffle{value: cfg.entranceFee}();
        }
        uint256 reqId = _triggerDraw();
        vrfCoordinator.fulfillRandomWords(reqId, address(raffle));
        address winner = raffle.getRecentWinner();
        bool isPlayer;
        for (uint256 i = 0; i < n; i++) {
            if (players_[i] == winner) isPlayer = true;
        }
        assertTrue(isPlayer, "winner must be a registered player");
    }

    /* ================================================================
       14. MULTI-ROUND
    ================================================================ */

    function test_MultipleRounds_PotIsolatedPerRound() external {
        _fullDraw(2);
        assertEq(raffle.getCurrentRoundId(),  2);
        assertEq(raffle.getCurrentRoundPot(), 0);

        vm.prank(PLAYER);   raffle.enterRaffle{value: cfg.entranceFee}();
        vm.prank(PLAYER_2); raffle.enterRaffle{value: cfg.entranceFee}();
        assertEq(raffle.getCurrentRoundPot(), cfg.entranceFee * 2);

        uint256 reqId2 = _triggerDraw();
        vrfCoordinator.fulfillRandomWords(reqId2, address(raffle));

        assertEq(raffle.getCurrentRoundId(),    3);
        assertEq(raffle.getTotalRoundsPlayed(), 2);
        assertEq(raffle.getCurrentRoundPot(),   0);
    }

    function test_MultipleRounds_WinnerHistoryGrows() external {
        for (uint256 round = 1; round <= 3; round++) {
            _enterPlayers(2);
            uint256 reqId = _triggerDraw();
            vrfCoordinator.fulfillRandomWords(reqId, address(raffle));
            assertEq(raffle.getWinnerHistory().length, round);
        }
    }
}
