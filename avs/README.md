# Shield Auction Hook AVS

A Hourglass-based Autonomous Verifiable Service (AVS) that provides distributed compute infrastructure for Shield auction operations on Uniswap V4 pools.

## Overview

This AVS serves as a **connector and coordinator** that interfaces with the main Shield Auction Hook project. It implements a task-based architecture using the Hourglass framework to provide:

- **Distributed task execution** for Shield auction operations
- **EigenLayer operator management** and staking coordination  
- **Task validation and fee calculation** for auction workflows
- **Decentralized consensus** on auction results and settlements

**Important**: This AVS does **not** contain the auction business logic itself. It provides the distributed compute layer that interfaces with the main [Shield Auction Hook](../src/ShieldAuctionHook.sol) contract where all auction logic resides.

## Architecture

This AVS follows the Hourglass DevKit template structure as a **connector system**:

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  EigenLayer     │───▶│  L1: Service    │───▶│  L2: Task Hook  │
│  (Operators)    │    │  Manager        │    │  (Connector)    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                       │
                                                       ▼
                                               ┌─────────────────┐
                                               │  Main Project:  │
                                               │  ShieldAuctionHook │
                                               │  (Business Logic)│
                                               └─────────────────┘
```

### Directory Structure

```
├── cmd/                          # Performer application (task orchestration)
│   ├── main.go                  # ✅ Shield Auction Performer implementation
│   └── main_test.go             # ✅ Comprehensive tests for all task types
├── contracts/                    # AVS connector contracts ONLY
│   ├── src/
│   │   ├── interfaces/          # AVS-specific interfaces
│   │   │   └── IAVSDirectory.sol # ✅ EigenLayer AVS interface
│   │   ├── l1-contracts/        # EigenLayer integration (connectors)
│   │   │   └── ShieldAuctionServiceManager.sol # ✅ L1 connector only
│   │   └── l2-contracts/        # Task lifecycle management (connectors)
│   │       └── ShieldAuctionTaskHook.sol # ✅ L2 connector only
│   ├── script/                  # Deployment scripts for connectors
│   │   ├── DeployShieldL1Contracts.s.sol # ✅ Deploy L1 connector
│   │   └── DeployShieldL2Contracts.s.sol # ✅ Deploy L2 connector
│   └── test/                    # Connector contract tests
│       ├── ShieldAuctionServiceManager.t.sol # ✅ L1 connector tests
│       └── ShieldAuctionTaskHook.t.sol       # ✅ L2 connector tests
├── .devkit/                     # DevKit integration
├── .hourglass/                  # Hourglass framework configuration
├── go.mod                       # ✅ Go dependencies (Hourglass/Ponos)
├── go.sum                       # ✅ Dependency checksums
└── README.md                    # This file
```

**❌ Business Logic NOT in AVS:**
- Main Shield Auction Hook logic → `../src/ShieldAuctionHook.sol`
- Price oracles → `../src/ChainlinkPriceOracle.sol`
- Auction libraries → `../src/libraries/AuctionLib.sol`
- Production configs → `../src/ProductionPriceFeedConfig.sol`

### Component Responsibilities

**✅ AVS Contracts (Connectors Only):**
- **L1 ServiceManager** (`ShieldAuctionServiceManager.sol`):
  - EigenLayer operator registration and staking coordination
  - Extends `TaskAVSRegistrarBase` for EigenLayer integration
  - References main Shield hook address (does not contain auction logic)
  
- **L2 TaskHook** (`ShieldAuctionTaskHook.sol`):
  - Implements `IAVSTaskHook` for Hourglass task lifecycle management
  - Validates Shield auction task parameters and calculates fees
  - Interfaces with main hook contract (does not replace it)

**✅ Go Performer (`cmd/main.go`):**
- **Task Orchestration**: Coordinates distributed execution of Shield tasks
- **Payload Parsing**: Handles 4 task types (monitoring, creation, validation, settlement)
- **Result Aggregation**: Aggregates responses from operators for consensus
- **Hourglass Integration**: Implements `ValidateTask` and `HandleTask` interfaces

**❌ Main Project (Business Logic - deployed separately):**
- **ShieldAuctionHook** (`../src/ShieldAuctionHook.sol`): All auction business logic
- **Price Oracles** (`../src/ChainlinkPriceOracle.sol`): Price monitoring logic
- **Auction Libraries** (`../src/libraries/AuctionLib.sol`): Bid processing logic

## Quick Start

### Prerequisites

- [Docker (latest)](https://docs.docker.com/engine/install/)
- [Foundry (latest)](https://book.getfoundry.sh/getting-started/installation)
- [Go (v1.23.6)](https://go.dev/doc/install)
- [DevKit CLI](https://github.com/Layr-Labs/devkit-cli)

### Build

```bash
# Build the performer binary
make build

# Build contracts
make build-contracts

# Build everything
make
```

### Development with DevKit

```bash
# Build AVS and contracts
devkit avs build --image shield-auction-hook

