// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// ----------------------------------------------------------------
// WHY NO OZ Ownable / OZ Pausable?
//
// VRFConsumerBaseV2Plus  →  ConfirmedOwner  →  ConfirmedOwnerWithProposal
//
// ConfirmedOwnerWithProposal already defines:
//   - onlyOwner modifier
//   - owner() function
//   - transferOwnership()
//   - OwnershipTransferred event
//
// OZ Ownable defines the exact same symbols → fatal compiler clash (E6480).
// Solution: use Chainlink's built-in ownership and a lightweight custom
// Pausable that has zero external dependencies.
// ----------------------------------------------------------------

/**
 * @dev Minimal Pausable — same API as OZ Pausable, no Ownable dependency.
 *      onlyOwner comes from ConfirmedOwnerWithProposal via VRFConsumerBaseV2Plus.
 */
abstract contract RafflePausable {
    bool private _paused;

    event Paused(address account);
    event Unpaused(address account);

    modifier whenNotPaused() {
    _whenNotPaused();
    _;
    }

    function _whenNotPaused() internal view {
        require(!_paused, "Pausable: paused");
    }

    function paused() public view returns (bool) { return _paused; }
    function _pause()   internal { _paused = true;  emit Paused(msg.sender); }
    function _unpause() internal { _paused = false; emit Unpaused(msg.sender); }
}

/**
 * @title  Raffle — Production-ready decentralized lottery
 * @author GOLIBJON-developer — fully improved
 * @notice On-chain raffle using Chainlink VRF v2+ and Automation.
 *
 * ── Features ─────────────────────────────────────────────────────
 *  [1]  Pull-over-push payments      claimWinnings() / claimRefund()
 *  [2]  MAX_PLAYERS cap              prevents gas-limit DoS
 *  [3]  ReentrancyGuard              CEI + nonReentrant double-guard
 *  [4]  Ownable + Pausable           pause / unpause by owner
 *  [5]  Richer events                amount + roundId on every event
 *  [6]  Proper empty bytes           checkUpkeep returns ""
 *  [7]  Refund mechanism             cancelRaffle() + claimRefund()
 *  [8]  MIN_PLAYERS guard            draw only when >= 2 players
 *  [9]  Duplicate-entry guard        one ticket per address per round
 *  [10] Emergency withdraw           owner drain when paused
 *  [11] Mutable entrance fee         setEntranceFee() (paused only)
 *  [12] Winner history               full on-chain history array
 *  [13] Protocol fee (treasury)      configurable BPS
 *  [14] Multi-round tracking         RoundResult struct per roundId
 * ─────────────────────────────────────────────────────────────────
 */
