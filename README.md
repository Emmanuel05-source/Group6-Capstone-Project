Group 6 Capstone Project: Decentralized Subscription Protocol
​A robust, production-grade decentralized subscription platform built using Solidity and the Foundry framework. The protocol enables service providers to manage recurring billing logic on-chain, while granting users non-transferable (Soulbound) NFT payment receipts for every cycle they purchase.

​Architecture & Mechanics
​The system handles the full lifecycle of decentralized subscriptions with the following specialized core mechanics:
​Subscription Period Model: One standard subscription interval is defined as 30 days. Subscriptions are tracked in real-time by checking the current block timestamp against a subscriber's individual expiration timeline.
​Prepayment & Interval Stacking: Users are allowed to buy and stack up to 12 periods of subscription access upfront. For ongoing active users, renewing adds time directly to the end of their existing expiration timeline without losing any coverage days.
​On-Chain NFT Receipts: Inherits from OpenZeppelin's ERC721URIStorage. For every single month paid, a specific loop executes to mint an individual token to the subscriber containing granular structural metadata like period start, period end, and the period number.
​Soulbound Functionality: To maintain regulatory compliance and prevent users from transferring proof-of-payment receipts to unauthorized accounts, contract transfers are blocked by default via an overridden internal update function. The protocol owner can toggle this behavior at will.

​Project Directory Structure
​Group6CapstoneProject/
├── .github/workflows/       # GitHub Actions automated CI/CD pipeline
├── lib/                     # Project submodules & third-party dependencies
│   └── openzeppelin-contracts/
├── script/                  # Deployment script architecture
│   └── DeploySubscriptionProtocol.s.sol
├── src/                     # Core smart contract source code
│   └── SubscriptionProtocol.sol
├── test/                    # Full Unit testing suite
│   └── SubscriptionProtocol.t.sol
├── .env                     # Local environment keys (Secret)
├── .gitignore               # Safe Git path exclusion file
├── remappings.txt           # Dependency path overrides
└── README.md                # Project documentation
​Local Setup & Dependencies
​Clone the Workspace
git clone <your-repository-url>
cd Group6CapstoneProject
​Download Project Dependencies
Install the OpenZeppelin smart contract submodules utilizing Forge:
forge install openzeppelin/openzeppelin-contracts
​Verify Compiler Re-mappings
Ensure your remappings.txt file exists in the root folder to route the compiler imports safely:
@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/

​Testing Suite
​The testing layout includes 30 automated unit tests establishing 100% core execution safety coverage including edge cases, failure states, modifier rejections, and state viewing math.
​To execute the entire unit testing package locally:
forge test
​To enforce structural code formatting consistency across your files before a Git commit:
forge fmt
​Deployment & Etherscan Verification
​The deployment uses the Foundry script broadcasting pipeline to target the public Ethereum Sepolia Testnet.

​Configure the Local Environment
Initialize a secure .env file in your root project folder. Never push this file to GitHub.
PRIVATE_KEY=0x...your_wallet_private_key...
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_ALCHEMY_KEY
ETHERSCAN_API_KEY=YOUR_ETHERSCAN_DASHBOARD_API_KEY
​Broadcast Live to Sepolia Testnet
Execute the deployment command. This transmits the constructor bytecode directly onto the network and securely uploads the standard JSON metadata to Etherscan for instant code verification:
forge script script/DeploySubscriptionProtocol.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY -vvvv
​Core Smart Contract API
​User Interfaces
​subscribe(uint256 periods) external payable: Validates paid ETH matches the input cycles and registers a new user profile on-chain.
​renewSubscription(uint256 periods) external payable: Extends active timelines or restarts a fully lapsed plan safely from the current block time.
​isActive(address subscriber) public view: Evaluation function checking if a subscriber's package is currently active or expired.
​getSubscription(address subscriber) external view: Returns a packed profile data tuple for lightning-fast frontend dashboard loading.

​Governance Interfaces
​setSubscriptionFee(uint256 newFee): Allows the owner to adjust pricing scales immediately for all subsequent renewals.
​toggleSoulbound(): Toggles the transfer block restriction for receipt NFTs.
​withdraw(address payable to): Securely routes all accumulated ETH subscription revenue from the contract balance directly to the group's treasury wallet.