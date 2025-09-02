# 📡 Wifinet - Community Wi-Fi DAO

> Decentralized autonomous organization for shared Wi-Fi infrastructure management on Stacks blockchain

## 🌟 Overview

Wifinet enables communities to collectively own, manage, and monetize Wi-Fi infrastructure through a decentralized autonomous organization (DAO). Members can register Wi-Fi nodes, earn from usage, participate in governance, and collectively fund network expansion.

## ✨ Features

- 🏛️ **DAO Membership**: Join the community by staking STX tokens
- 📡 **Wi-Fi Node Registration**: Register and manage Wi-Fi access points
- 💰 **Usage-Based Payments**: Pay for Wi-Fi usage with automatic revenue sharing
- 🗳️ **Governance**: Create and vote on proposals for network improvements
- 📊 **Earnings Tracking**: Monitor node performance and earnings
- 🔒 **Decentralized Control**: Community-owned infrastructure management

## 🚀 Getting Started

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) installed
- Stacks wallet with STX tokens

### Installation

1. Clone the repository
2. Navigate to the project directory
3. Deploy the contract using Clarinet

```bash
clarinet deploy
```

## 📖 Usage Guide

### 1. 🎯 Join the DAO

```clarity
(contract-call? .Wifinet join-dao)
```

Pay the membership fee to become a DAO member and gain voting rights.

### 2. 📡 Register a Wi-Fi Node

```clarity
(contract-call? .Wifinet register-wifi-node "Downtown Coffee Shop" u100)
```

Register your Wi-Fi access point with location and bandwidth capacity.

### 3. 💻 Use Wi-Fi Services

```clarity
(contract-call? .Wifinet use-wifi u1 u50)
```

Pay for Wi-Fi usage by node ID and data amount. 70% goes to node owner, 30% to DAO treasury.

### 4. 🗳️ Create Governance Proposals

```clarity
(contract-call? .Wifinet create-proposal 
  "Expand Network Coverage" 
  "Fund 5 new nodes in underserved areas" 
  u5000000 
  'SP1234...)
```

### 5. 🗳️ Vote on Proposals

```clarity
(contract-call? .Wifinet vote-on-proposal u1 true)
```

### 6. 💸 Withdraw Node Earnings

```clarity
(contract-call? .Wifinet withdraw-earnings u1)
```

## 📊 Read-Only Functions

- `get-node-info`: Get Wi-Fi node details
- `get-member-info`: Get DAO member information
- `get-proposal-info`: Get proposal details
- `get-usage-info`: Get user's usage statistics
- `get-contract-balance`: Check DAO treasury balance

## 🏗️ Contract Architecture

### Data Structures

- **wifi-nodes**: Wi-Fi access point registry
- **dao-members**: DAO membership and voting power
- **proposals**: Governance proposals
- **votes**: Voting records
- **node-usage**: Usage tracking per user/node

### Revenue Model

- Users pay for Wi-Fi usage based on data consumption
- 70% of payments go to node owners
- 30% goes to DAO treasury for network expansion

## 🔧 Configuration

- **Membership Fee**: 1 STX
- **Proposal Duration**: 1440 blocks (~10 days)
- **Usage Cost**: 10 microSTX per data unit

## 🛡️ Security Features

- Member-only node registration
- Owner-only node management
- Anti-double voting protection
- Proposal expiration enforcement
- Balance validation for all transfers

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with Clarinet
5. Submit a pull request

## 📄 License

This project is open source and available under the MIT License.

## 🔗 Links

- [Stacks Documentation](https://docs.stacks.co/)
- [Clarity Language Reference](https://docs.stacks.co/clarity/)
- [Clarinet Documentation](https://github.com/hirosystems/clarinet)


