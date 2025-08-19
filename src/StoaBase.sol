// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts/access/Ownable.sol";

abstract contract StoaBase is Ownable {
    uint256 public feeBps = 1000; // 10% protocol fee
    uint256 public creatorFeeBps = 1000; // 10% creator fee (same as protocol fee)
    address public treasury;

    uint256 private constant BASIS_POINTS = 10000; // 100% = 10000 basis points

    event FeeUpdated(uint256 newFeeBps);
    event CreatorFeeUpdated(uint256 newCreatorFeeBps);
    event TreasuryUpdated(address newTreasury);

    constructor(address _treasury) {
        require(_treasury != address(0), "Invalid treasury");
        treasury = _treasury;
        _transferOwnership(msg.sender);
    }

    function setFeeBps(uint256 newFeeBps) external onlyOwner {
        require(newFeeBps <= BASIS_POINTS, "Fee cannot exceed 100%");
        feeBps = newFeeBps;
        emit FeeUpdated(newFeeBps);
    }

    function setCreatorFeeBps(uint256 newCreatorFeeBps) external onlyOwner {
        require(newCreatorFeeBps <= BASIS_POINTS, "Creator fee cannot exceed 100%");
        creatorFeeBps = newCreatorFeeBps;
        emit CreatorFeeUpdated(newCreatorFeeBps);
    }

    function setTreasury(address newTreasury) external onlyOwner {
        require(newTreasury != address(0), "Invalid treasury");
        treasury = newTreasury;
        emit TreasuryUpdated(newTreasury);
    }
}
