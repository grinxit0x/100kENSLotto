// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IENS {
    function owner(bytes32 node) external view returns (address);
    function resolver(bytes32 node) external view returns (address);
}

interface IENSResolver {
    function name(bytes32 node) external view returns (string memory);
}

contract NFTVault {
    IENS public ens;
    IENSResolver public resolver;

    struct Deposit {
        address owner;
        bytes32 node;
    }

    mapping(bytes32 => Deposit) public deposits;

    event DepositMade(address indexed owner, bytes32 indexed node);
    event WithdrawalMade(address indexed owner, bytes32 indexed node);

    constructor(address _ens, address _resolver) {
        ens = IENS(_ens);
        resolver = IENSResolver(_resolver);
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

    function depositENS(bytes32 node) public {
        require(isValidENS5DigitDomain(node), "Invalid ENS 5-digit domain");

        address owner = ens.owner(node);
        require(owner == msg.sender, "Only the owner can deposit");

        assembly {
            // Create a storage pointer for deposits[node]
            let depositSlot := sload(add(deposits.slot, node))

            // Store the deposit details
            sstore(add(depositSlot, 0), caller()) // deposit.owner = msg.sender
            sstore(add(depositSlot, 1), node) // deposit.node = node
        }

        emit DepositMade(msg.sender, node);
    }

    function withdrawENS(bytes32 node) public {
        address owner;
        assembly {
            // Create a storage pointer for deposits[node]
            let depositSlot := sload(add(deposits.slot, node))

            // Load the owner of the deposit
            owner := sload(depositSlot)
        }
        require(owner == msg.sender, "Only the owner can withdraw");

        assembly {
            // Delete the deposit
            sstore(add(deposits.slot, node), 0)
        }

        emit WithdrawalMade(msg.sender, node);
    }
}
