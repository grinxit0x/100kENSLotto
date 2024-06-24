// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface ILottoToken {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract StakingVault is Ownable, ReentrancyGuard {
    struct Staker {
        uint256 amount;
        uint256 rewardDebt;
        uint256 lastStakedTime;
    }

    mapping(address => Staker) public stakers;
    address[] public stakerAddresses;

    ILottoToken public lottoToken;
    uint256 public totalStaked;
    uint256 public rewardPool;
    uint256 public rewardRate;
    uint256 public organizerFeeRate;

    event Stake(address indexed user, uint256 amount);
    event Unstake(address indexed user, uint256 amount);
    event ClaimRewards(address indexed user, uint256 reward);
    event RewardsDistributed(uint256 rewardPool, uint256 ownerShare);

    constructor(address _lottoToken, uint256 _rewardRate, uint256 _organizerFeeRate) Ownable(msg.sender) {
        lottoToken = ILottoToken(_lottoToken);
        rewardRate = _rewardRate;
        organizerFeeRate = _organizerFeeRate;
    }

    function stake(uint256 amount) external nonReentrant {
        Staker storage staker = stakers[msg.sender];

        if (staker.amount > 0) {
            uint256 pendingReward = (staker.amount * rewardRate * (block.timestamp - staker.lastStakedTime)) / 1e18;
            staker.rewardDebt += pendingReward;
            rewardPool -= pendingReward;
            lottoToken.transfer(msg.sender, pendingReward);
            emit ClaimRewards(msg.sender, pendingReward);
        }

        lottoToken.transferFrom(msg.sender, address(this), amount);
        staker.amount += amount;
        staker.lastStakedTime = block.timestamp;
        totalStaked += amount;
        stakerAddresses.push(msg.sender);

        emit Stake(msg.sender, amount);
    }

    function unstake(uint256 amount) external nonReentrant {
        Staker storage staker = stakers[msg.sender];
        require(staker.amount >= amount, "Insufficient staked amount");

        uint256 pendingReward = (staker.amount * rewardRate * (block.timestamp - staker.lastStakedTime)) / 1e18;
        staker.rewardDebt += pendingReward;
        rewardPool -= pendingReward;

        staker.amount -= amount;
        totalStaked -= amount;
        lottoToken.transfer(msg.sender, amount);
        lottoToken.transfer(msg.sender, staker.rewardDebt);

        emit Unstake(msg.sender, amount);
        emit ClaimRewards(msg.sender, staker.rewardDebt);
        staker.rewardDebt = 0;
    }

    function distributeRewards() external onlyOwner {
        uint256 ownerShare = (rewardPool * organizerFeeRate) / 100;
        uint256 distributeAmount = rewardPool - ownerShare;

        for (uint256 i = 0; i < stakerAddresses.length; i++) {
            address stakerAddress = stakerAddresses[i];
            Staker storage staker = stakers[stakerAddress];

            uint256 stakerReward = (distributeAmount * staker.amount) / totalStaked;
            lottoToken.transfer(stakerAddress, stakerReward);
        }

        lottoToken.transfer(owner(), ownerShare);
        rewardPool = 0;

        emit RewardsDistributed(distributeAmount, ownerShare);
    }
}
