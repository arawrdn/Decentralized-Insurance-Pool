# Simple Decentralized Insurance Pool

A minimal-interaction smart contract implementation of an on-chain insurance pool built on the Ethereum Virtual Machine (EVM).

---

## Project Overview

This contract enables a group of participants (Contributors) to pool Ether (ETH) for mutual insurance coverage. Claims are resolved democratically through a proportional voting mechanism.

The design focuses on **minimal user interaction**, requiring contributors only to deposit funds and vote on claim validity. The administrative burden of filing claims is handled by the Owner.

---

## Deployment and Contract Details

| Parameter | Value |
| :--- | :--- |
| **Contract Address (CA)** | `0x616aC1326f7c94d924C9b900760031171dB88899` |
| **Blockchain Explorer** | https://basescan.org/address/0x616aC1326f7c94d924C9b900760031171dB88899 |
| **Deployer/Owner Address** | `0x2A6b5204B83C7619c90c4EB6b5365AA0b7d912F7` |
| **Solidity Version** | `0.8.30` |
| **Minimum Contribution** | `0.000001 ETH` (1 Trillion Wei) |
| **Approval Threshold** | **51%** of the total pool's ETH balance |

---

## User Guide: Contributor (Voter/Depositor)

Contributors fund the pool, gain voting power, and decide on the validity of claims.

| Action | Function/Method | Input Format | Description |
| :--- | :--- | :--- | :--- |
| **Deposit Funds** | Send ETH (Transfer) | Value $\ge$ `0.000001 ETH` | Sends ETH directly to the CA. This amount becomes the User's **Proportional Voting Power**. |
| **Vote on Claim** | `voteOnClaim(uint256 _claimId, bool _voteFor)` | `ID` (e.g., `1`), `true`/`false` | Casts the User's entire voting weight (contributed ETH) for (true) or against (false) the claim. |
| **Withdraw Deposit** | `withdrawContribution()` | No input | Allows the User to exit the pool and withdraw their remaining ETH contribution. |

---

## Admin Guide: Owner Functions

The Owner is responsible for pre-validating and submitting claims for the community to vote on.

| Action | Function/Method | Parameters (Example) | Description |
| :--- | :--- | :--- | :--- |
| **File Claim** | `ownerFileClaim(address _claimant, uint256 _amount, string memory _evidence)` | `0xAddress`, `5000000000000`, `"Description"` | Submits a new claim to the pool, generating a **Claim ID** for voting. **Note:** `_amount` must be in Wei and less than the pool's current balance. |
| **Resolve Claim** | `resolveClaim(uint256 _claimId)` | `1` | Forces claim resolution and payment if the 51% threshold has been met, acting as a fallback if the automatic trigger fails. |

---

## Voting Mechanism

1.  **Proportional Power:** Voting power is directly tied to the amount of ETH contributed (`s_contribution`).
2.  **Threshold:** A claim is approved if the collective weight of **YES** votes (`votesFor`) reaches **51%** of the **Total Pool Balance** (`s_totalContribution`).
3.  **Automation:** If the threshold is met upon casting a vote, the claim is automatically paid out in the same transaction, saving the Owner an additional step.

---

## Contract Structure (Solidity Code)

The full, verified Solidity source code for the `SimpleInsurancePool` contract is provided below:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract SimpleInsurancePool {
    address private immutable i_owner;

    // Minimum deposit allowed for contribution (0.000001 ETH)
    uint256 private constant MIN_CONTRIBUTION = 1000000000000 wei; 

    // Threshold for claim approval (51% of total contribution weight)
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
        mapping(address => bool) hasVoted; 
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

    // 1. DEPOSIT/CONTRIBUTION LOGIC 
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

    // 2. CLAIM SUBMISSION (OWNER ACTION ONLY)
    function ownerFileClaim(address _claimant, uint256 _amount, string memory _evidence) external onlyOwner returns (uint256) {
        require(_amount > 0 && _amount <= address(this).balance, "Invalid claim amount");
        
        uint256 claimId = s_nextClaimId;
        
        Claim storage newClaim = s_claims[claimId];

        newClaim.claimant = _claimant;
        newClaim.amount = _amount;
        newClaim.evidence = _evidence;
        newClaim.paid = false;
        newClaim.votesFor = 0;
        newClaim.votesAgainst = 0;

        s_nextClaimId++;
        return claimId;
    }

    // 3. VOTING MECHANISM 
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

    // 4. CLAIM RESOLUTION AND PAYMENT
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

    // 5. WITHDRAWAL 
    function withdrawContribution() external onlyContributor {
        uint256 amount = s_contribution[msg.sender];
        require(amount > 0, "No contribution to withdraw");

        s_contribution[msg.sender] = 0;
        s_totalContribution -= amount;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    // 6. VIEW FUNCTIONS
    function getPoolBalance() public view returns (uint256) {
        return address(this).balance;
    }
}