contract Raffle is
    VRFConsumerBaseV2Plus,
    AutomationCompatibleInterface,
    ReentrancyGuard,
    RafflePausable
{
    /* ============================================================
       Errors
    ============================================================ */
    error Raffle__UpkeepNotNeeded(uint256 balance, uint256 numPlayers, uint256 raffleState);
    error Raffle__TransferFailed();
    error Raffle__SendMoreToEnterRaffle();
    error Raffle__RaffleNotOpen();
    error Raffle__MaxPlayersReached();
    error Raffle__NothingToClaim();
    error Raffle__NothingToRefund();
    error Raffle__AlreadyEntered();
    error Raffle__MustBePaused();
    error Raffle__FeeTooLow();
    error Raffle__InvalidBPS();
    error Raffle__InvalidTreasury();

    /* ============================================================
       Type declarations
    ============================================================ */
    enum RaffleState { OPEN, CALCULATING, CANCELLED }

    struct RoundResult {
        address winner;
        uint256 prize;
        uint256 timestamp;
        uint256 playerCount;
        uint256 roundId;
        bool    cancelled;
    }

    /* ============================================================
       Constants
    ============================================================ */
    uint16  private constant REQUEST_CONFIRMATIONS = 3;
    uint32  private constant NUM_WORDS             = 1;
    uint256 public  constant MAX_PLAYERS           = 500;
    uint256 public  constant MIN_PLAYERS           = 2;
    uint256 public  constant MIN_ENTRANCE_FEE      = 0.001 ether;
    uint256 public  constant MAX_PROTOCOL_BPS      = 1_000; // 10%

    /* ============================================================
       Immutables
    ============================================================ */
    uint256 private immutable i_subscriptionId;
    bytes32 private immutable i_gasLane;
    uint32  private immutable i_callbackGasLimit;
    uint256 private immutable i_interval;

    /* ============================================================
       Storage
    ============================================================ */
    RaffleState       private s_raffleState;
    uint256           private s_lastTimeStamp;
    address           private s_recentWinner;
    address payable[] private s_players;
    uint256           private s_entranceFee;
    uint256           private s_currentRoundId;
    uint256           private s_protocolFeeBps;
    address           private s_treasury;

    // [FIX-1] Tracks ONLY current round's collected ETH.
    // Unclaimed winnings from previous rounds live in s_winnings
    // and are NOT part of the current prize pot.
    uint256 private s_currentRoundPot;

    // [FIX-5] Total claimable ETH (winnings + refunds) owed to users.
    // emergencyWithdraw can only touch balance − s_pendingClaims.
    uint256 private s_pendingClaims;

    mapping(address => bool)        private s_hasEntered;
    mapping(address => uint256)     private s_winnings;
    mapping(address => uint256)     private s_refunds;
    mapping(uint256 => RoundResult) private s_rounds;

    address[] private s_winnerHistory;

    /* ============================================================
       Events
    ============================================================ */
    event RaffleEnter(address indexed player, uint256 totalPlayers);
    event ExcessRefunded(address indexed player, uint256 amount);
    event RequestedRaffleWinner(uint256 indexed requestId, uint256 indexed roundId);
    event WinnerPicked(address indexed winner, uint256 prize, uint256 timestamp, uint256 indexed roundId);
    event WinningsClaimed(address indexed winner, uint256 amount);
    event RefundClaimed(address indexed player, uint256 amount);
    event RaffleCancelled(uint256 indexed roundId, uint256 timestamp);
    event RafflePausedByOwner(address indexed by);
    event RaffleUnpausedByOwner(address indexed by);
    event EntranceFeeUpdated(uint256 oldFee, uint256 newFee);
    event ProtocolFeeUpdated(uint256 oldBps, uint256 newBps);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event EmergencyWithdraw(address indexed to, uint256 amount);

    /* ============================================================
       Constructor
    ============================================================ */
    constructor(
        uint256 subscriptionId,
        bytes32 gasLane,
        uint256 interval,
        uint256 entranceFee,
        uint32  callbackGasLimit,
        address vrfCoordinatorV2,
        address treasury,
        uint256 protocolFeeBps
    ) VRFConsumerBaseV2Plus(vrfCoordinatorV2) {
        if (treasury == address(0))            revert Raffle__InvalidTreasury();
        if (protocolFeeBps > MAX_PROTOCOL_BPS) revert Raffle__InvalidBPS();
        if (entranceFee < MIN_ENTRANCE_FEE)    revert Raffle__FeeTooLow();

        i_subscriptionId   = subscriptionId;
        i_gasLane          = gasLane;
        i_interval         = interval;
        i_callbackGasLimit = callbackGasLimit;

        s_entranceFee    = entranceFee;
        s_raffleState    = RaffleState.OPEN;
        s_lastTimeStamp  = block.timestamp;
        s_treasury       = treasury;
        s_protocolFeeBps = protocolFeeBps;
        s_currentRoundId = 1;
    }

    /* ============================================================
       Owner — pause controls
    ============================================================ */

    function pause() external onlyOwner {
        _pause();
        emit RafflePausedByOwner(msg.sender);
    }

    /// @notice Resume. If previous round was cancelled, resets to OPEN.
    function unpause() external onlyOwner {
        _unpause();
        // [FIX-6] unpause is the right place to reset state after cancel
        s_raffleState   = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
        emit RaffleUnpausedByOwner(msg.sender);
    }

    /* ============================================================
       Owner — round management
    ============================================================ */

    /**
     * @notice Cancel the current round. Credits all players a refund.
     * @dev    [FIX-2] Also clears s_hasEntered so players can enter next round.
     *         [FIX-6] State stays CANCELLED until unpause() resets it.
     */
    function cancelRaffle() external onlyOwner {
        if (!paused())                         revert Raffle__MustBePaused();
        if (s_raffleState != RaffleState.OPEN) revert Raffle__RaffleNotOpen();

        uint256 len     = s_players.length;
        uint256 roundId = s_currentRoundId;

        for (uint256 i = 0; i < len;) {
            address player = s_players[i];
            s_refunds[player]    += s_entranceFee;
            // [FIX-2] Clear entry flag so player can join next round
            delete s_hasEntered[player];
            unchecked { ++i; }
        }

        // [FIX-5] Pot becomes pending claims (will be claimed via claimRefund)
        s_pendingClaims += s_currentRoundPot;
        s_currentRoundPot = 0;

        s_players     = new address payable[](0);
        // [FIX-6] Stay CANCELLED — unpause() will set OPEN
        s_raffleState = RaffleState.CANCELLED;
        unchecked { ++s_currentRoundId; }

        // Record cancelled round in history
        s_rounds[roundId] = RoundResult({
            winner:      address(0),
            prize:       0,
            timestamp:   block.timestamp,
            playerCount: len,
            roundId:     roundId,
            cancelled:   true
        });

        emit RaffleCancelled(roundId, block.timestamp);
    }

    /* ============================================================
       Owner — configuration  (all require pause — [FIX-4])
    ============================================================ */

    function setEntranceFee(uint256 newFee) external onlyOwner {
        if (!paused())                 revert Raffle__MustBePaused();
        if (newFee < MIN_ENTRANCE_FEE) revert Raffle__FeeTooLow();
        uint256 old = s_entranceFee;
        s_entranceFee = newFee;
        emit EntranceFeeUpdated(old, newFee);
    }

    // [FIX-4] Now requires pause — prevents mid-round fee changes
    function setProtocolFee(uint256 newBps) external onlyOwner {
        if (!paused())                 revert Raffle__MustBePaused();
        if (newBps > MAX_PROTOCOL_BPS) revert Raffle__InvalidBPS();
        uint256 old = s_protocolFeeBps;
        s_protocolFeeBps = newBps;
        emit ProtocolFeeUpdated(old, newBps);
    }

    // [FIX-4] Now requires pause — prevents mid-round treasury swap
    function setTreasury(address newTreasury) external onlyOwner {
        if (!paused())                 revert Raffle__MustBePaused();
        if (newTreasury == address(0)) revert Raffle__InvalidTreasury();
        address old = s_treasury;
        s_treasury = newTreasury;
        emit TreasuryUpdated(old, newTreasury);
    }

    /**
     * @notice Emergency drain — only withdraws funds NOT owed to users.
     * @dev    [FIX-5] balance − s_pendingClaims = truly "orphaned" ETH.
     *         Legitimate winnings and refunds are never touched.
     */
    function emergencyWithdraw() external onlyOwner {
        if (!paused()) revert Raffle__MustBePaused();

        uint256 totalBalance = address(this).balance;
        uint256 ownerShare   = totalBalance > s_pendingClaims
            ? totalBalance - s_pendingClaims
            : 0;

        if (ownerShare == 0) revert Raffle__NothingToClaim();

        (bool ok,) = owner().call{value: ownerShare}("");
        if (!ok) revert Raffle__TransferFailed();
        emit EmergencyWithdraw(owner(), ownerShare);
    }

    /* ============================================================
       External — user-facing
    ============================================================ */

    /**
     * @notice Enter the raffle.
     * @dev    [FIX-3] Excess ETH above entranceFee is refunded immediately.
     *                 s_currentRoundPot += s_entranceFee (not msg.value).
     */
    function enterRaffle() external payable whenNotPaused {
        if (msg.value < s_entranceFee)         revert Raffle__SendMoreToEnterRaffle();
        if (s_raffleState != RaffleState.OPEN) revert Raffle__RaffleNotOpen();
        if (s_players.length >= MAX_PLAYERS)   revert Raffle__MaxPlayersReached();
        if (s_hasEntered[msg.sender])          revert Raffle__AlreadyEntered();

        // [FIX-3] Accept exactly entranceFee; refund the rest
        uint256 excess = msg.value - s_entranceFee;
        if (excess > 0) {
            (bool ok,) = msg.sender.call{value: excess}("");
            if (!ok) revert Raffle__TransferFailed();
            emit ExcessRefunded(msg.sender, excess);
        }

        // [FIX-1] Only track exact fee in the pot
        s_currentRoundPot += s_entranceFee;

        s_hasEntered[msg.sender] = true;
        s_players.push(payable(msg.sender));
        emit RaffleEnter(msg.sender, s_players.length);
    }

    /// @notice Claim ETH winnings from s_winnings (pull fallback).
    function claimWinnings() external nonReentrant {
        uint256 amount = s_winnings[msg.sender];
        if (amount == 0) revert Raffle__NothingToClaim();
        s_winnings[msg.sender] = 0;
        s_pendingClaims -= amount; // [FIX-5]
        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert Raffle__TransferFailed();
        emit WinningsClaimed(msg.sender, amount);
    }

    /// @notice Claim refund after a cancelled round.
    function claimRefund() external nonReentrant {
        uint256 amount = s_refunds[msg.sender];
        if (amount == 0) revert Raffle__NothingToRefund();
        s_refunds[msg.sender] = 0;
        s_pendingClaims -= amount; // [FIX-5]
        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert Raffle__TransferFailed();
        emit RefundClaimed(msg.sender, amount);
    }

    /* ============================================================
       Chainlink Automation
    ============================================================ */

    function checkUpkeep(bytes memory /* checkData */)
        public
        view
        override
        returns (bool upkeepNeeded, bytes memory)
    {
        bool notPaused     = !paused();
        bool isOpen        = s_raffleState == RaffleState.OPEN;
        bool timePassed    = (block.timestamp - s_lastTimeStamp) > i_interval;
        bool enoughPlayers = s_players.length >= MIN_PLAYERS;
        bool hasBalance    = s_currentRoundPot > 0; // [FIX-1] check pot, not total balance

        upkeepNeeded = notPaused && isOpen && timePassed && enoughPlayers && hasBalance;
        return (upkeepNeeded, "");
    }

    function performUpkeep(bytes calldata) external override {
        (bool upkeepNeeded,) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                s_currentRoundPot,
                s_players.length,
                uint256(s_raffleState)
            );
        }
        s_raffleState = RaffleState.CALCULATING;

        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash:              i_gasLane,
                subId:                i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit:     i_callbackGasLimit,
                numWords:             NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            })
        );
        emit RequestedRaffleWinner(requestId, s_currentRoundId);
    }

    /* ============================================================
       Chainlink VRF callback
    ============================================================ */

    /**
     * @dev [FIX-1] Uses s_currentRoundPot (not address(this).balance).
     *      [FIX-7] Hybrid push/pull:
     *               1. Try direct push to winner.
     *               2. On failure → store in s_winnings for pull claim.
     *              Treasury always uses pull (contracts often can't receive ETH).
     */
    function fulfillRandomWords(
        uint256,
        uint256[] calldata randomWords
    ) internal override nonReentrant {
        uint256 playerCount   = s_players.length;
        uint256 indexOfWinner = randomWords[0] % playerCount;
        address payable recentWinner = s_players[indexOfWinner];

        // [FIX-1] Use isolated round pot, not total balance
        uint256 totalPrize  = s_currentRoundPot;
        uint256 protocolFee = (totalPrize * s_protocolFeeBps) / 10_000;
        uint256 winnerPrize = totalPrize - protocolFee;

        // ── Effects (CEI) ────────────────────────────────────
        uint256 roundId    = s_currentRoundId;
        s_recentWinner     = recentWinner;
        s_lastTimeStamp    = block.timestamp;
        s_raffleState      = RaffleState.OPEN;
        s_currentRoundPot  = 0; // [FIX-1] reset pot
        unchecked { ++s_currentRoundId; }

        // Reset players + duplicate-entry flags
        uint256 len = s_players.length;
        for (uint256 i = 0; i < len;) {
            delete s_hasEntered[s_players[i]];
            unchecked { ++i; }
        }
        s_players = new address payable[](0);

        // Persist round result
        s_rounds[roundId] = RoundResult({
            winner:      recentWinner,
            prize:       winnerPrize,
            timestamp:   block.timestamp,
            playerCount: playerCount,
            roundId:     roundId,
            cancelled:   false
        });
        s_winnerHistory.push(recentWinner);

        // ── Interactions: pure pull pattern ──────────────────
        // No ETH transfer in callback — avoids reentrancy, failed push,
        // and unpredictable gas. Winner + treasury claim via claimWinnings().
        s_winnings[recentWinner] += winnerPrize;
        s_pendingClaims          += winnerPrize;

        if (protocolFee > 0) {
            s_winnings[s_treasury] += protocolFee;
            s_pendingClaims        += protocolFee;
        }

        emit WinnerPicked(recentWinner, winnerPrize, block.timestamp, roundId);
    }

    /* ============================================================
       View / Pure — getters
    ============================================================ */

    function getRaffleState()                    public view returns (RaffleState)      { return s_raffleState; }
    function getEntranceFee()                    public view returns (uint256)          { return s_entranceFee; }
    function getLastTimeStamp()                  public view returns (uint256)          { return s_lastTimeStamp; }
    function getInterval()                       public view returns (uint256)          { return i_interval; }
    function getNumberOfPlayers()                public view returns (uint256)          { return s_players.length; }
    function getPlayer(uint256 i)                public view returns (address)          { return s_players[i]; }
    function getRecentWinner()                   public view returns (address)          { return s_recentWinner; }
    function getCurrentRoundId()                 public view returns (uint256)          { return s_currentRoundId; }
    function getCurrentRoundPot()                public view returns (uint256)          { return s_currentRoundPot; }
    function getPendingClaims()                  public view returns (uint256)          { return s_pendingClaims; }
    function isPaused()                          public view returns (bool)             { return paused(); }
    function getProtocolFeeBps()                 public view returns (uint256)          { return s_protocolFeeBps; }
    function getTreasury()                       public view returns (address)          { return s_treasury; }
    function getWinnings(address a)              public view returns (uint256)          { return s_winnings[a]; }
    function getRefund(address a)                public view returns (uint256)          { return s_refunds[a]; }
    function hasEntered(address a)               public view returns (bool)             { return s_hasEntered[a]; }
    function getWinnerHistory()                  public view returns (address[] memory) { return s_winnerHistory; }
    function getTotalRoundsPlayed()              public view returns (uint256)          { return s_winnerHistory.length; }
    function getRoundResult(uint256 roundId)     public view returns (RoundResult memory) { return s_rounds[roundId]; }
    function getNumWords()                       public pure returns (uint256)          { return NUM_WORDS; }
    function getRequestConfirmations()           public pure returns (uint256)          { return REQUEST_CONFIRMATIONS; }
    function getMaxPlayers()                     public pure returns (uint256)          { return MAX_PLAYERS; }
    function getMinPlayers()                     public pure returns (uint256)          { return MIN_PLAYERS; }
}
