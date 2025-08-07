# Prism Protocol

> **Automated Yield Aggregation on Stacks**

Prism Protocol is a decentralized yield aggregation platform that automatically compounds rewards across multiple Stacks DeFi protocols, maximizing returns for users while minimizing active management requirements. Now supporting multi-token deposits with SIP-10 token compatibility.

## 🌟 Features

- **Automated Compounding**: Smart yield optimization across multiple strategies
- **Multi-Protocol Integration**: Aggregate yields from various DeFi protocols
- **Multi-Token Support**: Support for STX and SIP-10 tokens with isolated pools
- **Risk-Adjusted Returns**: Strategies are rated and balanced based on risk scores
- **Transparent Fee Structure**: Low protocol fees with clear fee distribution
- **Gas-Efficient Operations**: Optimized smart contract design for minimal transaction costs

## 🚀 Quick Start

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) installed
- Stacks wallet with STX tokens or SIP-10 tokens
- Basic understanding of DeFi concepts

### Installation

```bash
git clone https://github.com/your-username/prism-protocol
cd prism-protocol
clarinet check
```

### Basic Usage

1. **Create Token Pool**: Call `create-token-pool` function for new SIP-10 tokens
2. **Deposit Tokens**: Call `deposit-token` function with desired amount and token contract
3. **Earn Yield**: Protocol automatically compounds rewards per token pool
4. **Withdraw**: Use `withdraw-token` function to claim your share plus yields

## 📊 Protocol Overview

### Core Functionality

- **Multi-Token Management**: Support for STX and any SIP-10 token with isolated pools
- **Token Pool Creation**: Permissioned creation of new token pools with validation
- **Deposit Management**: Users deposit tokens and receive shares proportional to their contribution
- **Yield Strategies**: Multiple yield-generating strategies with risk assessments per token
- **Automated Compounding**: Smart contract automatically reinvests yields when thresholds are met
- **Fee Distribution**: Transparent fee structure supporting protocol development

### Security Features

- **Parameter Validation**: All inputs are validated before processing
- **Token Contract Validation**: SIP-10 token contracts are verified before pool creation
- **Access Control**: Critical functions restricted to authorized users
- **Emergency Controls**: Protocol owner can pause strategies if needed
- **Bounded Operations**: All calculations use safe arithmetic with bounds checking
- **Isolated Token Pools**: Each token has its own pool preventing cross-contamination

## 🔧 Contract Functions

### Token Pool Management

- `create-token-pool(token-contract)`: Create a new pool for SIP-10 token
- `get-token-pool-info(token-contract)`: Get information about a token pool
- `get-supported-tokens()`: List all supported token pools

### User Functions

- `deposit(amount)`: Deposit STX tokens to earn yield (legacy)
- `deposit-token(token-contract, amount)`: Deposit SIP-10 tokens to earn yield
- `withdraw(shares)`: Withdraw STX share of the pool (legacy)
- `withdraw-token(token-contract, shares)`: Withdraw your share of a token pool
- `get-user-balance(user)`: Check user's current STX balance (legacy)
- `get-user-token-balance(user, token-contract)`: Check user's token balance
- `get-user-token-shares(user, token-contract)`: Check user's token shares
- `calculate-user-value(user)`: Calculate current value of user's STX position (legacy)
- `calculate-user-token-value(user, token-contract)`: Calculate token position value

### Strategy Management

- `add-yield-strategy()`: Add new yield-generating strategy
- `add-token-strategy(token-contract, strategy-id)`: Add strategy for specific token
- `compound-yield()`: Trigger compounding for a strategy
- `compound-token-yield(token-contract, strategy-id)`: Compound for token strategy
- `get-strategy-info()`: Get information about a strategy

### Protocol Administration

- `update-protocol-fee()`: Adjust protocol fee rate
- `emergency-pause-strategy()`: Pause a strategy in emergencies
- `emergency-pause-token-pool(token-contract)`: Pause a specific token pool

## 🧪 Testing

```bash
clarinet test
```

## 📈 Yield Strategies

The protocol supports multiple yield strategies with different risk profiles per token:

1. **Conservative**: Low-risk strategies with stable returns
2. **Balanced**: Medium-risk strategies balancing yield and safety
3. **Aggressive**: Higher-risk strategies with potential for greater returns

Each token can have its own set of strategies optimized for that specific asset.

## 🪙 Supported Tokens

The protocol supports:
- **STX**: Native Stacks token (legacy support)
- **SIP-10 Tokens**: Any compatible SIP-10 token through isolated pools

Token pools are created on-demand and validated for SIP-10 compliance before activation.

## 🛡️ Security

- All user funds are secured by battle-tested smart contract patterns
- Isolated token pools prevent cross-contamination between assets
- Multi-signature controls for protocol upgrades
- Regular security audits and community reviews
- Transparent on-chain operations
- SIP-10 token validation before pool creation

## 🤝 Contributing

We welcome contributions! Please read our contributing guidelines and submit pull requests for any improvements.

## 🔗 Links

- [Documentation](https://docs.prismprotocol.com)
- [Discord Community](https://discord.gg/prismprotocol)
- [Twitter](https://twitter.com/prismprotocol)

## 🗺️ Roadmap

- [x] **Multi-Token Support**: Extend protocol to support SIP-10 tokens beyond STX
- [ ] **Governance System**: Implement DAO voting for protocol parameters and strategy additions
- [ ] **Cross-Protocol Bridge**: Enable yield farming across Bitcoin Layer 2 solutions
- [ ] **Advanced Risk Metrics**: ML-powered risk assessment with historical performance analysis
- [ ] **Flash Loan Integration**: Add flash loan capabilities for capital-efficient arbitrage
- [ ] **Liquid Staking Integration**: Incorporate stacking rewards into yield strategies
- [ ] **Insurance Protocol**: Built-in insurance fund for strategy failures
- [ ] **Mobile SDK**: Native mobile app integration for easier user access
- [ ] **Yield Optimization AI**: Automated strategy allocation based on market conditions
- [ ] **NFT Yield Farming**: Enable NFT staking and yield generation through the protocol

## ⚠️ Disclaimer

This protocol is experimental software. Use at your own risk. Always do your own research before investing in DeFi protocols. Multi-token support adds additional complexity - ensure you understand the risks of each token pool.