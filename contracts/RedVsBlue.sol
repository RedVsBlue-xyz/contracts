
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract RedVsBlue {
    uint256 public constant GAME_DURATION = 30 minutes;
    uint256 public gameEndTime;
    uint256 public currentRound = 1;

    //events
    event RoundEnded(uint256 roundNumber, RoundState result, uint256 totalRed, uint256 totalBlue);
    event Contribution(address indexed user, uint256 amount, bool isRed);

    enum RoundState {
        None,
        RedWins,
        BlueWins,
        Draw
    }

    struct Round {
        mapping(address => uint256) redContributions;
        mapping(address => uint256) blueContributions;
        uint256 totalRed;
        uint256 totalBlue;
        bool ended;
        RoundState result;
    }

    mapping(uint256 => Round) public rounds;

    modifier canContributeRound() {
        require(block.timestamp < gameEndTime, "Contribution time has ended");
        require(!rounds[currentRound].ended, "Current round has ended");
        _;
    }

    modifier canEndRound() {
        require(block.timestamp >= gameEndTime, "Round cannot be ended yet");
        require(!rounds[currentRound].ended, "Current round already ended");
        _;
    }

    modifier isRoundOver(uint roundNumber) {
        require(rounds[roundNumber].ended, "Round not ended yet");
        _;
    }

    constructor() {
        gameEndTime = block.timestamp + GAME_DURATION;
    }

    function contributeToRed() external payable canContributeRound {
        Round storage round = rounds[currentRound];
        round.redContributions[msg.sender] += msg.value;
        round.totalRed += msg.value;
    }

    function contributeToBlue() external payable canContributeRound {
        Round storage round = rounds[currentRound];
        round.blueContributions[msg.sender] += msg.value;
        round.totalBlue += msg.value;
    }

    function endRound() external canEndRound {
        Round storage round = rounds[currentRound];
        round.ended = true;
        round.result = round.totalRed > round.totalBlue ? RoundState.RedWins : (round.totalBlue > round.totalRed ? RoundState.BlueWins : RoundState.Draw);

        //start new round
        currentRound++;
        gameEndTime = block.timestamp + GAME_DURATION;
    }

    function claimReward(uint256 roundNumber) isRoundOver(roundNumber) external {
        //require(rounds[roundNumber].ended, "Round not ended yet");
        Round storage round = rounds[roundNumber];

        uint256 userContribution;
        uint256 totalPot = round.result == RoundState.Draw ? round.totalRed + round.totalBlue : (round.result == RoundState.RedWins ? round.totalRed : round.totalBlue);
        if (round.result == RoundState.RedWins) { // Red wins
            userContribution = round.redContributions[msg.sender];
            round.redContributions[msg.sender] = 0;
        } else { // Blue wins
            userContribution = round.blueContributions[msg.sender];
            round.blueContributions[msg.sender] = 0;
        }

        if (userContribution > 0) {
            uint256 reward = (userContribution / (round.result == RoundState.RedWins ? round.totalRed : round.totalBlue)) * totalPot;
            payable(msg.sender).transfer(reward);
        }
    }

    function rewards(uint256 roundNumber, address user) external view returns (uint256) {
        Round storage round = rounds[roundNumber];
        if (!round.ended) {
            return 0; // No rewards if the round hasn't ended
        }

        uint256 userContribution;
        uint256 totalPot = round.totalRed + round.totalBlue;
        if (round.result == RoundState.RedWins) { // Red wins
            userContribution = round.redContributions[user];
        } else if (round.result == RoundState.BlueWins) { // Blue wins
            userContribution = round.blueContributions[user];
        }

        if (userContribution > 0) {
            return (userContribution / (round.result == RoundState.RedWins ? round.totalRed : round.totalBlue)) * totalPot;
        } else {
            return 0;
        }
    }
}
