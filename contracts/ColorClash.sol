
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import "@chainlink/contracts/src/v0.8/vrf/VRFV2WrapperConsumerBase.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract RedVsBlue is 
    Ownable,
    VRFV2WrapperConsumerBase
{

    //Protocol constants
    uint256 public constant protocolFee = 0.02 ether; // 2%
    uint256 public constant deductionFee = 0.1 ether; // 10%
    uint256 public constant GAME_DURATION = 5 minutes;

    //Chainlink VRF constants
    uint32 callbackGasLimit = 100000;
    uint16 requestConfirmations = 3;
    uint32 numWords = 1;
    address linkAddress = 0xd14838A68E8AFBAdE5efb411d5871ea0011AFd28;
    address wrapperAddress = 0x674Cda1Fef7b3aA28c535693D658B42424bb7dBD;

    //Colors of the rainbow
    enum ColorTypes {
        Red,
        Orange,
        Yellow,
        Green,
        Blue,
        Indigo,
        Violet
    }

    enum RoundState {
        None, // Round has not started
        Open, // Round is open for contributions
        FetchingRandomNumber, // Fetching random words
        Finished, // Random words received and winner determined
        NoContest // No color has any contributions
    }

    struct VrfRequestStatus {
        uint requestId;
        uint256 paid; // amount paid in link
        uint256[] randomWords;
    }

    struct Round {
        bool ended;
        RoundState status;
        VrfRequestStatus vrfRequestStatus;
    }

    struct Color {
        uint256 value;
        uint256 supply;
    }

    //events
    event FetchingRandomNumber(uint256 roundNumber);
    event RandomNumberReceived(uint256 roundNumber, uint256 randomNumber);
    event RoundStarted(uint256 roundNumber, uint256 startTime, uint256 endTime);
    event RoundColorDeduction(uint256 roundNumber, ColorTypes color, uint256 deduction);
    event RoundEnded(uint256 roundNumber, RoundState status, ColorTypes winner, uint256 reward);
    event Trade(address trader, ColorTypes color, bool isBuy, uint256 shareAmount, uint256 ethAmount, uint256 protocolEthAmount, uint256 supply);

    //dApp state variables
    address public protocolFeeDestination;
    uint256 public gameEndTime;
    uint256 public currentRound = 0;
    uint256 public totalValueDeposited;
    mapping(uint256 => Round) public rounds;
    mapping(ColorTypes => Color) public colors;
    mapping(ColorsTypes => mapping(address => uint256)) public colorSharesBalance;

    modifier canContributeRound() {
        require(block.timestamp < gameEndTime, "Contribution time has ended");
        require(rounds[currentRound].status == RoundState.Open, "Round not open yet");
        require(!rounds[currentRound].ended, "Current round has ended");
        _;
    }

    modifier canEndRound() {
        require(block.timestamp >= gameEndTime, "Round cannot be ended yet");
        require(rounds[currentRound].status == RoundState.Open, "Round not open yet");
        require(!rounds[currentRound].ended, "Current round already ended");
        _;
    }

    modifier isRoundOver(uint roundNumber) {
        require(rounds[roundNumber].ended, "Round not ended yet");
        _;
    }

    constructor() 
        Ownable(msg.sender)
        VRFV2WrapperConsumerBase(linkAddress, wrapperAddress)
    {
        protocolFeeDestination = msg.sender;
        _startNewRound();
    }

    function getPrice(uint256 supply, uint256 amount) public pure returns (uint256) {
        uint256 sum1 = supply == 0 ? 0 : (supply - 1 )* (supply) * (2 * (supply - 1) + 1) / 6;
        uint256 sum2 = supply == 0 && amount == 1 ? 0 : (supply - 1 + amount) * (supply + amount) * (2 * (supply - 1 + amount) + 1) / 6;
        uint256 summation = sum2 - sum1;
        return summation * 1 ether / 16000;
    }

    function getScalingFactor(ColorTypes color) public view returns (uint256) {
        uint256 xf = colors[color].supply-1;
        uint256 originalValue = getPrice(1, xf <= 0 ? 0 : xf);
        uint256 scalingFactor = colors[color].value / originalValue;
        return scalingFactor == 0 ? 1 ether : scalingFactor;
    }

    function getAdjustedPrice(uint256 supply, uint256 amount, uint256 scalingFactor) public pure returns (uint256) {
        uint256 price = getPrice(supply, amount);
        return (price * scalingFactor) / 1 ether;
    }

    function getBuyPrice(ColorTypes color, uint256 amount) public view returns (uint256) {
        uint256 scalingFactor = getScalingFactor(bubbleAddress);
        return getAdjustedPrice(colors[color].supply, amount, scalingFactor);
    }

    function getSellPrice(ColorTypes color, uint256 amount) public view returns (uint256) {
        uint256 scalingFactor = getScalingFactor(bubbleAddress);
        return getAdjustedPrice(colors[color].supply - amount, amount, scalingFactor);
    }

    function getBuyPriceAfterFee(ColorTypes color, uint256 amount) public view returns (uint256) {
        uint256 price = getBuyPrice(bubbleAddress, amount);
        uint256 protocolFee = price * protocolFeePercent / 1 ether;
        return price + protocolFee;
    }

    function getSellPriceAfterFee(address bubbleAddress, uint256 amount) public view returns (uint256) {
        uint256 price = getSellPrice(bubbleAddress, amount);
        uint256 protocolFee = price * protocolFeePercent / 1 ether;
        return price - protocolFee;
    }

    function buyShares(ColorTypes color, uint256 amount) public payable canTrade(bubbleTier[bubbleAddress]) {
        uint256 supply = colors[color].supply;
        uint256 price = getBuyPrice(color, amount);
        uint256 protocolFee = price * protocolFeePercent / 1 ether;
        require(msg.value >= price + protocolFee, "Insufficient payment");
        colorSharesBalance[colors][msg.sender] = colorSharesBalance[color][msg.sender] + amount;
        colors[colors].supply = supply + amount;
        colors[colors].value = colors[colors].value + price;
        totalValueDeposited = totalValueDeposited + price;
        emit Trade(msg.sender, color, true, amount, price, protocolFee, supply + amount);
        (bool success1, ) = protocolFeeDestination.call{value: protocolFee}("");
        require(success1, "Unable to send funds");
    }

    function sellShares(ColorTypes color, uint256 amount) public payable canTrade(bubbleTier[bubbleAddress]) {
        uint256 supply = colors[color].supply;
        require(supply > amount, "Cannot sell the last share");
        uint256 price = getSellPrice(color, amount);
        uint256 protocolFee = price * protocolFeePercent / 1 ether;
        require(colorSharesBalance[color][msg.sender] >= amount, "Insufficient shares");
        colorSharesBalance[color][msg.sender] = colorSharesBalance[color][msg.sender] - amount;
        colors[color].supply = supply - amount;
        colors[color].value = colors[color].value - price;
        totalValueDeposited = totalValueDeposited - price;
        emit Trade(msg.sender, color, false, amount, price, protocolFee, supply - amount);
        (bool success1, ) = msg.sender.call{value: price - protocolFee}("");
        (bool success2, ) = protocolFeeDestination.call{value: protocolFee}("");
        require(success1 && success2, "Unable to send funds");
    }

    function endRound() external canEndRound {
        Round storage round = rounds[currentRound];
        round.status = RoundState.FetchingRandomNumber;

        //Confirm at least two colors have contributions
        uint256 contributingColors = 0;
        for (uint256 index = 0; index < ColorTypes.length; index++) {
            ColorTypes colorType = ColorTypes(index);
            Color memory color = colors[colorType];

            if (color.value > 0) {
                contributingColors++;
            }
        }
        if (contributingColors == 0) {
            round.status = RoundState.NoContest;
            round.ended = true;
            emit RoundEnded(currentRound, round.status, ColorTypes.None);
            _startNewRound();
            return;
        }


        //Fetch random number
        uint requestId = requestRandomness(
            callbackGasLimit,
            requestConfirmations,
            numWords
        );
        round.vrfRequestStatus = VrfRequestStatus({
            requestId: requestId,
            paid: VRF_V2_WRAPPER.calculateRequestPrice(callbackGasLimit),
            randomWords: new uint256[](numWords)
        });
        emit FetchingRandomNumber(currentRound);
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        Round storage round = rounds[currentRound];
        require(round.vrfRequestStatus.paid > 0, "Request not found");
        require(round.vrfRequestStatus.requestId == _requestId, "Request ID mismatch");
        round.vrfRequestStatus.randomWords = _randomWords;

        uint256 accumulatedValue = 0;
        uint256 reward = 0;
        for (uint256 index = 0; index < ColorTypes.length; index++) {
            ColorTypes colorType = ColorTypes(index);
            Color memory color = colors[colorType];
            accumulatedValue += color.value;

            if (accumulatedValue > randomThreshold) {
                round.status = RoundState.Finished;
                round.winner = colorType;
                continue;
            }

            //deduct 10% of the value from the color
            uint256 deduction = color.value * deductionFee / 1 ether;
            colors[colorType].value = color.value - deduction;
            reward += deduction;
            emit RoundColorDeduction(currentRound, colorType, deduction);
        }

        //pay the winner
        colors[round.winner].value += reward;

        emit RandomNumberReceived(currentRound, _randomWords[0]);

        _determineWinner();
        _startNewRound();
    }

    //determin winner function, called by fulfillRandomWords takes in the random number and determines the winner
    //sets the round status and ended to true
    //uses the random number to determine the winner based on the size of red contributions and blue contributions, bigger the contribution the bigger the chance of winning
    function _determineWinner() private {
        Round storage round = rounds[currentRound];
        uint256 randomNumber = round.vrfRequestStatus.randomWords[0];
        round.ended = true;
        uint256 randomThreshold = randomNumber % totalValueDeposited;

        

        emit RoundEnded(currentRound, round.status, ColorTypes.None);
    }

    function _startNewRound() private {
        currentRound++;
        gameEndTime = block.timestamp + GAME_DURATION;
        rounds[currentRound].status = RoundState.Open;
        emit RoundStarted(currentRound, block.timestamp, gameEndTime);
    }

    function withdrawLink() public onlyOwner {
        LinkTokenInterface link = LinkTokenInterface(linkAddress);
        require(
            link.transfer(msg.sender, link.balanceOf(address(this))),
            "Unable to transfer"
        );
    }

    
}
