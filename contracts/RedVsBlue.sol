
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import "@chainlink/contracts/src/v0.8/vrf/VRFV2WrapperConsumerBase.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract RedVsBlue is VRFV2WrapperConsumerBase {

    //Protocol constants
    uint256 public constant protocolFee = 0.02 ether; // 2%
    uint256 public constant GAME_DURATION = 30 minutes;

    //Chainlink VRF constants
    uint32 callbackGasLimit = 100000;
    uint16 requestConfirmations = 3;
    uint32 numWords = 1;
    address linkAddress = 0xd14838A68E8AFBAdE5efb411d5871ea0011AFd28;
    address wrapperAddress = 0x674Cda1Fef7b3aA28c535693D658B42424bb7dBD;


    //events
    event FetchingRandomNumber(uint256 roundNumber);
    event RandomNumberReceived(uint256 roundNumber, uint256 randomNumber);
    event RoundStarted(uint256 roundNumber, uint256 startTime, uint256 endTime);
    event RoundEnded(uint256 roundNumber, RoundState status, uint256 totalRed, uint256 totalBlue);
    event Contribution(address indexed user, uint256 amount, bool isRed);

    enum RoundState {
        None,
        Open,
        FetchingRandomNumber, // Fetching random words
        RedWins,
        BlueWins
    }

    struct VrfRequestStatus {
        uint requestId;
        uint256 paid; // amount paid in link
        uint256[] randomWords;
    }

    struct Round {
        mapping(address => uint256) redContributions;
        mapping(address => uint256) blueContributions;
        uint256 totalRed;
        uint256 totalBlue;
        bool ended;
        RoundState status;
        VrfRequestStatus vrfRequestStatus;
    }

    //dApp state variables
    address public protocolFeeDestination;
    uint256 public gameEndTime;
    uint256 public currentRound = 0;
    mapping(uint256 => Round) public rounds;

    modifier canContributeRound() {
        require(block.timestamp < gameEndTime, "Contribution time has ended");
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
        VRFV2WrapperConsumerBase(linkAddress, wrapperAddress)
    {
        protocolFeeDestination = msg.sender;
        _startNewRound();
    }
 
    function contributeToRed() external payable canContributeRound {
        Round storage round = rounds[currentRound];
        round.redContributions[msg.sender] += msg.value;
        round.totalRed += msg.value;
        emit Contribution(msg.sender, msg.value, true);
    }

    function contributeToBlue() external payable canContributeRound {
        Round storage round = rounds[currentRound];
        round.blueContributions[msg.sender] += msg.value;
        round.totalBlue += msg.value;
        emit Contribution(msg.sender, msg.value, false);
    }

    function endRound() external canEndRound {
        Round storage round = rounds[currentRound];
        round.status = RoundState.FetchingRandomNumber;

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
        //round.status = RoundState.RandomNumberReceived;

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
        uint256 totalContributions = round.totalRed + round.totalBlue;
        // Calculate the probability ratio
        uint256 redChance = (round.totalRed * 100) / totalContributions;
        uint256 randomThreshold = randomNumber % 100;

        if (randomThreshold < redChance) {
            round.status = RoundState.RedWins;
        } else {
            round.status = RoundState.BlueWins;
        }

        emit RoundEnded(currentRound, round.status, round.totalRed, round.totalBlue);
    }

    function _startNewRound() private {
        currentRound++;
        gameEndTime = block.timestamp + GAME_DURATION;
        rounds[currentRound].status = RoundState.Open;
        emit RoundStarted(currentRound, block.timestamp, gameEndTime);
    }

    function rewards(uint256 roundNumber, address user) public view returns (uint256) {
        Round storage round = rounds[roundNumber];
        if (!round.ended) {
            return 0; // No rewards if the round hasn't ended
        }

        uint256 userContribution;
        uint256 totalPot = round.totalRed + round.totalBlue;
        if (round.status == RoundState.RedWins) { // Red wins
            userContribution = round.redContributions[user];
        } else if (round.status == RoundState.BlueWins) { // Blue wins
            userContribution = round.blueContributions[user];
        }

        if (userContribution > 0) {
            return (userContribution / (round.status == RoundState.RedWins ? round.totalRed : round.totalBlue)) * totalPot;
        } else {
            return 0;
        }
    }

    function claimReward(uint256 roundNumber) isRoundOver(roundNumber) external {
        //require(rounds[roundNumber].ended, "Round not ended yet");
        Round storage round = rounds[roundNumber];

        uint256 claimableAmount = rewards(roundNumber, msg.sender);
        require(claimableAmount > 0, "No rewards to claim");

        if (round.status == RoundState.RedWins) {
            round.redContributions[msg.sender] = 0;
        } else if (round.status == RoundState.BlueWins) {
            round.blueContributions[msg.sender] = 0;
        }

        //payable(msg.sender).transfer(claimableAmount);
        //use call instead
        (bool success, ) = payable(msg.sender).call{value: claimableAmount}("");
        require(success, "Transfer failed.");
    }

    
}
