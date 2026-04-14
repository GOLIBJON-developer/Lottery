# ================================================================
#  Raffle — Foundry Makefile
#  Usage: make <target>
# ================================================================

-include .env

# ── Default values (override via .env or command line) ──────────
RPC_URL        ?= http://127.0.0.1:8545
PRIVATE_KEY    ?= 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
NETWORK_ARGS   := --rpc-url $(RPC_URL) --private-key $(PRIVATE_KEY) --broadcast

# Sepolia specific
ifeq ($(findstring sepolia,$(NETWORK)),sepolia)
	NETWORK_ARGS := --rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) \
	                --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
endif

.PHONY: all clean install build test test-unit test-integration \
        test-gas snapshot coverage \
        deploy deploy-sepolia \
        create-sub fund-sub add-consumer \
        format lint help

# ── Dependencies ────────────────────────────────────────────────

install:
	@echo ">>> Installing dependencies..."
	forge install smartcontractkit/chainlink-brownie-contracts@1.1.1 
	forge install OpenZeppelin/openzeppelin-contracts@v4.9.3 
	forge install Cyfrin/foundry-devops 
	forge install foundry-rs/forge-std 
	forge install transmissions11/solmate@v6

# ── Build ────────────────────────────────────────────────────────

build:
	forge build

clean:
	forge clean
	@rm -rf cache out

# ── Tests ────────────────────────────────────────────────────────

test:
	forge test -v

test-unit:
	forge test --match-path test/unit/RaffleTest.t.sol -vv

test-integration:
	forge test --match-path test/integration/RaffleIntegrationTest.t.sol -vv

# Verbose (show all logs)
test-vvv:
	forge test -vvv

# Gas report
test-gas:
	forge test --gas-report

# Snapshot (compare gas between runs)
snapshot:
	forge snapshot

# Coverage report (requires lcov: brew install lcov)
coverage:
	forge coverage --report lcov
	genhtml lcov.info --branch-coverage --output-dir coverage/
	@echo ">>> Open coverage/index.html in browser"

# ── Deploy ───────────────────────────────────────────────────────
 
deploy:
	@echo ">>> Deploying to local Anvil..."
	forge script script/DeployRaffle.s.sol $(NETWORK_ARGS)
 
# ── Step 1: Create VRF subscription (run ONCE, save subId to .env) ──────────
create-sub-sepolia:
	@echo ">>> Creating VRF subscription on Sepolia..."
	@echo "After running, add SUBSCRIPTION_ID=<subId> to .env"
	forge script script/CreateSubscription.s.sol \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--account $(ACCOUNT) \
		--broadcast --slow -vvvv
 
# ── Step 2: Fund + Deploy + AddConsumer (requires SUBSCRIPTION_ID in .env) ───
deploy-sepolia:
	@echo ">>> Deploying Raffle to Sepolia..."
	@echo "Requires: SUBSCRIPTION_ID in .env, LINK in wallet (faucets.chain.link)"
	forge script script/DeployRaffle.s.sol \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--account $(ACCOUNT) \
		--broadcast --verify \
		--etherscan-api-key $(ETHERSCAN_API_KEY) \
		--skip-simulation --slow \
		-vvvv
 
# ── Chainlink interactions ───────────────────────────────────────

create-sub:
	forge script script/Interactions.s.sol:CreateSubscription $(NETWORK_ARGS)

fund-sub:
	forge script script/Interactions.s.sol:FundSubscription $(NETWORK_ARGS)

add-consumer:
	forge script script/Interactions.s.sol:AddConsumer $(NETWORK_ARGS)

enter:
	forge script script/Interactions.s.sol:EnterRaffle $(NETWORK_ARGS)

# ── Code quality ────────────────────────────────────────────────

format:
	forge fmt

lint:
	forge fmt --check

# ── Help ────────────────────────────────────────────────────────

help:
	@echo ""
	@echo "  make install           Install all dependencies"
	@echo "  make build             Compile contracts"
	@echo "  make test              Run all tests"
	@echo "  make test-unit         Run unit tests only"
	@echo "  make test-integration  Run integration tests only"
	@echo "  make test-gas          Run tests with gas report"
	@echo "  make snapshot          Save gas snapshot"
	@echo "  make coverage          Generate HTML coverage report"
	@echo "  make deploy            Deploy to local Anvil"
	@echo "  make deploy-sepolia    Deploy to Sepolia + verify"
	@echo "  make create-sub        Create VRF subscription"
	@echo "  make fund-sub          Fund VRF subscription"
	@echo "  make add-consumer      Add Raffle as VRF consumer"
	@echo "  make enter             Enter the raffle (manual test)"
	@echo "  make format            Format all Solidity files"
	@echo ""
#forge script script/Interactions.s.sol:FundSubscription --rpc-url $SEPOLIA_RPC_URL --account golib --broadcast