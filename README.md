# Raffle — Decentralized On-Chain Lottery

Production-ready raffle contract built with Foundry, Chainlink VRF v2.5, and Chainlink Automation.

## Architecture

Deploy
  │
  ▼
[OPEN] ──► enterRaffle() × N o'yinchi
  │
  │  (interval o'tdi, MIN_PLAYERS bor, ETH bor, paused emas)
  ▼
checkUpkeep() → true
  │
  ▼
performUpkeep() → s_raffleState = CALCULATING
  │               VRF ga so'rov yuborildi
  │
  │  (3 blok o'tdi, Chainlink javob berdi)
  ▼
fulfillRandomWords()
  ├── g'olib tanlandi
  ├── s_winnings[winner] += prize
  ├── s_winnings[treasury] += fee
  ├── players reset
  ├── s_raffleState = OPEN  ◄─── keyingi round boshlandi
  └── ++roundId

  │
  ▼
g'olib claimWinnings() chaqiradi → ETH oladi
treasury claimWinnings() chaqiradi → fee oladi

---------------------------------------------------------------------
Xavfsizlik qatlamlari xulasasi
Xavf                                        Himoya 
Reentrancy hujumi                           CEI pattern + nonReentrant
Manipulyatsiya qilingan random              Chainlink VRF
Gas limit DoS                               MAX_PLAYERS = 500
Push payment xatosi                         Pull pattern
Owner suiste'moli when                      Paused guard konfiguratsiyada
Noto'g'ri deploy                            Constructor validatsiyalari
Bir kishi ko'p kirishi                      s_hasEntered mapping
Bo'sh round draw                            MIN_PLAYERS = 2
--------------------------------------------------------------------

## Quick Start

```bash
# 1. Install dependencies
make install

# 2. Copy and fill environment
cp .env.example .env

# 3. Build
make build

# 4. Run all tests
make test

# 5. Gas report
make test-gas

# 6. Deploy locally (Anvil)
anvil                    # in one terminal
make deploy              # in another
```

## Deploy to Sepolia

```bash
# 1. Fill .env with SEPOLIA_RPC_URL, PRIVATE_KEY, ETHERSCAN_API_KEY
# 2. Create and fund a VRF subscription at https://vrf.chain.link
# 3. Set VRF_SUBSCRIPTION_ID in .env

make deploy-sepolia      # deploys + verifies on Etherscan
make add-consumer        # registers contract with VRF subscription
```

## Contract Features

| Feature | Description |
|---|---|
| Pull payments | Winners call `claimWinnings()` — push-free |
| Pause / Unpause | Owner can halt the raffle at any time |
| Cancel + Refund | `cancelRaffle()` credits all players |
| One entry per round | Duplicate entries rejected |
| Max 500 players | Gas-safe array cap |
| Min 2 players | No single-player "draws" |
| Protocol fee | Configurable BPS taken on each prize |
| Round history | Full `RoundResult` stored per round |
| Emergency drain | Owner can drain ETH when paused |

## Running Tests

```bash
make test              # all tests
make test-unit         # unit only
make test-integration  # integration only
make test-gas          # with gas report
make coverage          # HTML coverage (requires lcov)
forge test --match-test test_FulfillRandomWords -vvv   # single test verbose
```

## Chainlink Config (Sepolia)

| Parameter | Value |
|---|---|
| VRF Coordinator | `0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B` |
| Key Hash (200 gwei) | `0x787d74...` |
| Subscription | Create at vrf.chain.link |

## License

MIT
0x3faab6CcBc253d3F1B2b56ec6E194197ea7d9a95
