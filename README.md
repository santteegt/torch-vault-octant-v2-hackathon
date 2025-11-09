
# TorchVault - Combining yield burning with charitable giving


## YieldBethStrategy: Productive ETH Burning with Yield Generation

### The Problem and Solution

Many protocols and L2s commit to burning ETH from fees, but immediate burning misses the chance to generate yield first. YieldBethStrategy lets projects commit to burn ETH while making it productive during a lockup period. Instead of burning immediately, ETH is staked into yield-bearing protocols (e.g., RocketPool rETH), where it earns yield. After the lockup, the original ETH is burned via BETH, and users receive BETH tokens as proof-of-burn. This turns a one-time burn into a productive commitment that generates value before permanent removal.

### The Flywheel Effect and Use Cases

The strategy creates a flywheel: ETH generates yield during the lockup, and that yield can be donated to public goods (via the dragon router) before the principal is burned. This means each burn can fund public goods, creating a positive feedback loop where more burns generate more funding. Protocols and L2s can use this to make their burn commitments productive, turning fee burns into a mechanism that supports public goods while still fulfilling their burn promise. The lockup period ensures funds remain productive for a set duration, maximizing the yield generated for public goods.
BETH Integration and RocketPool Implementation
BETH integration provides proof-of-burn as a transparent, composable primitive. Each BETH token represents ETH permanently removed from circulation, allowing contracts, incentives, and applications to reference verified burns without intermediaries or off-chain systems. We implement an example using RocketPool's rETH: users deposit ETH, which is converted to rETH and staked; the strategy tracks rETH/ETH exchange rate appreciation to capture yield; after the lockup, rETH is converted back to ETH, deposited into BETH, and users receive BETH tokens representing their burned ETH. This demonstrates how any yield-bearing ETH derivative can be integrated into the productive burning framework.

### YieldSkimmingStrategy as a base strategy

he yield skimming strategy is a passive mechanism for assets that appreciate via exchange rate (e.g., rETH, stETH). Unlike active strategies that deploy funds, it holds the appreciating asset and tracks its exchange rate.

### Implementation details 

See [IMPLEMENTATION.md](IMPLEMENTATION.md) for details.

## Getting Started

### Prerequisites

1. Install [Foundry](https://book.getfoundry.sh/getting-started/installation) (WSL recommended for Windows)
2. Install [Node.js](https://nodejs.org/en/download/package-manager/)
3. Clone this repository:
```sh
git clone git@github.com:santteegt/torch-vault-octant-v2-hackathon.git
```

4. Install dependencies:
```sh
forge install
forge soldeer install
```

