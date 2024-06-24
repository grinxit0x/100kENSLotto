// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract LOTTOERC20 is ERC20, Ownable, ReentrancyGuard {
    uint256 public constant REWARD_RATE = 100; // Example reward rate
    uint256 public constant ORGANIZER_FEE_RATE = 1; // 1% fee for organizers
    uint256 public totalStaked;
    uint256 public rewardPool;

    struct Staker {
        uint256 amount;
        uint256 rewardDebt;
    }

    mapping(address => Staker) public stakers;
    address[] public stakerAddresses;

    event Stake(address indexed user, uint256 amount);
    event Unstake(address indexed user, uint256 amount);
    event ClaimRewards(address indexed user, uint256 reward);

    constructor() ERC20("LOTTO Fraction", "LOTTO") Ownable(msg.sender) {}

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function stake(uint256 amount) external nonReentrant {
        Staker storage staker = stakers[msg.sender];
        uint256 pendingReward;
        
        assembly {
            let stakerAmount := sload(add(staker.slot, 0)) // staker.amount
            let rewardDebt := sload(add(staker.slot, 1)) // staker.rewardDebt
            pendingReward := sub(div(mul(stakerAmount, REWARD_RATE), 10000), rewardDebt)
        }

        if (staker.amount > 0) {
            rewardPool -= pendingReward;
            _transfer(address(this), msg.sender, pendingReward);
            emit ClaimRewards(msg.sender, pendingReward);
        }

        _transfer(msg.sender, address(this), amount);
        staker.amount += amount;
        assembly {
            sstore(add(staker.slot, 1), div(mul(sload(add(staker.slot, 0)), REWARD_RATE), 10000))
        }

        totalStaked += amount;
        stakerAddresses.push(msg.sender); // Add the staker address if it's the first stake
        emit Stake(msg.sender, amount);
    }

    function unstake(uint256 amount) external nonReentrant {
        Staker storage staker = stakers[msg.sender];
        require(staker.amount >= amount, "Insufficient staked amount");

        uint256 pendingReward;
        
        assembly {
            let stakerAmount := sload(add(staker.slot, 0)) // staker.amount
            let rewardDebt := sload(add(staker.slot, 1)) // staker.rewardDebt
            pendingReward := sub(div(mul(stakerAmount, REWARD_RATE), 10000), rewardDebt)
        }

        rewardPool -= pendingReward;
        _transfer(address(this), msg.sender, pendingReward);
        _transfer(address(this), msg.sender, amount);

        staker.amount -= amount;
        assembly {
            sstore(add(staker.slot, 1), div(mul(sload(add(staker.slot, 0)), REWARD_RATE), 10000))
        }

        totalStaked -= amount;
        emit Unstake(msg.sender, amount);
        emit ClaimRewards(msg.sender, pendingReward);
    }

    function addRewards(uint256 amount) external onlyOwner {
        _transfer(msg.sender, address(this), amount);
        
        assembly {
            sstore(rewardPool.slot, add(sload(rewardPool.slot), amount))
        }
    }

    function claimRewards() external nonReentrant {
        Staker storage staker = stakers[msg.sender];
        uint256 pendingReward;
        
        assembly {
            let stakerAmount := sload(add(staker.slot, 0)) // staker.amount
            let rewardDebt := sload(add(staker.slot, 1)) // staker.rewardDebt
            pendingReward := sub(div(mul(stakerAmount, REWARD_RATE), 10000), rewardDebt)
        }

        require(pendingReward > 0, "No rewards to claim");

        assembly {
            sstore(rewardPool.slot, sub(sload(rewardPool.slot), pendingReward))
        }

        _transfer(address(this), msg.sender, pendingReward);
        
        assembly {
            let stakerSlot := add(staker.slot, 0)
            sstore(add(staker.slot, 1), div(mul(sload(stakerSlot), REWARD_RATE), 10000))
        }

        emit ClaimRewards(msg.sender, pendingReward);
    }

    function distributeRewards() external onlyOwner nonReentrant {
        uint256 totalReward;
        uint256 organizerFee;

        assembly {
            let rewardPoolValue := sload(rewardPool.slot)
            totalReward := div(mul(rewardPoolValue, sub(10000, ORGANIZER_FEE_RATE)), 10000)
            organizerFee := sub(rewardPoolValue, totalReward)
        }

        for (uint256 i = 0; i < stakerAddresses.length; i++) {
            address stakerAddress = stakerAddresses[i];
            Staker storage staker = stakers[stakerAddress];
            uint256 reward;

            assembly {
                reward := div(mul(sload(add(staker.slot, 0)), totalReward), sload(totalStaked.slot))
                sstore(add(staker.slot, 1), add(sload(add(staker.slot, 1)), reward))
            }

            _transfer(address(this), stakerAddress, reward);
        }

        _transfer(address(this), owner(), organizerFee);

        assembly {
            sstore(rewardPool.slot, 0)
        }
    }
}
