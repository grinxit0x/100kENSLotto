// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IENS {
    function owner(bytes32 node) external view returns (address);
    function resolver(bytes32 node) external view returns (address);
}

interface IENSResolver {
    function name(bytes32 node) external view returns (string memory);
}

interface ILottery {
    function isWinningNode(bytes32 node) external view returns (bool);
}

contract NFTVault is ReentrancyGuard, Ownable {
    IENS public ens;
    IENSResolver public resolver;
    ILottery public lottery;
    uint256 public rewardPool;

    struct Staker {
        address owner;
        bytes32 node;
        uint256 registeredAt;
        uint256 rewardMultiplier;
        uint256 lastClaimed;
    }

    mapping(bytes32 => Staker) public stakers;
    mapping(address => bytes32[]) public addressToNodes;
    mapping(address => uint256) public totalRewards;
    address[] public stakerAddresses;

    event Staked(address indexed owner, bytes32 indexed node);
    event Unstaked(address indexed owner, bytes32 indexed node);
    event RewardClaimed(address indexed owner, uint256 reward);
    event ENSAddressUpdated(address indexed oldAddress, address indexed newAddress);
    event ENSResolverAddressUpdated(address indexed oldAddress, address indexed newAddress);
    event LotteryAddressUpdated(address indexed oldAddress, address indexed newAddress);

    constructor(address _ens, address _resolver, address _lottery) Ownable(msg.sender) {
        ens = IENS(_ens);
        resolver = IENSResolver(_resolver);
        lottery = ILottery(_lottery);
    }

    function setENSAddress(address _ens) external onlyOwner {
        address oldAddress = address(ens);
        ens = IENS(_ens);
        emit ENSAddressUpdated(oldAddress, _ens);
    }

    function setENSResolverAddress(address _resolver) external onlyOwner {
        address oldAddress = address(resolver);
        resolver = IENSResolver(_resolver);
        emit ENSResolverAddressUpdated(oldAddress, _resolver);
    }

    function setLotteryAddress(address _lottery) external onlyOwner {
        address oldAddress = address(lottery);
        lottery = ILottery(_lottery);
        emit LotteryAddressUpdated(oldAddress, _lottery);
    }

    function isValidENS5DigitDomain(bytes32 node) public view returns (bool) {
        address owner = ens.owner(node);
        if (owner == address(0)) {
            return false;
        }
        string memory name = resolver.name(node);
        if (bytes(name).length != 5) {
            return false;
        }
        for (uint256 i = 0; i < 5; i++) {
            if (bytes(name)[i] < '0' || bytes(name)[i] > '9') {
                return false;
            }
        }
        return true;
    }

    function registerENS(bytes32 node) public nonReentrant {
        require(isValidENS5DigitDomain(node), "Invalid ENS 5-digit domain");
        address owner = ens.owner(node);
        require(owner == msg.sender, "Only the owner can register");

        stakers[node] = Staker({
            owner: msg.sender,
            node: node,
            registeredAt: block.timestamp,
            rewardMultiplier: 1,
            lastClaimed: block.timestamp
        });

        addressToNodes[msg.sender].push(node);
        stakerAddresses.push(msg.sender);

        emit Staked(msg.sender, node);
    }

    function unregisterENS(bytes32 node) public nonReentrant {
        Staker storage staker = stakers[node];
        require(staker.owner == msg.sender, "Only the owner can unregister");

        uint256 reward = calculateReward(node);
        rewardPool -= reward;
        payable(msg.sender).transfer(reward);

        // Remove the node from addressToNodes mapping
        bytes32[] storage nodes = addressToNodes[msg.sender];
        for (uint256 i = 0; i < nodes.length; i++) {
            if (nodes[i] == node) {
                nodes[i] = nodes[nodes.length - 1];
                nodes.pop();
                break;
            }
        }

        delete stakers[node];
        emit Unstaked(msg.sender, node);
    }

    function calculateReward(bytes32 node) public view returns (uint256) {
        Staker storage staker = stakers[node];
        uint256 stakingDuration = block.timestamp - staker.registeredAt;
        uint256 reward = (rewardPool * staker.rewardMultiplier * stakingDuration) / 1e18;

        // Adding a bonus multiplier if the NFT has been a winning NFT
        uint256 bonusMultiplier = 1;
        if (lottery.isWinningNode(node)) {
            bonusMultiplier += 1;
        }

        return reward * bonusMultiplier;
    }

    function distributeRewards() external onlyOwner nonReentrant {
        uint256 totalMultiplier;
        for (uint256 i = 0; i < stakerAddresses.length; i++) {
            address stakerAddress = stakerAddresses[i];
            bytes32[] storage nodes = addressToNodes[stakerAddress];
            for (uint256 j = 0; j < nodes.length; j++) {
                Staker storage staker = stakers[nodes[j]];
                totalMultiplier += staker.rewardMultiplier;
            }
        }

        for (uint256 i = 0; i < stakerAddresses.length; i++) {
            address stakerAddress = stakerAddresses[i];
            bytes32[] storage nodes = addressToNodes[stakerAddress];
            for (uint256 j = 0; j < nodes.length; j++) {
                Staker storage staker = stakers[nodes[j]];
                uint256 reward = (rewardPool * staker.rewardMultiplier) / totalMultiplier;
                payable(stakerAddress).transfer(reward);
                staker.rewardMultiplier = 0;
            }
        }

        rewardPool = 0;
    }

    function claimReward(bytes32 node) public nonReentrant {
        Staker storage staker = stakers[node];
        require(staker.owner == msg.sender, "Only the owner can claim rewards");

        uint256 reward = calculateReward(node);
        require(reward > 0, "No rewards available");

        staker.lastClaimed = block.timestamp;
        rewardPool -= reward;
        totalRewards[msg.sender] += reward;

        emit RewardClaimed(msg.sender, reward);
    }

    function addToRewardPool(uint256 amount) external onlyOwner {
        rewardPool += amount;
    }
}
