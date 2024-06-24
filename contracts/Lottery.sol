// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./TimeUtils.sol";

contract Lottery is
    Ownable,
    KeeperCompatibleInterface,
    VRFConsumerBaseV2,
    ReentrancyGuard
{
    using TimeUtils for uint256;

    IERC20 public lottoToken;
    mapping(uint256 => mapping(string => uint256)) public ticketCount;
    mapping(uint256 => mapping(string => address)) public ticketOwners;
    uint256 public ticketPrice = 0.001 ether; // Precio inicial de 0.001 ETH
    uint256 public totalTickets;
    uint256 public prizePool;
    uint256 public organizerFeeRate;
    uint256 public lastDrawTime;
    bool public paused = true; // Inicialmente pausado
    bool public prizeLevelsSet = false; // Controla si los niveles de premios están configurados

    uint256 public seriesCount = 185;
    uint256 public fractionCount = 10;

    VRFCoordinatorV2Interface COORDINATOR;
    uint64 s_subscriptionId;
    bytes32 keyHash;
    uint256 public s_requestId;

    struct PrizeLevel {
        uint256 percentage;
        address[] winners;
        uint256 winnerCount;
    }

    PrizeLevel[6] public prizeLevels;
    bytes32[] public winningNodes;

    event TicketPurchased(
        address indexed buyer,
        uint256 series,
        string number,
        uint256 fraction
    );
    event WinnersSelected(address[] winners, uint256[] prizes);
    event Paused(bool isPaused);
    event SeriesUpdated(uint256 newSeriesCount);
    event FractionsUpdated(uint256 newFractionCount);
    event TicketPriceUpdated(uint256 newTicketPrice);
    event PrizeLevelsSet();

    constructor(
        address _lottoToken,
        uint256 _organizerFeeRate,
        address vrfCoordinator,
        bytes32 _keyHash,
        uint64 subscriptionId
    ) Ownable(msg.sender) VRFConsumerBaseV2(vrfCoordinator) {
        lottoToken = IERC20(_lottoToken);
        organizerFeeRate = _organizerFeeRate;
        lastDrawTime = block.timestamp;
        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        keyHash = _keyHash;
        s_subscriptionId = subscriptionId;
    }

    function setPrizeLevels() external onlyOwner {
        require(
            paused,
            "El contrato debe estar pausado para configurar los niveles de premios"
        );

        assembly {
            let ptr := add(prizeLevels.slot, 0)
            sstore(ptr, 4000)
            sstore(add(ptr, 1), 1)
            sstore(add(ptr, 2), 1)

            ptr := add(prizeLevels.slot, 1)
            sstore(ptr, 1250)
            sstore(add(ptr, 1), 1)
            sstore(add(ptr, 2), 1)

            ptr := add(prizeLevels.slot, 2)
            sstore(ptr, 500)
            sstore(add(ptr, 1), 1)
            sstore(add(ptr, 2), 1)

            ptr := add(prizeLevels.slot, 3)
            sstore(ptr, 200)
            sstore(add(ptr, 1), 2)
            sstore(add(ptr, 2), 2)

            ptr := add(prizeLevels.slot, 4)
            sstore(ptr, 60)
            sstore(add(ptr, 1), 8)
            sstore(add(ptr, 2), 8)

            ptr := add(prizeLevels.slot, 5)
            sstore(ptr, 1794)
            sstore(add(ptr, 1), 1794)
            sstore(add(ptr, 2), 1794)
        }

        prizeLevelsSet = true;
        emit PrizeLevelsSet();
    }

    function buyTickets(
        uint256 series,
        string memory number,
        uint256 fraction
    ) external nonReentrant {
        require(!paused, "Sorteo esta pausado");
        require(series < seriesCount, "Numero de series excedido");
        require(bytes(number).length == 5, "Numero no valido");
        require(fraction <= fractionCount, "Fraccion no valida");

        uint256 cost = ticketPrice * fraction;
        require(
            lottoToken.transferFrom(msg.sender, address(this), cost),
            "Pago fallido"
        );

        // Actualizar el contador de boletos
        ticketCount[series][number] += fraction;

        // Registrar el propietario del boleto
        ticketOwners[series][number] = msg.sender;

        // Actualizar totalTickets y prizePool
        totalTickets += fraction;
        prizePool += cost;

        emit TicketPurchased(msg.sender, series, number, fraction);
    }

    function checkUpkeep(
        bytes calldata /* checkData */
    )
        external
        view
        override
        returns (
            bool upkeepNeeded,
            bytes memory /* performData */
        )
    {
        upkeepNeeded = block.timestamp.isTimeForDraw() && !paused;
    }

    function performUpkeep(
        bytes calldata /* performData */
    ) external override {
        if (block.timestamp.isTimeForDraw() && !paused) {
            requestRandomWords();
            lastDrawTime = block.timestamp;
        }
    }

    function requestRandomWords() internal {
        s_requestId = COORDINATOR.requestRandomWords(
            keyHash,
            s_subscriptionId,
            3, // request confirmations
            200000, // callback gas limit
            1 // number of random words
        );
    }

    function fulfillRandomWords(uint256, uint256[] memory randomWords)
        internal
        override
        nonReentrant
    {
        drawWinners(randomWords[0]);
    }

    function drawWinners(uint256 randomSeed) internal nonReentrant {
        require(totalTickets > 0, "No tickets sold");

        uint256 organizerFee = (prizePool * organizerFeeRate) / 10000;
        uint256 totalPrize = prizePool - organizerFee;

        uint256[] memory prizes = new uint256[](prizeLevels.length);

        for (uint256 i = 0; i < prizeLevels.length; i++) {
            prizes[i] = (totalPrize * prizeLevels[i].percentage) / 10000;
            for (uint256 j = 0; j < prizeLevels[i].winnerCount; j++) {
                uint256 winnerIndex = uint256(
                    keccak256(abi.encode(randomSeed, i, j))
                ) % totalTickets;
                uint256 cumulativeTickets = 0;
                bool found = false;

                for (uint256 series = 0; series < seriesCount && !found; series++) {
                    for (uint256 k = 0; k < 100000 && !found; k++) {
                        string memory numStr = uintToStr(k);
                        cumulativeTickets += ticketCount[series][numStr];
                        if (cumulativeTickets > winnerIndex) {
                            address winner = ticketOwners[series][numStr];
                            prizeLevels[i].winners.push(winner);
                            found = true;

                            // Registrar el nodo ganador
                            bytes32 winningNode = keccak256(abi.encodePacked(series, numStr));
                            winningNodes.push(winningNode);
                        }
                    }
                }
            }
        }

        for (uint256 i = 0; i < prizeLevels.length; i++) {
            for (uint256 j = 0; j < prizeLevels[i].winnerCount; j++) {
                require(
                    lottoToken.transfer(
                        prizeLevels[i].winners[j],
                        prizes[i] / prizeLevels[i].winnerCount
                    ),
                    "Prize transfer failed"
                );
            }
        }

        require(
            lottoToken.transfer(owner(), organizerFee),
            "Fee transfer failed"
        );

        emit WinnersSelected(flattenWinners(), prizes);

        // Reset lottery
        totalTickets = 0;
        prizePool = 0;
        for (uint256 i = 0; i < prizeLevels.length; i++) {
            delete prizeLevels[i].winners;
            prizeLevels[i].winners = new address[](prizeLevels[i].winnerCount);
        }
    }

    function getTicketOwner(uint256 series, string memory numStr) internal view returns (address) {
        return ticketOwners[series][numStr];
    }

    function pause(bool _paused) external onlyOwner nonReentrant {
        require(
            prizeLevelsSet,
            "No se puede despausar hasta que los niveles de premios esten configurados"
        );
        paused = _paused;
        emit Paused(paused);
    }

    function setSeriesCount(uint256 newSeriesCount)
        external
        onlyOwner
        nonReentrant
    {
        require(
            paused,
            "Debe pausar el contrato antes de cambiar la configuracion"
        );
        seriesCount = newSeriesCount;
        emit SeriesUpdated(newSeriesCount);
    }

    function setFractionCount(uint256 newFractionCount)
        external
        onlyOwner
        nonReentrant
    {
        require(
            paused,
            "Debe pausar el contrato antes de cambiar la configuracion"
        );
        fractionCount = newFractionCount;
        emit FractionsUpdated(newFractionCount);
    }

    function setTicketPrice(uint256 newTicketPrice)
        external
        onlyOwner
        nonReentrant
    {
        require(
            paused,
            "Debe pausar el contrato antes de cambiar la configuracion"
        );
        ticketPrice = newTicketPrice;
        emit TicketPriceUpdated(newTicketPrice);
    }

    function flattenWinners() internal view returns (address[] memory) {
        uint256 totalWinners = 0;
        for (uint256 i = 0; i < prizeLevels.length; i++) {
            totalWinners += prizeLevels[i].winnerCount;
        }
        address[] memory allWinners = new address[](totalWinners);
        uint256 index = 0;
        for (uint256 i = 0; i < prizeLevels.length; i++) {
            for (uint256 j = 0; j < prizeLevels[i].winnerCount; j++) {
                allWinners[index] = prizeLevels[i].winners[j];
                index++;
            }
        }
        return allWinners;
    }

    function uintToStr(uint256 v) internal pure returns (string memory) {
        bytes32 ret;
        if (v == 0) {
            ret = "00000";
        } else {
            uint256 vCopy = v;
            for (uint256 i = 0; vCopy != 0; i++) {
                ret = bytes32(uint256(ret) / (2**8));
                ret |= bytes32(((vCopy % 10) + 48) * 2**(8 * 31));
                vCopy /= 10;
            }
        }
        return string(abi.encodePacked(ret));
    }

    function isWinningNode(bytes32 node) external view returns (bool) {
        for (uint256 i = 0; i < winningNodes.length; i++) {
            if (winningNodes[i] == node) {
                return true;
            }
        }
        return false;
    }
}
