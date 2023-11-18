
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
    uint256 public constant GAME_DURATION = 5 minutes;

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
        BlueWins,
        NoContest
    }

    struct VrfRequestStatus {
        uint requestId;
        uint256 paid; // amount paid in link
        uint256[] randomWords;
    }

    struct Round {
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
    mapping(uint256 => mapping(address => uint256)) public redContributions;
    mapping(uint256 => mapping(address => uint256)) public blueContributions;

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
 
    function contributeToRed() external payable canContributeRound {
        Round storage round = rounds[currentRound];
        redContributions[currentRound][msg.sender] += msg.value;
        round.totalRed += msg.value;
        emit Contribution(msg.sender, msg.value, true);
    }

    function contributeToBlue() external payable canContributeRound {
        Round storage round = rounds[currentRound];
        blueContributions[currentRound][msg.sender] += msg.value;
        round.totalBlue += msg.value;
        emit Contribution(msg.sender, msg.value, false);
    }

    function endRound() external canEndRound {
        Round storage round = rounds[currentRound];
        round.status = RoundState.FetchingRandomNumber;

        //send fee to protocol fee destination
        uint256 fee = (round.totalRed + round.totalBlue) * protocolFee / 1 ether;

        if (fee > 0) {
            (bool success, ) = payable(protocolFeeDestination).call{value: fee}("");
            require(success, "Transfer failed.");
        }

        //make sure round has contributions
        if (round.totalRed == 0 || round.totalBlue == 0){
            round.ended = true;
            round.status = RoundState.NoContest;
            emit RoundEnded(currentRound, round.status, round.totalRed, round.totalBlue);
            _startNewRound();
            return;
        }

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

        if (round.status == RoundState.NoContest) {
            uint256 totalUserContributions = redContributions[roundNumber][user] + blueContributions[roundNumber][user];
            return totalUserContributions - ((totalUserContributions * protocolFee) / 1 ether);
        }

        uint256 share;
        uint256 totalPot = round.totalRed + round.totalBlue;
        uint256 totalPotAfterFee = totalPot - ((totalPot * protocolFee) / 1 ether);
        if (round.status == RoundState.RedWins) { // Red wins
            share = redContributions[roundNumber][user] * 1 ether / round.totalRed;
        } else if (round.status == RoundState.BlueWins) { // Blue wins
            share = blueContributions[roundNumber][user] * 1 ether / round.totalBlue;
        } 

        if (share > 0) {
            return (share * totalPotAfterFee) / 1 ether;
        } else {
            return 0;
        }
    }

    function viewTotalRewards(address user) public view returns (uint256) {
        uint256 totalRewards = 0;
        for (uint256 index = 0; index < currentRound; index++) {
            totalRewards += rewards(index, user);
        }
        return totalRewards;
    }

    function claimReward(uint256 roundNumber) isRoundOver(roundNumber) external {
        //require(rounds[roundNumber].ended, "Round not ended yet");
        Round storage round = rounds[roundNumber];

        uint256 claimableAmount = rewards(roundNumber, msg.sender);
        require(claimableAmount > 0, "No rewards to claim");

        redContributions[roundNumber][msg.sender] = 0;
        blueContributions[roundNumber][msg.sender] = 0;

        //payable(msg.sender).transfer(claimableAmount);
        //use call instead
        (bool success, ) = payable(msg.sender).call{value: claimableAmount}("");
        require(success, "Transfer failed.");
    }

    function claimRewardsFromRounds(uint256[] calldata roundNumbers) external {
        uint256 totalRewards = 0;
        for (uint256 index = 0; index < roundNumbers.length; index++) {
            uint256 roundNumber = roundNumbers[index];
            totalRewards += rewards(roundNumber, msg.sender);
            Round storage round = rounds[roundNumber];
            redContributions[roundNumber][msg.sender] = 0;
            blueContributions[roundNumber][msg.sender] = 0;

        }
        (bool success, ) = payable(msg.sender).call{value: totalRewards}("");
        require(success, "Transfer failed.");
    } 



    function withdrawLink() public onlyOwner {
        LinkTokenInterface link = LinkTokenInterface(linkAddress);
        require(
            link.transfer(msg.sender, link.balanceOf(address(this))),
            "Unable to transfer"
        );
    }

    
}