# Start local development network
devkit avs devnet start

# Run the performer
devkit avs run

# Simulate tasks
devkit avs call --task-type monitoring
```

### Testing

```bash
# Run all tests
make test

# Run Go tests only
make test-go

# Run Forge tests only
make test-forge
```

## Task Types

The Shield Auction Performer coordinates distributed execution of four main task types:

### 1. Shield Monitoring Tasks
- **Coordinate** price monitoring across multiple operators
- **Validate** Shield threshold breach detection parameters
- **Aggregate** monitoring results from distributed operators

### 2. Auction Creation Tasks  
- **Orchestrate** auction initialization across the network
- **Validate** auction parameters and operator permissions
- **Coordinate** auction setup with the main Shield Auction Hook

### 3. Bid Validation Tasks
- **Distribute** bid validation work across operators
- **Validate** bid parameters and operator signatures
- **Aggregate** bid validation results for consensus

### 4. Settlement Tasks
- **Coordinate** auction finalization across operators
- **Validate** settlement parameters and results
- **Orchestrate** reward distribution through the main hook contract

**Note**: The actual auction logic (price calculations, bid processing, etc.) is executed by the main [ShieldAuctionHook](../src/ShieldAuctionHook.sol) contract. The AVS provides distributed consensus and coordination.

## Configuration

Configuration is managed through the Hourglass framework:

- **`.hourglass/config/`** - Framework configuration
- **`.hourglass/context/`** - Environment-specific settings
- **`.devkit/`** - Development tooling configuration

## Smart Contracts

### AVS Connector Contracts

#### L1 Contracts (Ethereum Mainnet)
- **ShieldAuctionServiceManager.sol** - EigenLayer connector only
  - ✅ Extends `TaskAVSRegistrarBase` for DevKit compliance
  - ✅ Handles operator registration with minimum 10 ETH stake
  - ✅ References L2 hook address for coordination
  - ❌ **No auction business logic** - pure EigenLayer integration

#### L2 Contracts (Optimism/Arbitrum/etc.)
- **ShieldAuctionTaskHook.sol** - Task system connector only
  - ✅ Implements `IAVSTaskHook` for Hourglass integration
  - ✅ Validates 4 Shield task types with proper fee structure
  - ✅ Calculates task fees (0.001-0.01 ETH based on complexity)
  - ❌ **No auction business logic** - interfaces with main hook

### Main Project Contracts (deployed separately)

#### Core Business Logic (in main project)
- **[ShieldAuctionHook.sol](../src/ShieldAuctionHook.sol)** - All auction functionality
  - ✅ Uniswap V4 hook with complete Shield auction implementation
  - ✅ Price monitoring, bid processing, settlement execution
  - ✅ **All business logic here** - AVS provides distributed coordination

#### Supporting Infrastructure (in main project)
- **[ChainlinkPriceOracle.sol](../src/ChainlinkPriceOracle.sol)** - Price feeds
- **[AuctionLib.sol](../src/libraries/AuctionLib.sol)** - Auction utilities

## Deployment

### Prerequisites
1. **Deploy main Shield Auction Hook** first in your main project
2. **Note the deployed hook address** - you'll need it for AVS deployment

### AVS Deployment
Deployment is handled through DevKit scripts:

```bash
# 1. Deploy L1 AVS contracts (EigenLayer integration)
forge script contracts/script/DeployShieldL1Contracts.s.sol:DeployShieldL1Contracts

# 2. Deploy L2 AVS contracts (requires main hook address)
# Edit .hourglass/context/{environment}.json to include:
# {
#   "l2": {
#     "shieldAuctionHook": "0x..." // Your deployed main hook address
#   },
#   "l1": {
#     "serviceManager": "0x..." // From L1 deployment
#   }
# }

forge script contracts/script/DeployShieldL2Contracts.s.sol:DeployShieldL2Contracts
```

### Deployment Order
1. **Main Project**: Deploy `ShieldAuctionHook.sol` from main project
2. **AVS L1**: Deploy `ShieldAuctionServiceManager` (EigenLayer integration)  
3. **AVS L2**: Deploy `ShieldAuctionTaskHook` (connects to main hook)

## API

The performer exposes a gRPC server on port 8080 implementing the Hourglass Performer interface:

- `ValidateTask(TaskRequest) -> error` - Validates Shield auction task parameters
- `HandleTask(TaskRequest) -> TaskResponse` - Coordinates task execution with main hook

### Task Payload Structure

Tasks are JSON payloads with the following structure:
```json
{
  "type": "SHIELD_MONITORING|AUCTION_CREATION|BID_VALIDATION|SETTLEMENT", 
  "parameters": {
    "poolId": "0x...",
    "threshold": 1000,
    // ... task-specific parameters
  }
}
```

The performer validates these parameters and coordinates execution with the main Shield Auction Hook contract.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests: `make test`
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.