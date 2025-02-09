// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;



contract Dystera {
    struct Scenario {
        uint256 id;
        uint256 startTime;
        uint256 endTime;
        bool resolved;
        string outcome;
        uint256 totalPool;
        mapping(string => uint256) predictionVotes;
        mapping(string => uint256) interferenceAmounts;
        address[] bettors;
        address[] interferers;
        string[] predictions;
    }
    
    struct Bet {
        address bettor;
        uint256 amount;
        string prediction;
        bool claimed;
    }

    struct Interference {
        address interferer;
        uint256 amount;
        string prediction;
        bool claimed;
    }

    struct ScenarioView {
        uint256 id;
        uint256 startTime;
        uint256 endTime;
        bool resolved;
        string outcome;
        uint256 totalPool;
    }

    mapping(uint256 => Scenario) public scenarios;
    mapping(uint256 => mapping(address => Bet)) public bets;
    mapping(uint256 => mapping(address => Interference)) public interferences;
    mapping(uint256 => uint256) public scenarioPools;
    mapping(uint256 => uint256) public interferancePools;

    event ScenarioCreated(uint256 indexed scenarioId, uint256 startTime, uint256 endTime);
    event BetPlaced(uint256 indexed scenarioId, address indexed bettor, uint256 amount, string prediction);
    event InterferenceAdded(uint256 indexed scenarioId, address indexed interferer, uint256 amount, string prediction);
    event ScenarioResolved(uint256 indexed scenarioId, string outcome);
    event WinningsClaimed(uint256 indexed scenarioId, address indexed bettor, uint256 amount);
    event InterferenceWinningsClaimed(uint256 indexed scenarioId, address indexed interferer, uint256 amount);

    function placeBet(uint256 _scenarioId, string memory _prediction) external payable   {
        require(msg.value > 0, "Bet amount must be greater than 0");
        require(!scenarios[_scenarioId].resolved, "Scenario already resolved");
        require(block.timestamp < scenarios[_scenarioId].endTime, "Betting period ended");

        Scenario storage scenario = scenarios[_scenarioId];
        
        // If this is a new prediction, add it to the predictions array
        if (!isPredictionExists(_scenarioId, _prediction)) {
            scenario.predictions.push(_prediction);
        }

        // If this is a new bettor, add them to the bettors array
        if (bets[_scenarioId][msg.sender].bettor == address(0)) {
            scenario.bettors.push(msg.sender);
        }

        bets[_scenarioId][msg.sender] = Bet({
            bettor: msg.sender,
            amount: msg.value,
            prediction: _prediction,
            claimed: false
        });

        scenario.predictionVotes[_prediction] += 1;
        scenarioPools[_scenarioId] += msg.value;
        scenario.totalPool += msg.value;

        emit BetPlaced(_scenarioId, msg.sender, msg.value, _prediction);
    }

    function interfere(uint256 _scenarioId, string memory _prediction) external payable   {
        require(msg.value > 0, "Interference amount must be greater than 0");
        require(!scenarios[_scenarioId].resolved, "Scenario already resolved");
        require(block.timestamp < scenarios[_scenarioId].endTime, "Betting period ended");
        require(msg.value >= getMinimumBetAmount(_scenarioId), "Interference amount must be >= minimum bet");

        Scenario storage scenario = scenarios[_scenarioId];

        // If this is a new prediction, add it to the predictions array
        if (!isPredictionExists(_scenarioId, _prediction)) {
            scenario.predictions.push(_prediction);
        }

        // If this is a new interferer, add them to the interferers array
        if (interferences[_scenarioId][msg.sender].interferer == address(0)) {
            scenario.interferers.push(msg.sender);
        }

        interferences[_scenarioId][msg.sender] = Interference({
            interferer: msg.sender,
            amount: msg.value,
            prediction: _prediction,
            claimed: false
        });

        scenario.interferenceAmounts[_prediction] += msg.value;
        interferancePools[_scenarioId] += msg.value;

        emit InterferenceAdded(_scenarioId, msg.sender, msg.value, _prediction);
    }

    function resolveScenario(uint256 _scenarioId) external {
        require(!scenarios[_scenarioId].resolved, "Scenario already resolved");
        require(block.timestamp >= scenarios[_scenarioId].endTime, "Betting period not ended");

        string memory winningPrediction = determineWinner(_scenarioId);
        scenarios[_scenarioId].resolved = true;
        scenarios[_scenarioId].outcome = winningPrediction;

        emit ScenarioResolved(_scenarioId, winningPrediction);
    }

    function determineWinner(uint256 _scenarioId) internal view returns (string memory) {
        Scenario storage scenario = scenarios[_scenarioId];
        
        // If there are interferences, choose the prediction with highest interference amount
        if (interferancePools[_scenarioId] > 0) {
            string memory maxPrediction;
            uint256 maxAmount = 0;
            
            // Iterate through all predictions to find the one with highest interference
            for (uint i = 0; i < scenario.predictions.length; i++) {
                string memory prediction = scenario.predictions[i];
                if (scenario.interferenceAmounts[prediction] > maxAmount) {
                    maxAmount = scenario.interferenceAmounts[prediction];
                    maxPrediction = prediction;
                }
            }
            return maxPrediction;
        }
        
        // If no interference, choose the prediction with most votes
        string memory mostVotedPrediction;
        uint256 maxVotes = 0;
        
        for (uint i = 0; i < scenario.predictions.length; i++) {
            string memory prediction = scenario.predictions[i];
            if (scenario.predictionVotes[prediction] > maxVotes) {
                maxVotes = scenario.predictionVotes[prediction];
                mostVotedPrediction = prediction;
            }
        }
        return mostVotedPrediction;
    }

    function claimWinnings(uint256 _scenarioId) external   {
        require(scenarios[_scenarioId].resolved, "Scenario not resolved");
        Bet storage bet = bets[_scenarioId][msg.sender];
        require(!bet.claimed, "Winnings already claimed");
        require(keccak256(abi.encodePacked(bet.prediction)) == 
                keccak256(abi.encodePacked(scenarios[_scenarioId].outcome)), "Incorrect prediction");

        bet.claimed = true;
        uint256 winnings = calculateWinnings(_scenarioId, msg.sender);
        payable(msg.sender).transfer(winnings);

        emit WinningsClaimed(_scenarioId, msg.sender, winnings);
    }

    function claimInterferenceWinnings(uint256 _scenarioId) external   {
        require(scenarios[_scenarioId].resolved, "Scenario not resolved");
        Interference storage interference = interferences[_scenarioId][msg.sender];
        require(!interference.claimed, "Interference winnings already claimed");
        require(keccak256(abi.encodePacked(interference.prediction)) == 
                keccak256(abi.encodePacked(scenarios[_scenarioId].outcome)), "Incorrect prediction");

        interference.claimed = true;
        uint256 winnings = calculateInterferenceWinnings(_scenarioId, msg.sender);
        payable(msg.sender).transfer(winnings);

        emit InterferenceWinningsClaimed(_scenarioId, msg.sender, winnings);
    }

    function calculateWinnings(uint256 _scenarioId, address _bettor) public view returns (uint256) {
        if (interferancePools[_scenarioId] > 0) {
            // If interference exists, winners split both pools
            uint256 totalWinningBets = getTotalWinningBets(_scenarioId);
            if (totalWinningBets == 0) return 0;
            return (scenarioPools[_scenarioId] + interferancePools[_scenarioId]) * 
                   bets[_scenarioId][_bettor].amount / totalWinningBets;
        } else {
            // If no interference, split only the betting pool
            uint256 totalWinningBets = getTotalWinningBets(_scenarioId);
            if (totalWinningBets == 0) return 0;
            return scenarioPools[_scenarioId] * bets[_scenarioId][_bettor].amount / totalWinningBets;
        }
    }

    function calculateInterferenceWinnings(uint256 _scenarioId, address _interferer) public view returns (uint256) {
        uint256 totalWinningInterference = getTotalWinningInterference(_scenarioId);
        if (totalWinningInterference == 0) return 0;
        return interferancePools[_scenarioId] * 
               interferences[_scenarioId][_interferer].amount / totalWinningInterference;
    }

    function getTotalWinningBets(uint256 _scenarioId) internal view returns (uint256) {
        uint256 total = 0;
        for (uint i = 0; i < scenarios[_scenarioId].bettors.length; i++) {
            address bettor = scenarios[_scenarioId].bettors[i];
            if (keccak256(abi.encodePacked(bets[_scenarioId][bettor].prediction)) == 
                keccak256(abi.encodePacked(scenarios[_scenarioId].outcome))) {
                total += bets[_scenarioId][bettor].amount;
            }
        }
        return total;
    }

    function getTotalWinningInterference(uint256 _scenarioId) internal view returns (uint256) {
        uint256 total = 0;
        for (uint i = 0; i < scenarios[_scenarioId].interferers.length; i++) {
            address interferer = scenarios[_scenarioId].interferers[i];
            if (keccak256(abi.encodePacked(interferences[_scenarioId][interferer].prediction)) == 
                keccak256(abi.encodePacked(scenarios[_scenarioId].outcome))) {
                total += interferences[_scenarioId][interferer].amount;
            }
        }
        return total;
    }

    // Getter Functions
    function getScenarioDetails(uint256 _scenarioId) external view returns (ScenarioView memory) {
        Scenario storage scenario = scenarios[_scenarioId];
        return ScenarioView({
            id: scenario.id,
            startTime: scenario.startTime,
            endTime: scenario.endTime,
            resolved: scenario.resolved,
            outcome: scenario.outcome,
            totalPool: scenario.totalPool
        });
    }

    function getBet(uint256 _scenarioId, address _bettor) external view returns (Bet memory) {
        return bets[_scenarioId][_bettor];
    }

    function getInterference(uint256 _scenarioId, address _interferer) external view returns (Interference memory) {
        return interferences[_scenarioId][_interferer];
    }

    function getScenarioPool(uint256 _scenarioId) external view returns (uint256) {
        return scenarioPools[_scenarioId];
    }

    function getInterferencePool(uint256 _scenarioId) external view returns (uint256) {
        return interferancePools[_scenarioId];
    }

    function getPredictionVotes(uint256 _scenarioId, string memory _prediction) external view returns (uint256) {
        return scenarios[_scenarioId].predictionVotes[_prediction];
    }

    function getInterferenceAmount(uint256 _scenarioId, string memory _prediction) external view returns (uint256) {
        return scenarios[_scenarioId].interferenceAmounts[_prediction];
    }

    function getActiveBettors(uint256 _scenarioId) public view returns (uint256) {
        return scenarios[_scenarioId].bettors.length;
    }

    function getActiveBettor(uint256 _scenarioId, uint256 _index) public view returns (address) {
        require(_index < scenarios[_scenarioId].bettors.length, "Index out of bounds");
        return scenarios[_scenarioId].bettors[_index];
    }

    function getActiveInterferers(uint256 _scenarioId) public view returns (uint256) {
        return scenarios[_scenarioId].interferers.length;
    }

    function getActiveInterferer(uint256 _scenarioId, uint256 _index) public view returns (address) {
        require(_index < scenarios[_scenarioId].interferers.length, "Index out of bounds");
        return scenarios[_scenarioId].interferers[_index];
    }

    function getAllPredictions(uint256 _scenarioId) public view returns (string[] memory) {
        return scenarios[_scenarioId].predictions;
    }

    function getPredictionCount(uint256 _scenarioId) external view returns (uint256) {
        return scenarios[_scenarioId].predictions.length;
    }

    // Helper Functions
    function getMinimumBetAmount(uint256 _scenarioId) public view returns (uint256) {
        if (scenarios[_scenarioId].bettors.length == 0) return 0;
        
        uint256 minBet = type(uint256).max;
        for (uint i = 0; i < scenarios[_scenarioId].bettors.length; i++) {
            address bettor = scenarios[_scenarioId].bettors[i];
            if (bets[_scenarioId][bettor].amount < minBet) {
                minBet = bets[_scenarioId][bettor].amount;
            }
        }
        return minBet;
    }

    function isPredictionExists(uint256 _scenarioId, string memory _prediction) internal view returns (bool) {
        string[] memory predictions = scenarios[_scenarioId].predictions;
        for (uint i = 0; i < predictions.length; i++) {
            if (keccak256(abi.encodePacked(predictions[i])) == keccak256(abi.encodePacked(_prediction))) {
                return true;
            }
        }
        return false;
    }

}