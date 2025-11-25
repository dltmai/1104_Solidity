// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Subscription {
    address public owner;

    uint public constant BASIC_PRICE = 0.001 ether;
    uint public constant STANDARD_PRICE = 0.003 ether;
    uint public constant PREMIUM_PRICE = 0.005 ether;

    enum Plan { NONE, BASIC, STANDARD, PREMIUM }

    struct Transaction {
        uint txId;
        bytes32 txHash;
        uint blockNumber;
        address sender;
        address receiver;
        Plan plan;
        uint amount;
        uint gasUsed;
        uint gasPrice;
        uint timestamp;
    }

    mapping(address => Plan) public subscriptions;
    mapping(address => uint) public expiration;
    mapping(Plan => string[]) private movies;
    mapping(uint => Transaction) public transactions;
    mapping(address => uint[]) private userTransactions; 

    uint private nextTxId = 0;

    event Subscribed(address indexed user, Plan plan, uint expiresAt);
    event MovieAdded(Plan plan, string movie);
    event FundsWithdrawn(address indexed owner, uint amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this");
        _;
    }

    constructor() {
        owner = msg.sender;

        movies[Plan.BASIC] = ["Movie A", "Movie B"];
        movies[Plan.STANDARD] = ["Movie A", "Movie B", "Movie C", "Movie D"];
        movies[Plan.PREMIUM] = ["Movie A", "Movie B", "Movie C", "Movie D", "Movie E", "Movie F"];
    }

    function subscribeBasic() external payable {
        require(msg.value >= BASIC_PRICE, "Insufficient amount");
        _subscribe(Plan.BASIC, 30 days);
        _refundExcess(BASIC_PRICE);
    }

    function subscribeStandard() external payable {
        require(msg.value >= STANDARD_PRICE, "Insufficient amount");
        _subscribe(Plan.STANDARD, 45 days);
        _refundExcess(STANDARD_PRICE);
    }

    function subscribePremium() external payable {
        require(msg.value >= PREMIUM_PRICE, "Insufficient amount");
        _subscribe(Plan.PREMIUM, 60 days);
        _refundExcess(PREMIUM_PRICE);
    }

    function _subscribe(Plan plan, uint duration) internal {
        uint newExpiration = block.timestamp + duration;
        
        if (subscriptions[msg.sender] != Plan.NONE && expiration[msg.sender] > block.timestamp) {
            newExpiration = expiration[msg.sender] + duration;
        }

        subscriptions[msg.sender] = plan;
        expiration[msg.sender] = newExpiration;
        emit Subscribed(msg.sender, plan, newExpiration);


        transactions[nextTxId] = Transaction({
            txId: nextTxId,
            txHash: keccak256(abi.encodePacked(msg.sender, block.timestamp)),
            blockNumber: block.number,
            sender: msg.sender,
            receiver: address(this),
            plan: plan,
            amount: msg.value,
            gasUsed: 0, 
            gasPrice: tx.gasprice,
            timestamp: block.timestamp
        });

        userTransactions[msg.sender].push(nextTxId);
        nextTxId++;
    }

    function _refundExcess(uint price) internal {
        if (msg.value > price) {
            payable(msg.sender).transfer(msg.value - price);
        }
    }

    function checkSubscription(address user) external view returns (Plan, uint) {
        return (subscriptions[user], expiration[user]);
    }

    function getAvailableMovies(address user) external view returns (string[] memory) {
        Plan userPlan = subscriptions[user];
        require(userPlan != Plan.NONE, "No subscription found");
        require(expiration[user] >= block.timestamp, "Subscription expired");
        return movies[userPlan];
    }
    function getMoviesByPlan(uint planId) external view returns (string[] memory) {
        require(planId >= 1 && planId <= 3, "Invalid planId");
        Plan plan = Plan(planId);
        return movies[plan];
}

    function addMovie(Plan plan, string memory movie) external onlyOwner {
        require(plan != Plan.NONE, "Invalid plan");
        movies[plan].push(movie);
        emit MovieAdded(plan, movie);
    }

    function withdraw() external onlyOwner {
        uint balance = address(this).balance;
        require(balance > 0, "No funds to withdraw");
        payable(owner).transfer(balance);
        emit FundsWithdrawn(owner, balance);
    }

    function getTransactionDetails(uint txId) external view returns (Transaction memory) {
        require(txId < nextTxId, "Invalid transaction ID");
        return transactions[txId];
    }

    function getTransactionsByUser(address user) external view returns (Transaction[] memory) {
        uint[] memory txIds = userTransactions[user];
        uint length = txIds.length;
        Transaction[] memory txList = new Transaction[](length);

        for (uint i = 0; i < length; i++) {
            txList[i] = transactions[txIds[i]];
        }

        return txList;
    }
}