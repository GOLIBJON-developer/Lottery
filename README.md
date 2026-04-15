# ⚡ Raffle — Decentralized On-Chain Lottery

> A production-grade, fully decentralized lottery built on Ethereum Sepolia, powered by **Chainlink VRF v2.5** for verifiable randomness and **Chainlink Automation** for trustless, automatic draws — no server, no admin intervention.

[![Live Demo](https://img.shields.io/badge/Live%20Demo-netlify-00C7B7?style=for-the-badge&logo=netlify)](https://raffle-mod.netlify.app/)
[![Contract](https://img.shields.io/badge/Contract-Sepolia-627EEA?style=for-the-badge&logo=ethereum)](https://sepolia.etherscan.io/address/0xc2cb8835769662d48E31A4272Bfde1A2530DD9b4)
[![Verified](https://img.shields.io/badge/Etherscan-Verified-2ECC71?style=for-the-badge)](https://sepolia.etherscan.io/address/0xc2cb8835769662d48E31A4272Bfde1A2530DD9b4#code)
[![Tests](https://img.shields.io/badge/Tests-98%20passing-2ECC71?style=for-the-badge)](#testing)
[![Tests](https://github.com/YOUR_USERNAME/YOUR_REPO/actions/workflows/test.yml/badge.svg)](https://github.com/YOUR_USERNAME/YOUR_REPO/actions/workflows/test.yml)

**Live:** https://raffle-mod.netlify.app/
**Contract:** [`0xc2cb8835769662d48E31A4272Bfde1A2530DD9b4`](https://sepolia.etherscan.io/address/0xc2cb8835769662d48E31A4272Bfde1A2530DD9b4)

---

## Screenshots

### Player View
![Player UI](img/ui-user.jpg)
*Any connected wallet can enter the current round, track the prize pot, countdown timer, and claim winnings.*

### Owner Dashboard
![Owner UI](img/ui-owner.jpg)
*When the deployer wallet is connected, a third column appears with full administrative controls: pause, cancel, fee configuration, and emergency tools.*

---

## Table of Contents

- [How It Works](#how-it-works)
- [Architecture](#architecture)
- [Smart Contract](#smart-contract)
  - [Deployed Address](#deployed-address)
  - [Features](#features)
  - [Functions Reference](#functions-reference)
  - [Gas Optimized Version](#gas-optimized-version)
- [Frontend](#frontend)
  - [Player Features](#player-features)
  - [Owner Features](#owner-features)
- [Testing](#testing)
  - [Test Coverage](#test-coverage)
  - [Running Tests](#running-tests)
- [Local Development](#local-development)
- [Deployment Guide](#deployment-guide)
  - [Smart Contract](#smart-contract-deployment)
  - [Frontend](#frontend-deployment)
- [Project Structure](#project-structure)
- [Security](#security)
- [Tech Stack](#tech-stack)

---

## How It Works

```
1. Players call enterRaffle() paying the entrance fee in ETH
         ↓
2. Chainlink Automation monitors checkUpkeep() every block
         ↓
3. When interval passes and conditions are met, performUpkeep() is triggered
         ↓
4. A Chainlink VRF request is sent — a verifiably random number is returned
         ↓
5. fulfillRandomWords() selects the winner, credits winnings (pull pattern)
         ↓
6. Winner calls claimWinnings() to receive ETH
```

**Five conditions must ALL be true before a draw triggers:**

| Condition | Why |
|---|---|
| `!paused` | Owner can halt the raffle at any time |
| `state == OPEN` | No draw already in progress |
| `block.timestamp - lastTimestamp > interval` | Time interval has elapsed |
| `players.length >= 2` | At least 2 entrants for a meaningful lottery |
| `currentRoundPot > 0` | ETH in the pot |

---

## Architecture

```
┌──────────────────────────────────────────────────┐
│              Next.js Frontend                    │
│   Wagmi v2 · Viem · RainbowKit                  │
│                                                  │
│  RaffleApp ──► RaffleCard  OwnerPanel           │
│           ──► WinnersList  UserStatus           │
│  hooks: useRaffleData · useRaffleWrite           │
└───────────────────┬──────────────────────────────┘
                    │  read / write
┌───────────────────▼──────────────────────────────┐
│              Raffle.sol  (Sepolia)               │
│                                                  │
│  enterRaffle()   checkUpkeep()   claimWinnings() │
│  performUpkeep() cancelRaffle()  emergencyWithdraw│
│  fulfillRandomWords()  (VRF callback)            │
└──────────┬──────────────────────┬────────────────┘
           │                      │
┌──────────▼──────┐   ┌───────────▼──────────────┐
│ Chainlink VRF   │   │  Chainlink Automation     │
│ v2.5 (random)   │   │  (automatic draw trigger) │
└─────────────────┘   └──────────────────────────┘
```

---

## Smart Contract

### Deployed Address

| Network | Address | Status |
|---|---|---|
| Sepolia | [`0xc2cb8835769662d48E31A4272Bfde1A2530DD9b4`](https://sepolia.etherscan.io/address/0xc2cb8835769662d48E31A4272Bfde1A2530DD9b4) | ✅ Verified |

Contract source is publicly verified on Etherscan — every line of logic is auditable by anyone.

### Features

| # | Feature | Description |
|---|---|---|
| 1 | **Pull payment pattern** | Winners call `claimWinnings()` — no ETH push to unknown addresses |
| 2 | **Prize pot isolation** | `s_currentRoundPot` tracks only the current round's ETH. Previous unclaimed winnings never bleed into the new prize |
| 3 | **ReentrancyGuard** | CEI pattern + `nonReentrant` modifier as a double safety layer |
| 4 | **Pause / Unpause** | Owner can halt entries and automation at any time |
| 5 | **Rich events** | Every action emits an event with full context (amount, roundId, timestamp) |
| 6 | **Refund mechanism** | `cancelRaffle()` credits all players; they pull refunds via `claimRefund()` |
| 7 | **MIN_PLAYERS guard** | Draw only triggers with ≥ 2 players |
| 8 | **Duplicate entry guard** | `s_hasEntered` mapping — one ticket per address per round |
| 9 | **Emergency withdraw** | Owner can drain only orphaned ETH; `s_pendingClaims` is always protected |
| 10 | **Mutable entrance fee** | `setEntranceFee()` — requires pause |
| 11 | **Winner history** | Full on-chain winner array via `getWinnerHistory()` |
| 12 | **Protocol fee** | Configurable BPS fee (max 10%) credited to a treasury address |
| 13 | **Multi-round tracking** | `RoundResult` struct stored per round ID |
| 14 | **Excess ETH refund** | Overpayments are returned immediately; pot only holds exact entrance fee |

### Functions Reference

#### Player Functions

| Function | Type | Description |
|---|---|---|
| `enterRaffle()` | `payable` | Enter the current round by sending the entrance fee |
| `claimWinnings()` | `nonpayable` | Claim ETH prize after winning |
| `claimRefund()` | `nonpayable` | Claim refund if the round was cancelled |

#### Automation (called by Chainlink)

| Function | Type | Description |
|---|---|---|
| `checkUpkeep(bytes)` | `view` | Returns `true` when all 5 draw conditions are met |
| `performUpkeep(bytes)` | `nonpayable` | Locks the raffle and fires a VRF request |

#### Owner Functions

| Function | Requires | Description |
|---|---|---|
| `pause()` | owner | Halt the raffle |
| `unpause()` | owner | Resume; resets the interval countdown |
| `cancelRaffle()` | owner + paused | Cancel current round, credit refunds |
| `setEntranceFee(uint256)` | owner + paused | Update entrance fee (wei) |
| `setProtocolFee(uint256)` | owner + paused | Update fee in BPS (200 = 2%, max 1000) |
| `setTreasury(address)` | owner + paused | Update protocol fee recipient |
| `emergencyWithdraw()` | owner + paused | Drain orphaned ETH (not pending claims) |

#### View / Pure Getters

| Function | Returns |
|---|---|
| `getRaffleState()` | `0`=OPEN `1`=CALCULATING `2`=CANCELLED |
| `getEntranceFee()` | Current fee in wei |
| `getCurrentRoundPot()` | ETH in current round |
| `getNumberOfPlayers()` | Active player count |
| `getLastTimeStamp()` | Unix timestamp of last draw reset |
| `getInterval()` | Draw interval in seconds |
| `getRecentWinner()` | Most recent winner address |
| `getWinnerHistory()` | All-time winner address array |
| `getCurrentRoundId()` | Current round number |
| `getPendingClaims()` | Total ETH owed to users (protected) |
| `getWinnings(address)` | Claimable prize for a given address |
| `getRefund(address)` | Claimable refund for a given address |
| `getRoundResult(uint256)` | Full `RoundResult` struct for a round |
| `hasEntered(address)` | Whether an address entered this round |
| `isPaused()` | Current pause state |

### Gas Optimized Version

`src/RaffleGasOptimized.sol` is an alternative implementation with the same logic but storage-packed slots:

```
Standard version:   9 storage slots  (9 × 2100 = 18,900 gas cold SLOAD)
Optimized version:  4 storage slots  (4 × 2100 =  8,400 gas cold SLOAD)
```

**Packed layout:**

```
Slot A │ s_treasury (20 bytes)    │ s_entranceFee (12 bytes)       │
Slot B │ s_recentWinner (20 bytes)│ s_lastTimeStamp (4 bytes)      │
       │ s_protocolFeeBps (2 b)   │ s_raffleState (1 b) │ _paused  │
Slot C │ s_currentRoundPot (16 b) │ s_pendingClaims (16 bytes)     │
Slot D │ s_currentRoundId (8 bytes)                                │
```

Key savings per function:

| Function | Standard | Optimized | Saved |
|---|---|---|---|
| `checkUpkeep()` | ~10,500 gas | ~6,300 gas | **4,200 gas** |
| `enterRaffle()` | ~80,000 gas | ~78,000 gas | **~2,000 gas** |
| `fulfillRandomWords()` | ~120,000 gas | ~103,000 gas | **~17,000 gas** |

> `checkUpkeep()` is called by Chainlink every block (~7,200× per day). The 4,200 gas saving per call adds up significantly over time.

---

## Frontend

**Live:** [https://raffle-mod.netlify.app](https://raffle-mod.netlify.app)

Built with Next.js 14 (App Router), Wagmi v2, Viem, and RainbowKit.

### Player Features

- Connect any EVM wallet (MetaMask, WalletConnect, Coinbase Wallet, etc.)
- See real-time prize pot, player count, and countdown to next draw
- One-click raffle entry at the current entrance fee
- Live winner feed via `WinnerPicked` event subscription
- **Claim Prize** button appears automatically if you won
- **Claim Refund** button appears if your round was cancelled
- "YOU" badge on your address in the winners list

### Owner Features

Owner panel only renders when the deployer wallet is connected (checked via `raffle.owner()`):

- **Pause / Unpause** — single button, state-aware
- **Cancel Round** — only enabled when paused + OPEN
- **Set Entrance Fee** — input field, requires pause
- **Set Protocol Fee** — BPS input with live current value display, requires pause
- **Set Treasury** — address input, requires pause
- **Emergency Withdraw** — shows protected pending claims amount

---

## Testing

### Test Coverage

![Coverage Report](img/coverage.jpg)

98 unit tests · 8 fuzz tests · 6 integration scenarios

```
Test Suites:  2
Tests:        104 total  (98 unit + 6 integration)
Fuzz runs:    1000 per fuzz test
Status:       All passing ✅
```

Coverage highlights:

| Area | Tests |
|---|---|
| Constructor validation | 4 tests |
| `enterRaffle()` — all revert paths | 7 tests |
| `checkUpkeep()` — each condition | 7 tests |
| `performUpkeep()` | 4 tests |
| `fulfillRandomWords()` — VRF callback | 9 tests |
| Pull payments (claim / refund) | 8 tests |
| Pause / Unpause | 5 tests |
| Cancel + refund flow | 9 tests |
| Emergency withdraw | 5 tests |
| Config functions | 8 tests |
| Fuzz: any EOA can enter | 1000 runs |
| Fuzz: prize split always correct | 1000 runs |
| Fuzz: excess always refunded | 1000 runs |
| Fuzz: pot accounting | 1000 runs |
| Fuzz: winner always a player | 1000 runs |
| Integration: full lifecycle | 6 scenarios |

### Running Tests

```bash
# All tests
forge test -v

# Unit tests only
forge test --match-path test/unit/RaffleTest.t.sol -vv

# Integration tests
forge test --match-path test/integration/RaffleIntegrationTest.t.sol -vv

# Gas report
forge test --gas-report

# Coverage (requires lcov: brew install lcov)
forge coverage --report lcov
genhtml lcov.info --branch-coverage --output-dir coverage/
```

---

## Local Development

### Prerequisites

- [Node.js 20+](https://nodejs.org)
- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Sepolia ETH + LINK ([faucets.chain.link](https://faucets.chain.link))
- [WalletConnect Cloud](https://cloud.walletconnect.com) project ID

### Setup

```bash
git clone https://github.com/GOLIBJON-developer/lottery
cd raffle

# Foundry dependencies
forge install

# Frontend dependencies
cd raffle-ui
npm install
```

### Run locally

```bash
# Terminal 1 — local chain
anvil

# Terminal 2 — deploy to anvil
forge script script/DeployRaffle.s.sol --broadcast

# Terminal 3 — frontend
cd raffle-ui
npm run dev
```

Open [http://localhost:3000](http://localhost:3000).

---

## Deployment Guide

### Environment Variables

Create `.env` in the project root:

```env
# RPC
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY

# Foundry keystore account name (cast wallet import)
ACCOUNT=your-keystore-name

# Block explorer
ETHERSCAN_API_KEY=YOUR_KEY

# Set AFTER Step 1 below
SUBSCRIPTION_ID=0
```

### Smart Contract Deployment

Deployment uses a **two-step** process because `createSubscription()` generates the subscription ID using `blockhash` — it differs between Foundry's local dry-run and the actual on-chain execution. Splitting the steps eliminates the mismatch.

**Step 1 — Create VRF subscription**

```bash
make create-sub-sepolia ACCOUNT=your-account
```

Copy the printed subscription ID into `.env` as `SUBSCRIPTION_ID`.

**Step 2 — Deploy and verify**

```bash
make deploy-sepolia ACCOUNT=your-account
```

This single command:
1. Funds the VRF subscription with 3 LINK
2. Deploys `Raffle.sol`
3. Registers the contract as a VRF consumer
4. Verifies source code on Etherscan automatically

**Step 3 — Register Chainlink Automation**

1. Go to [automation.chain.link](https://automation.chain.link) → Sepolia
2. **Register new Upkeep** → **Custom Logic**
3. Enter deployed contract address
4. Fund with 0.5–1 LINK
5. Confirm

**Step 4 — Update frontend**

```typescript
// raffle-ui/lib/contract.ts
export const RAFFLE_ADDRESS = "0xYourDeployedAddress" as const
```

### Frontend Deployment

**Netlify (recommended)**

```bash
cd raffle-ui
npm run build   # verify no errors first

# Via Netlify CLI
npx netlify-cli deploy --prod --dir=.next
```

Or connect the repo to Netlify:
1. Import repo at [app.netlify.com](https://app.netlify.com)
2. Set **Base directory** to `raffle-ui`
3. Set **Build command** to `npm run build`
4. Add env var: `NEXT_PUBLIC_WALLETCONNECT_ID`

**Vercel**

```bash
cd raffle-ui
npx vercel --prod
```

---

## Project Structure

```
raffle/
├── src/
│   └── Raffle.sol                  Main contract (14 features)
│
├── script/
│   ├── CreateSubscription.s.sol    Step 1 of deploy
│   ├── DeployRaffle.s.sol          Step 2 of deploy
│   ├── HelperConfig.s.sol          Network config (Anvil / Sepolia)
│   └── Interactions.s.sol          Manual helpers
│
├── test/
│   ├── unit/
│   │   └── RaffleTest.t.sol        98 unit + fuzz tests
│   ├── integration/
│   │   └── RaffleIntegrationTest.t.sol   6 lifecycle scenarios
│   └── mocks/
│       ├── VRFCoordinatorV2_5Mock.sol
│       └── LinkToken.sol
│
├── raffle-ui/                      Next.js 14 frontend
│   ├── app/
│   │   ├── layout.tsx
│   │   ├── page.tsx
│   │   ├── providers.tsx           Wagmi + RainbowKit
│   │   └── globals.css
│   ├── components/
│   │   ├── RaffleApp.tsx           Root orchestrator
│   │   ├── raffle/
│   │   │   ├── RaffleCard.tsx      Pot, enter, claim
│   │   │   ├── OwnerPanel.tsx      Admin controls
│   │   │   ├── WinnersList.tsx     Live + history feed
│   │   │   ├── UserStatus.tsx      My wallet status
│   │   │   ├── ContractStats.tsx   On-chain stats
│   │   │   └── StatusBadge.tsx     OPEN / PAUSED badge
│   │   └── ui/
│   │       ├── Toast.tsx
│   │       ├── Divider.tsx
│   │       └── StatRow.tsx
│   ├── hooks/
│   │   ├── useRaffleData.ts        Batched contract reads
│   │   └── useRaffleWrite.ts       Write + confirmation
│   └── lib/
│       ├── contract.ts             ABI + address
│       ├── wagmi.ts                Config
│       └── utils.ts                Shared helpers
│
├── foundry.toml
├── Makefile
└── README.md
```

---

## Security

- **No private keys in code** — Foundry keystores (`cast wallet import`) for deployment
- **Pull payments** — ETH never pushed to unknown addresses inside VRF callback
- **CEI pattern** — all state changes before balance updates; `ReentrancyGuard` as backup
- **`emergencyWithdraw` bounded** — `balance - s_pendingClaims` only; user funds are always protected
- **Config requires pause** — entrance fee, protocol fee, and treasury address can only change while the raffle is paused, preventing mid-round manipulation
- **3 VRF confirmations** — makes randomness manipulation economically infeasible
- **Contract verified** — full source code publicly auditable on Etherscan

---

## Tech Stack

| Layer | Technology |
|---|---|
| Smart Contract | Solidity 0.8.19 |
| Framework | Foundry (forge, cast, anvil) |
| Randomness | Chainlink VRF v2.5 |
| Automation | Chainlink Automation |
| Access Control | Chainlink ConfirmedOwner |
| Reentrancy | OpenZeppelin ReentrancyGuard |
| Frontend | Next.js 14 (App Router) |
| Language | TypeScript |
| Ethereum hooks | Wagmi v2 |
| Ethereum library | Viem |
| Wallet UI | RainbowKit |
| State management | TanStack Query |
| Hosting | Netlify |

---

## License

MIT © 2025

---

*Built as a portfolio project demonstrating production-grade Solidity development, Chainlink oracle integration, security patterns, comprehensive testing, and modern Web3 frontend architecture.*
