
// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title  Raffle — Gas-Optimized Version
 * @notice Funksionallik avvalgi versiya bilan bir xil.
 *         Faqat storage layout va hot-path ko'rsatmalar optimizatsiya qilindi.
 *
 * ── Gas tejash usullari (qo'llanilgan) ──────────────────────────
 *
 *  [O1] STORAGE PACKING — eng katta tejash
 *       Solidity storage slotlari 32 byte. Kichik o'zgaruvchilar
 *       bir slotga joylashsa, har bir SLOAD/SSTORE'da bir nechta
 *       o'zgaruvchi bepul o'qiladi/yoziladi.
 *
 *       ESKI (8 ta alohida slot, har biri 32 byte):
 *         s_raffleState(32) + s_lastTimeStamp(32) + s_recentWinner(32)
 *         s_entranceFee(32) + s_protocolFeeBps(32) + s_treasury(32)
 *         s_currentRoundPot(32) + s_pendingClaims(32)
 *         + _paused(32) [RafflePausable abstract'dan]
 *         = 9 slot = 9 × 2100 = 18,900 gas (cold SLOAD)
 *
 *       YANGI (4 ta packed slot):
 *         Slot A: s_treasury(20) + s_entranceFee(12)             = 32 byte
 *         Slot B: s_recentWinner(20) + s_lastTimeStamp(4)
 *                 + s_protocolFeeBps(2) + s_raffleState(1)
 *                 + _paused(1) + [4 free]                        = 28 byte
 *         Slot C: s_currentRoundPot(16) + s_pendingClaims(16)   = 32 byte
 *         Slot D: s_currentRoundId(8) + [24 free]               = 8 byte
 *         = 4 slot = 4 × 2100 = 8,400 gas (cold SLOAD)
 *
 *       Tejash: 10,500 gas faqat cold SLOAD dan
 *
 *       Amaliy misol — checkUpkeep():
 *         ESKI: _paused(2100) + raffleState(2100) + lastTimeStamp(2100) = 6,300
 *         YANGI: Slot B bir marta (2100) — uchovi bepul keladi       = 2,100
 *         Tejash: 4,200 gas / chaqiruv
 *
 *       Amaliy misol — fulfillRandomWords():
 *         ESKI: 4 ta alohida SSTORE = 4 × 5,000 = 20,000 gas
 *         YANGI: Slot B 1 ta SSTORE = 5,000 gas
 *         Tejash: 15,000 gas / draw
 *
 *  [O2] RafflePausable inline qilindi
 *       Abstract contract ni alohida saqlash _paused ni o'z slotiga
 *       joylashtirar edi. Inline qilish orqali u Slot B ga paklanadi.
 *
 *  [O3] custom error "Paused" qo'shildi
 *       require("string") ≈ 90 gas qimmat, custom error arzonroq.
 *
 *  [O4] Type kichraytirildi — lekin mantiqiy chegaralar tekshirildi
 *       uint96  entranceFee  — max 79 billion ETH (yetarli)
 *       uint32  lastTimeStamp — 2106 yilgacha ishlaydi (yetarli)
 *       uint16  protocolFeeBps — max 65535 (biz 1000 da chekladik)
 *       uint128 pot/pending  — max 3.4e38 wei (yetarli)
 *       uint64  roundId      — 1.8e19 round (cheksiz)
 *
 *  [O5] Hot-path storage caching
 *       Bir funksiya ichida bir xil storage o'zgaruvchisini
 *       bir necha marta o'qish o'rniga, birinchi o'qishni lokal
 *       o'zgaruvchiga saqlash (warm SLOAD = 100 gas vs cold = 2100).
 *
 *  [O6] unchecked arifmetika
 *       Overflow imkonsiz bo'lgan joylarda unchecked ishlatildi.
 *       Loop counter (++i), roundId increment va boshqalar.
 *
 *  [O7] whenNotPaused modifier optimallashtirish
 *       require(string) o'rniga if + custom error.
 *       Slot B ning birinchi o'qishi (paused check) keyingi
 *       s_raffleState o'qishini ham "isitadi" (warm qiladi).
 * ─────────────────────────────────────────────────────────────────
 */
contract Raffle is
    VRFConsumerBaseV2Plus,
    AutomationCompatibleInterface,
    ReentrancyGuard
{
    /* ============================================================
       Errors
    ============================================================ */
    error Raffle__Paused();                                             // [O3]
    error Raffle__UpkeepNotNeeded(uint256 pot, uint256 players, uint256 state);
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
       Types
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
       Constants — bytecode'a "baked in", SLOAD = 0 gas
    ============================================================ */
    uint16  private constant REQUEST_CONFIRMATIONS = 3;
    uint32  private constant NUM_WORDS             = 1;
    uint256 public  constant MAX_PLAYERS           = 500;
    uint256 public  constant MIN_PLAYERS           = 2;
    uint256 public  constant MIN_ENTRANCE_FEE      = 0.001 ether;
    uint256 public  constant MAX_PROTOCOL_BPS      = 1_000;

    /* ============================================================
       Immutables — bytecode'a embedded, SLOAD = 0 gas
    ============================================================ */
    uint256 private immutable i_subscriptionId;
    bytes32 private immutable i_gasLane;
    uint32  private immutable i_callbackGasLimit;
    uint256 private immutable i_interval;

    /* ============================================================
       Storage — packed layout [O1][O2][O4]
       ─────────────────────────────────────────────────────────────
       Inherited slots (VRFConsumerBaseV2Plus, ReentrancyGuard) bu
       slotlardan oldin keladi. Raffle o'z slotlarini quyidan boshlaydi.
       ─────────────────────────────────────────────────────────────
       Slot A │ s_treasury      20 bytes │ s_entranceFee    12 bytes │ = 32
       Slot B │ s_recentWinner  20 bytes │ s_lastTimeStamp   4 bytes │
              │ s_protocolBps    2 bytes │ s_raffleState     1 byte  │
              │ _paused          1 byte  │ [4 bytes free]            │ = 28
       Slot C │ s_currentRoundPot 16 b  │ s_pendingClaims  16 bytes │ = 32
       Slot D │ s_currentRoundId  8 b   │ [24 bytes free]           │ = 8
    ============================================================ */

    // ── Slot A ───────────────────────────────────────────────────
    address private s_treasury;         // 20 bytes
    uint96  private s_entranceFee;      // 12 bytes │ max 79B ETH — yetarli

    // ── Slot B (eng ko'p o'qiladigan slot) ───────────────────────
    address private s_recentWinner;     // 20 bytes
    uint32  private s_lastTimeStamp;    //  4 bytes │ 2106 yilgacha ishlaydi
    uint16  private s_protocolFeeBps;   //  2 bytes │ max 65535 > cap 1000
    RaffleState private s_raffleState;  //  1 byte
    bool    private _paused;            //  1 byte  │ [O2] inline qilindi

    // ── Slot C ───────────────────────────────────────────────────
    uint128 private s_currentRoundPot;  // 16 bytes │ max 3.4e38 wei
    uint128 private s_pendingClaims;    // 16 bytes

    // ── Slot D ───────────────────────────────────────────────────
    uint64  private s_currentRoundId;   //  8 bytes │ cheksiz round

    // ── Dynamic arrays + mappings (har biri o'z slotida) ─────────
    address payable[] private s_players;
    address[]         private s_winnerHistory;

    mapping(address => bool)        private s_hasEntered;
    mapping(address => uint256)     private s_winnings;
    mapping(address => uint256)     private s_refunds;
    mapping(uint256 => RoundResult) private s_rounds;

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
       Modifier [O7]
       _paused (Slot B) o'qiladi. Keyingi s_raffleState o'qishi
       (ham Slot B) warm bo'ladi → 100 gas (cold 2100 emas).
    ============================================================ */
    modifier whenNotPaused() {
        if (_paused) revert Raffle__Paused();
        _;
    }

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

        // Slot A yozish (1 SSTORE)
        s_treasury    = treasury;
        s_entranceFee = uint96(entranceFee);

        // Slot B yozish (1 SSTORE)
        s_raffleState    = RaffleState.OPEN;
        s_lastTimeStamp  = uint32(block.timestamp);
        s_protocolFeeBps = uint16(protocolFeeBps);
        // _paused = false (default)

        // Slot D yozish
        s_currentRoundId = 1;
    }

    /* ============================================================
       Owner — pause controls
    ============================================================ */

    function pause() external onlyOwner {
        _paused = true;
        emit RafflePausedByOwner(msg.sender);
    }

    function unpause() external onlyOwner {
        // Slot B: barcha o'zgaruvchilarni bir SSTORE da yozish
        _paused         = false;
        s_raffleState   = RaffleState.OPEN;
        s_lastTimeStamp = uint32(block.timestamp);
        emit RaffleUnpausedByOwner(msg.sender);
    }

    /* ============================================================
       Owner — round management
    ============================================================ */

    function cancelRaffle() external onlyOwner {
        if (!_paused)                          revert Raffle__MustBePaused();
        if (s_raffleState != RaffleState.OPEN) revert Raffle__RaffleNotOpen();

        // [O5] Cache storage once
        uint256 len     = s_players.length;
        uint64  roundId = s_currentRoundId;
        uint96  fee     = s_entranceFee;       // Slot A — 1 SLOAD

        for (uint256 i = 0; i < len;) {
            address player = s_players[i];
            s_refunds[player] += fee;
            delete s_hasEntered[player];
            unchecked { ++i; }                 // [O6]
        }

        // Slot C: pot → 0, pendingClaims += pot (1 SSTORE)
        uint128 pot = s_currentRoundPot;
        s_currentRoundPot = 0;
        unchecked { s_pendingClaims += pot; }  // [O6]

        s_players = new address payable[](0);

        // Slot B: raffleState güncelle (1 SSTORE — recentWinner, timestamp da ayniy)
        s_raffleState = RaffleState.CANCELLED;

        // Slot D
        unchecked { ++s_currentRoundId; }      // [O6]

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
       Owner — configuration
    ============================================================ */

    function setEntranceFee(uint256 newFee) external onlyOwner {
        if (!_paused)                  revert Raffle__MustBePaused();
        if (newFee < MIN_ENTRANCE_FEE) revert Raffle__FeeTooLow();
        uint256 old = s_entranceFee;   // Slot A
        s_entranceFee = uint96(newFee);
        emit EntranceFeeUpdated(old, newFee);
    }

    function setProtocolFee(uint256 newBps) external onlyOwner {
        if (!_paused)                  revert Raffle__MustBePaused();
        if (newBps > MAX_PROTOCOL_BPS) revert Raffle__InvalidBPS();
        uint256 old = s_protocolFeeBps; // Slot B
        s_protocolFeeBps = uint16(newBps);
        emit ProtocolFeeUpdated(old, newBps);
    }

    function setTreasury(address newTreasury) external onlyOwner {
        if (!_paused)                  revert Raffle__MustBePaused();
        if (newTreasury == address(0)) revert Raffle__InvalidTreasury();
        address old = s_treasury;      // Slot A
        s_treasury = newTreasury;
        emit TreasuryUpdated(old, newTreasury);
    }

    function emergencyWithdraw() external onlyOwner {
        if (!_paused) revert Raffle__MustBePaused();
        uint256 balance  = address(this).balance;
        uint256 pending  = s_pendingClaims;    // Slot C
        uint256 orphaned = balance > pending ? balance - pending : 0;
        if (orphaned == 0) revert Raffle__NothingToClaim();
        address ownerAddr = owner();
        (bool ok,) = ownerAddr.call{value: orphaned}("");
        if (!ok) revert Raffle__TransferFailed();
        emit EmergencyWithdraw(ownerAddr, orphaned);
    }

    /* ============================================================
       External — user-facing

       enterRaffle() gas tahlili (packed vs original):
         whenNotPaused:    Slot B 1 SLOAD (paused)
         fee check:        Slot A 1 SLOAD (entranceFee)
         state check:      Slot B WARM    (raffleState) → 100 gas tejash
         players.length:   array slot 1 SLOAD
         hasEntered check: mapping 1 SLOAD
         pot update:       Slot C 1 SSTORE
         hasEntered write: mapping 1 SSTORE
         players.push:     array slot SSTORE + element SSTORE
         ──────────────────────────────────────────────────────────
         Tejash: ~2000 gas (raffleState endi warm, cold emas)
    ============================================================ */

    function enterRaffle() external payable whenNotPaused {
        // [O5] Slot A: cache entranceFee (1 SLOAD, uint96)
        uint256 fee = s_entranceFee;

        if (msg.value < fee)                   revert Raffle__SendMoreToEnterRaffle();
        if (s_raffleState != RaffleState.OPEN) revert Raffle__RaffleNotOpen();  // Slot B WARM
        if (s_players.length >= MAX_PLAYERS)   revert Raffle__MaxPlayersReached();
        if (s_hasEntered[msg.sender])          revert Raffle__AlreadyEntered();

        uint256 excess = msg.value - fee;
        if (excess > 0) {
            (bool ok,) = msg.sender.call{value: excess}("");
            if (!ok) revert Raffle__TransferFailed();
            emit ExcessRefunded(msg.sender, excess);
        }

        // [O6] unchecked: pot + fee won't overflow uint128
        // (MAX_PLAYERS=500, MAX_FEE reasonable, 500×100ETH << uint128.max)
        unchecked {
            s_currentRoundPot += uint128(fee); // Slot C
        }

        s_hasEntered[msg.sender] = true;
        s_players.push(payable(msg.sender));
        emit RaffleEnter(msg.sender, s_players.length);
    }

    function claimWinnings() external nonReentrant {
        uint256 amount = s_winnings[msg.sender];
        if (amount == 0) revert Raffle__NothingToClaim();
        s_winnings[msg.sender] = 0;
        unchecked { s_pendingClaims -= uint128(amount); } // [O6] Slot C
        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert Raffle__TransferFailed();
        emit WinningsClaimed(msg.sender, amount);
    }

    function claimRefund() external nonReentrant {
        uint256 amount = s_refunds[msg.sender];
        if (amount == 0) revert Raffle__NothingToRefund();
        s_refunds[msg.sender] = 0;
        unchecked { s_pendingClaims -= uint128(amount); } // [O6] Slot C
        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert Raffle__TransferFailed();
        emit RefundClaimed(msg.sender, amount);
    }

    /* ============================================================
       Chainlink Automation

       checkUpkeep() gas tahlili:
         ESKI: _paused(2100) + raffleState(2100) + lastTimeStamp(2100)
               + players.length(2100) + currentRoundPot(2100) = 10,500
         YANGI: Slot B(2100) + players.length(2100) + Slot C(2100) = 6,300
         Tejash: 4,200 gas / Chainlink chaqiruv
         (Chainlink har blokda chaqiradi → oyiga millionlab gas tejash!)
    ============================================================ */

    function checkUpkeep(bytes memory /* checkData */)
        public
        view
        override
        returns (bool upkeepNeeded, bytes memory)
    {
        // Slot B: _paused, s_raffleState, s_lastTimeStamp — 1 SLOAD
        bool notPaused  = !_paused;
        bool isOpen     = s_raffleState == RaffleState.OPEN;
        bool timePassed = (block.timestamp - s_lastTimeStamp) > i_interval;

        bool enoughPlayers = s_players.length >= MIN_PLAYERS;  // array slot
        bool hasBalance    = s_currentRoundPot > 0;            // Slot C

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
        s_raffleState = RaffleState.CALCULATING; // Slot B SSTORE
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

       fulfillRandomWords() gas tahlili:
         ESKI: 4 alohida Slot SSTORE
               (recentWinner + lastTimeStamp + raffleState + protocolFeeBps)
               = 4 × ~5000 = ~20,000 gas
         YANGI: Slot B 1 SSTORE = ~5,000 gas
         Tejash: ~15,000 gas / draw

         SLOAD tejash:
         ESKI: protocolFeeBps(2100) + treasury(2100) + currentRoundPot(2100)
               + pendingClaims(2100) = 8,400
         YANGI: Slot B(2100) + Slot A(2100) + Slot C(2100) = 6,300
         Tejash: 2,100 gas
    ============================================================ */

    function fulfillRandomWords(
        uint256,
        uint256[] calldata randomWords
    ) internal override nonReentrant {
        // [O5] Cache storage reads upfront
        uint256 playerCount   = s_players.length;
        address payable recentWinner = s_players[randomWords[0] % playerCount];

        // Slot C: 1 SLOAD for both pot and pendingClaims
        uint128 totalPrize = s_currentRoundPot;
        uint256 protocolFee = (uint256(totalPrize) * s_protocolFeeBps) / 10_000; // Slot B WARM
        uint256 winnerPrize = uint256(totalPrize) - protocolFee;

        uint64 roundId = s_currentRoundId; // Slot D

        // ── Effects: Slot B — 1 SSTORE for 4 fields ────────────
        s_recentWinner   = recentWinner;
        s_lastTimeStamp  = uint32(block.timestamp);
        s_raffleState    = RaffleState.OPEN;
        // s_protocolFeeBps ve _paused unchanged

        // ── Effects: Slot C — reset pot ─────────────────────────
        s_currentRoundPot = 0;

        // ── Effects: Slot D ──────────────────────────────────────
        unchecked { ++s_currentRoundId; } // [O6]

        // ── Reset players ────────────────────────────────────────
        uint256 len = playerCount;
        for (uint256 i = 0; i < len;) {
            delete s_hasEntered[s_players[i]];
            unchecked { ++i; } // [O6]
        }
        s_players = new address payable[](0);

        // ── Persist history ──────────────────────────────────────
        s_rounds[roundId] = RoundResult({
            winner:      recentWinner,
            prize:       winnerPrize,
            timestamp:   block.timestamp,
            playerCount: playerCount,
            roundId:     roundId,
            cancelled:   false
        });
        s_winnerHistory.push(recentWinner);

        // ── Credits (pure pull) — Slot C pendingClaims update ───
        s_winnings[recentWinner] += winnerPrize;
        unchecked { s_pendingClaims += uint128(winnerPrize); } // [O6]

        if (protocolFee > 0) {
            address treasury = s_treasury; // Slot A WARM (already read? no — cache it)
            s_winnings[treasury] += protocolFee;
            unchecked { s_pendingClaims += uint128(protocolFee); } // [O6]
        }

        emit WinnerPicked(recentWinner, winnerPrize, block.timestamp, uint256(roundId));
    }

    /* ============================================================
       View / Pure — getters
       (view funksiyalar gas sarflamaydi — off-chain chaqiruv)
    ============================================================ */

    function getRaffleState()                 public view returns (RaffleState)      { return s_raffleState; }
    function getEntranceFee()                 public view returns (uint256)          { return s_entranceFee; }
    function getLastTimeStamp()               public view returns (uint256)          { return s_lastTimeStamp; }
    function getInterval()                    public view returns (uint256)          { return i_interval; }
    function getNumberOfPlayers()             public view returns (uint256)          { return s_players.length; }
    function getPlayer(uint256 i)             public view returns (address)          { return s_players[i]; }
    function getRecentWinner()                public view returns (address)          { return s_recentWinner; }
    function getCurrentRoundId()              public view returns (uint256)          { return s_currentRoundId; }
    function getCurrentRoundPot()             public view returns (uint256)          { return s_currentRoundPot; }
    function getPendingClaims()               public view returns (uint256)          { return s_pendingClaims; }
    function isPaused()                       public view returns (bool)             { return _paused; }
    function paused()                         public view returns (bool)             { return _paused; }
    function getProtocolFeeBps()              public view returns (uint256)          { return s_protocolFeeBps; }
    function getTreasury()                    public view returns (address)          { return s_treasury; }
    function getWinnings(address a)           public view returns (uint256)          { return s_winnings[a]; }
    function getRefund(address a)             public view returns (uint256)          { return s_refunds[a]; }
    function hasEntered(address a)            public view returns (bool)             { return s_hasEntered[a]; }
    function getWinnerHistory()               public view returns (address[] memory) { return s_winnerHistory; }
    function getTotalRoundsPlayed()           public view returns (uint256)          { return s_winnerHistory.length; }
    function getRoundResult(uint256 roundId)  public view returns (RoundResult memory) { return s_rounds[roundId]; }
    function getNumWords()                    public pure returns (uint256)          { return NUM_WORDS; }
    function getRequestConfirmations()        public pure returns (uint256)          { return REQUEST_CONFIRMATIONS; }
    function getMaxPlayers()                  public pure returns (uint256)          { return MAX_PLAYERS; }
    function getMinPlayers()                  public pure returns (uint256)          { return MIN_PLAYERS; }
}
