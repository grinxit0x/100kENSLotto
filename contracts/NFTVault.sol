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

    struct Deposit {
        address owner;
        bytes32 node;
        uint256 depositedAt;
        uint256 rewardMultiplier;
        uint256 lastClaimed;
    }

    mapping(bytes32 => Deposit) public deposits;
    mapping(address => bytes32[]) public addressToNodes;
    mapping(address => uint256) public totalRewards;
    address[] public stakerAddresses;

    event DepositMade(address indexed owner, bytes32 indexed node);
    event WithdrawalMade(address indexed owner, bytes32 indexed node);
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

    function depositENS(bytes32 node) public nonReentrant {
        require(isValidENS5DigitDomain(node), "Invalid ENS 5-digit domain");
        address owner = ens.owner(node);
        require(owner == msg.sender, "Only the owner can deposit");

        deposits[node] = Deposit({
            owner: msg.sender,
            node: node,
            depositedAt: block.timestamp,
            rewardMultiplier: 1,
            lastClaimed: block.timestamp
        });

        addressToNodes[msg.sender].push(node);
        stakerAddresses.push(msg.sender);

        emit DepositMade(msg.sender, node);
    }

    function withdrawENS(bytes32 node) public nonReentrant {
        Deposit storage deposit = deposits[node];
        require(deposit.owner == msg.sender, "Only the owner can withdraw");

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

        delete deposits[node];
        emit WithdrawalMade(msg.sender, node);
    }

    function calculateReward(bytes32 node) public view returns (uint256) {
        Deposit storage deposit = deposits[node];
        uint256 stakingDuration = block.timestamp - deposit.depositedAt;
        uint256 reward = (rewardPool * deposit.rewardMultiplier * stakingDuration) / 1e18;

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
                Deposit storage deposit = deposits[nodes[j]];
                totalMultiplier += deposit.rewardMultiplier;
            }
        }

        for (uint256 i = 0; i < stakerAddresses.length; i++) {
            address stakerAddress = stakerAddresses[i];
            bytes32[] storage nodes = addressToNodes[stakerAddress];
            for (uint256 j = 0; j < nodes.length; j++) {
                Deposit storage deposit = deposits[nodes[j]];
                uint256 reward = (rewardPool * deposit.rewardMultiplier) / totalMultiplier;
                payable(stakerAddress).transfer(reward);
                deposit.rewardMultiplier = 0;
            }
        }

        rewardPool = 0;
    }

    function claimReward(bytes32 node) public nonReentrant {
        Deposit storage deposit = deposits[node];
        require(deposit.owner == msg.sender, "Only the owner can claim rewards");

        uint256 reward = calculateReward(node);
        require(reward > 0, "No rewards available");

        deposit.lastClaimed = block.timestamp;
        rewardPool -= reward;
        totalRewards[msg.sender] += reward;

        emit RewardClaimed(msg.sender, reward);
    }
}
