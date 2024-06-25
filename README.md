# 100k ENS Lotto

## Overview
100k ENS Lotto is a decentralized lottery system built on Ethereum, utilizing ENS (Ethereum Name Service) domains. The lottery allows users to buy tickets for a chance to win prizes, with a portion of the prize pool distributed to stakers of 5-digit ENS domains.

## Contracts

### 1. LOTTERY
The `Lottery` contract is responsible for managing the lottery system. It allows users to buy tickets, handles the random selection of winners using Chainlink VRF, and distributes the prize pool accordingly.

#### Key Features:
- **Ticket Purchase**: Users can buy tickets by providing a 5-digit number.
- **Random Winner Selection**: Utilizes Chainlink VRF to ensure fairness and randomness.
- **Prize Distribution**: Distributes prizes to winners and a portion to the `NFTVault` for ENS domain stakers.
- **Configurable Parameters**: Admin can set ticket price, series count, fraction count, and prize levels.
- **Pause/Unpause**: The contract can be paused and unpaused by the admin.

#### Functions:
- `setPrizeLevels()`: Configure the prize levels.
- `buyTickets(string memory number)`: Buy a ticket for the given number.
- `getNextAvailableTicket(string memory number)`: Find the next available series and fraction for the given number.
- `checkUpkeep(bytes calldata)`: Check if it's time for a draw.
- `performUpkeep(bytes calldata)`: Perform the draw if it's time.
- `requestRandomWords()`: Request random words from Chainlink VRF.
- `fulfillRandomWords(uint256, uint256[] memory)`: Callback function for Chainlink VRF.
- `drawWinners(uint256 randomSeed)`: Draw winners based on the random seed.
- `getTicketOwner(uint256 series, string memory numStr)`: Get the owner of a specific ticket.
- `pause(bool _paused)`: Pause or unpause the contract.
- `setSeriesCount(uint256 newSeriesCount)`: Set the number of series.
- `setFractionCount(uint256 newFractionCount)`: Set the number of fractions per series.
- `setTicketPrice(uint256 newTicketPrice)`: Set the ticket price.
- `flattenWinners()`: Get a flattened list of all winners.
- `uintToStr(uint256 v)`: Convert a number to a 5-digit string.
- `isWinningNode(bytes32 node)`: Check if a node is a winning node.

### 2. NFTVault
The `NFTVault` contract is designed to reward owners of 5-digit ENS domains who register their domains in the contract. It distributes a portion of the lottery prize pool to these stakers.

#### Key Features:
- **Register ENS Domains**: Owners can register their 5-digit ENS domains.
- **Reward Calculation**: Rewards are calculated based on the staking duration and whether the domain has been a winning node in the lottery.
- **Reward Distribution**: Distributes rewards proportionally to stakers.

#### Functions:
- `setENSAddress(address _ens)`: Set the ENS contract address.
- `setENSResolverAddress(address _resolver)`: Set the ENS Resolver contract address.
- `setLotteryAddress(address _lottery)`: Set the Lottery contract address.
- `isValidENS5DigitDomain(bytes32 node)`: Check if a node is a valid 5-digit ENS domain.
- `registerENS(bytes32 node)`: Register a 5-digit ENS domain.
- `unregisterENS(bytes32 node)`: Unregister a 5-digit ENS domain.
- `calculateReward(bytes32 node)`: Calculate the reward for a staked domain.
- `distributeRewards()`: Distribute rewards to all stakers.
- `claimReward(bytes32 node)`: Claim the reward for a specific domain.
- `addToRewardPool(uint256 amount)`: Add funds to the reward pool.

## Deployment
To deploy the contracts, follow these steps:

1. Deploy the `LOTTOERC20` contract to create the ERC20 token.
2. Deploy the `NFTVault` contract with the addresses of the ENS and ENS Resolver contracts.
3. Deploy the `Lottery` contract with the necessary parameters and the address of the `NFTVault` contract.

## Usage
1. **Buying Tickets**: Users call the `buyTickets` function on the `Lottery` contract with a 5-digit number.
2. **Registering ENS Domains**: ENS domain owners call the `registerENS` function on the `NFTVault` contract with their domain's node.
3. **Drawing Winners**: The `performUpkeep` function on the `Lottery` contract is called periodically to draw winners.
4. **Claiming Rewards**: Stakers can call the `claimReward` function on the `NFTVault` contract to claim their accumulated rewards.

## Security
Both contracts implement `ReentrancyGuard` to prevent reentrancy attacks and `Ownable` to restrict access to critical functions.

## Future Improvements
- Implement additional mechanisms to enhance security.
- Introduce more complex reward structures.
- Add more flexibility in managing the lottery and staking parameters.
