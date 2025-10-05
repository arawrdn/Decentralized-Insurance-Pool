// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract SimpleInsurancePool {
    address private immutable i_owner;

    // Minimum deposit allowed for contribution (0.000001 ETH)
    uint256 private constant MIN_CONTRIBUTION = 1000000000000 wei; 
    uint256 private constant APPROVAL_THRESHOLD = 51; 

    // STATE VARIABLES
    mapping(address => uint256) public s_contribution;
    uint256 public s_totalContribution;
    uint256 public s_nextClaimId = 1;

    struct Claim {
        address claimant;
        uint256 amount;
        string evidence; 
        bool paid;
        uint256 votesFor; 
        uint256 votesAgainst; 
        mapping(address => bool) hasVoted; // MAPPING HARUS ADA DI STORAGE
    }

    mapping(uint256 => Claim) public s_claims;

    // MODIFIERS
    modifier onlyOwner() {
        require(msg.sender == i_owner, "Not the owner");
        _;
    }

    modifier onlyContributor() {
        require(s_contribution[msg.sender] > 0, "Must be a contributor to perform this action");
        _;
    }

    // CONSTRUCTOR
    constructor() {
        i_owner = msg.sender;
    }

    // ------------------------------------
    // 1. DEPOSIT/CONTRIBUTION LOGIC
    // ------------------------------------
    
    function _handleDeposit() internal {
        require(msg.value >= MIN_CONTRIBUTION, "Minimum contribution is 0.000001 ETH");
        s_contribution[msg.sender] += msg.value;
        s_totalContribution += msg.value;
    }

    receive() external payable {
        _handleDeposit();
    }
    
    fallback() external payable {
        _handleDeposit();
    }

    // ------------------------------------
    // 2. CLAIM SUBMISSION (OWNER ACTION ONLY) - PERBAIKAN DITERAPKAN DI SINI
    // ------------------------------------

    /**
     * @dev ONLY OWNER can file a claim on behalf of a user.
     */
    function ownerFileClaim(address _claimant, uint256 _amount, string memory _evidence) external onlyOwner returns (uint256) {
        require(_amount > 0 && _amount <= address(this).balance, "Invalid claim amount");
        
        uint256 claimId = s_nextClaimId;
        
        // SOLUSI: Dapatkan pointer storage ke lokasi struct baru
        Claim storage newClaim = s_claims[claimId];

        // Isi anggota struct satu per satu
        newClaim.claimant = _claimant;
        newClaim.amount = _amount;
        newClaim.evidence = _evidence;
        newClaim.paid = false;
        newClaim.votesFor = 0;
        newClaim.votesAgainst = 0;
        // TIDAK PERLU mengisi 'hasVoted', karena mapping secara otomatis ada di storage

        s_nextClaimId++;
        return claimId;
    }

    // ------------------------------------
    // 3. VOTING MECHANISM
    // ------------------------------------
    
    function voteOnClaim(uint256 _claimId, bool _voteFor) external onlyContributor {
        Claim storage claim = s_claims[_claimId];
        require(claim.claimant != address(0), "Claim does not exist");
        require(!claim.paid, "Claim has already been paid");
        require(!claim.hasVoted[msg.sender], "Already voted on this claim");
        require(claim.claimant != msg.sender, "Claimant cannot vote on their own claim"); 

        uint256 contributorWeight = s_contribution[msg.sender];
        claim.hasVoted[msg.sender] = true;

        if (_voteFor) {
            claim.votesFor += contributorWeight;
        } else {
            claim.votesAgainst += contributorWeight;
        }

        if (checkThreshold(claim.votesFor)) {
            resolveClaim(_claimId);
        }
    }
    
    function checkThreshold(uint256 _currentVotesFor) internal view returns (bool) {
        return (_currentVotesFor * 100) >= (s_totalContribution * APPROVAL_THRESHOLD);
    }

    // ------------------------------------
    // 4. CLAIM RESOLUTION AND PAYMENT
    // ------------------------------------

    function resolveClaim(uint256 _claimId) public {
        Claim storage claim = s_claims[_claimId];
        require(claim.claimant != address(0), "Claim does not exist");
        require(!claim.paid, "Claim has already been paid");
        
        require(checkThreshold(claim.votesFor), "Approval threshold not met (51% of total pool contribution required)");
        
        uint256 amountToPay = claim.amount;
        claim.paid = true;
        
        (bool success, ) = payable(claim.claimant).call{value: amountToPay}("");
        require(success, "ETH transfer failed");
    }

    // ------------------------------------
    // 5. WITHDRAWAL 
    // ------------------------------------
    
    function withdrawContribution() external onlyContributor {
        uint256 amount = s_contribution[msg.sender];
        require(amount > 0, "No contribution to withdraw");

        s_contribution[msg.sender] = 0;
        s_totalContribution -= amount;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    // ------------------------------------
    // 6. VIEW FUNCTIONS
    // ------------------------------------
    
    function getPoolBalance() public view returns (uint256) {
        return address(this).balance;
    }
}
