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
    // ====================================================
// GOVERNANCE: MOVIE UPLOAD & VOTING
// ====================================================

enum MovieStatus {
    PENDING,
    APPROVED,
    REJECTED
}

struct MovieProposal {
    string title;
    Plan targetPlan;
    uint approveVotes;
    uint rejectVotes;
    MovieStatus status;
}

uint public movieProposalCount;

mapping(uint => MovieProposal) public movieProposals;
mapping(uint => mapping(address => bool)) public hasVotedMovie;

// ================= EVENTS =================
event MovieProposed(
    uint indexed proposalId,
    string title,
    Plan targetPlan
);

event MovieVoted(
    uint indexed proposalId,
    address voter,
    bool approve
);

event MovieApproved(uint indexed proposalId);
event MovieRejected(uint indexed proposalId);

// ================= FUNCTIONS =================

/// Upload demo movie & choose plan
function proposeMovie(string memory title, Plan targetPlan) external {
    require(targetPlan != Plan.NONE, "Invalid plan");

    movieProposalCount++;

    movieProposals[movieProposalCount] = MovieProposal({
        title: title,
        targetPlan: targetPlan,
        approveVotes: 0,
        rejectVotes: 0,
        status: MovieStatus.PENDING
    });

    emit MovieProposed(movieProposalCount, title, targetPlan);
}

/// Vote approve / reject
function voteMovie(uint proposalId, bool approve) external {
    MovieProposal storage proposal = movieProposals[proposalId];

    require(proposal.status == MovieStatus.PENDING, "Voting closed");
    require(!hasVotedMovie[proposalId][msg.sender], "Already voted");

    // Chỉ user có subscription còn hạn mới được vote
    require(
        subscriptions[msg.sender] != Plan.NONE &&
        expiration[msg.sender] >= block.timestamp,
        "Only active subscribers can vote"
    );

    hasVotedMovie[proposalId][msg.sender] = true;

    if (approve) {
        proposal.approveVotes++;
    } else {
        proposal.rejectVotes++;
    }

    emit MovieVoted(proposalId, msg.sender, approve);

    _checkMovieResult(proposalId);
}

/// Check threshold & auto add movie
function _checkMovieResult(uint proposalId) internal {
    MovieProposal storage proposal = movieProposals[proposalId];
    uint threshold = _getVoteThreshold(proposal.targetPlan);

    if (proposal.approveVotes >= threshold) {
        proposal.status = MovieStatus.APPROVED;

        // ✅ AUTO ADD MOVIE TO EXISTING MOVIES MAPPING
        movies[proposal.targetPlan].push(proposal.title);

        emit MovieApproved(proposalId);
    }

    if (proposal.rejectVotes >= threshold) {
        proposal.status = MovieStatus.REJECTED;
        emit MovieRejected(proposalId);
    }
}

/// Vote threshold by plan
function _getVoteThreshold(Plan plan) internal pure returns (uint) {
    if (plan == Plan.BASIC) return 5;
    if (plan == Plan.STANDARD) return 10;
    if (plan == Plan.PREMIUM) return 15;
    return 0;
}

/// View proposal info
function getMovieProposal(uint proposalId)
    external
    view
    returns (
        string memory title,
        Plan plan,
        uint approveVotes,
        uint rejectVotes,
        MovieStatus status
    )
{
    MovieProposal memory p = movieProposals[proposalId];
    return (
        p.title,
        p.targetPlan,
        p.approveVotes,
        p.rejectVotes,
        p.status
    );
}

}
