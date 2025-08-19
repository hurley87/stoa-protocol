// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/StoaBase.sol";

// Concrete implementation of StoaBase for testing
contract ConcreteStoaBase is StoaBase {
    constructor(address _treasury) StoaBase(_treasury) {}
}

contract StoaBaseTest is Test {
    ConcreteStoaBase public stoaBase;
    address public owner;
    address public treasury;
    address public newTreasury;
    address public nonOwner;

    event FeeUpdated(uint256 newFeeBps);
    event CreatorFeeUpdated(uint256 newCreatorFeeBps);
    event TreasuryUpdated(address newTreasury);

    function setUp() public {
        owner = address(this);
        treasury = address(0x1);
        newTreasury = address(0x2);
        nonOwner = address(0x3);

        stoaBase = new ConcreteStoaBase(treasury);
    }

    // Constructor Tests
    function testConstructor() public {
        assertEq(stoaBase.treasury(), treasury);
        assertEq(stoaBase.owner(), owner);
        assertEq(stoaBase.feeBps(), 1000); // Default 10% protocol fee
        assertEq(stoaBase.creatorFeeBps(), 1000); // Default 10% creator fee
    }

    function testConstructorRevertsWithZeroTreasury() public {
        vm.expectRevert("Invalid treasury");
        new ConcreteStoaBase(address(0));
    }

    // Fee Management Tests
    function testSetFeeBpsAsOwner() public {
        uint256 newFeeBps = 500; // 5%

        vm.expectEmit(true, false, false, true);
        emit FeeUpdated(newFeeBps);

        stoaBase.setFeeBps(newFeeBps);

        assertEq(stoaBase.feeBps(), newFeeBps);
    }

    function testSetFeeBpsAsNonOwner() public {
        uint256 newFeeBps = 500;

        vm.prank(nonOwner);
        vm.expectRevert();
        stoaBase.setFeeBps(newFeeBps);

        // Fee should remain unchanged
        assertEq(stoaBase.feeBps(), 1000);
    }

    function testSetFeeBpsToZero() public {
        uint256 newFeeBps = 0;

        vm.expectEmit(true, false, false, true);
        emit FeeUpdated(newFeeBps);

        stoaBase.setFeeBps(newFeeBps);

        assertEq(stoaBase.feeBps(), newFeeBps);
    }

    function testSetFeeBpsToMaxValue() public {
        uint256 newFeeBps = 10000; // 100%

        vm.expectEmit(true, false, false, true);
        emit FeeUpdated(newFeeBps);

        stoaBase.setFeeBps(newFeeBps);

        assertEq(stoaBase.feeBps(), newFeeBps);
    }

    function testSetFeeBpsMultipleTimes() public {
        uint256[] memory feeValues = new uint256[](3);
        feeValues[0] = 250; // 2.5%
        feeValues[1] = 750; // 7.5%
        feeValues[2] = 1500; // 15%

        for (uint256 i = 0; i < feeValues.length; i++) {
            vm.expectEmit(true, false, false, true);
            emit FeeUpdated(feeValues[i]);

            stoaBase.setFeeBps(feeValues[i]);
            assertEq(stoaBase.feeBps(), feeValues[i]);
        }
    }

    // Treasury Management Tests
    function testSetTreasuryAsOwner() public {
        vm.expectEmit(true, false, false, true);
        emit TreasuryUpdated(newTreasury);

        stoaBase.setTreasury(newTreasury);

        assertEq(stoaBase.treasury(), newTreasury);
    }

    function testSetTreasuryAsNonOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        stoaBase.setTreasury(newTreasury);

        // Treasury should remain unchanged
        assertEq(stoaBase.treasury(), treasury);
    }

    function testSetTreasuryToZeroAddress() public {
        vm.expectRevert("Invalid treasury");
        stoaBase.setTreasury(address(0));

        // Treasury should remain unchanged
        assertEq(stoaBase.treasury(), treasury);
    }

    function testSetTreasuryToSameAddress() public {
        vm.expectEmit(true, false, false, true);
        emit TreasuryUpdated(treasury);

        stoaBase.setTreasury(treasury);

        assertEq(stoaBase.treasury(), treasury);
    }

    function testSetTreasuryMultipleTimes() public {
        address[] memory treasuryAddresses = new address[](3);
        treasuryAddresses[0] = address(0x10);
        treasuryAddresses[1] = address(0x20);
        treasuryAddresses[2] = address(0x30);

        for (uint256 i = 0; i < treasuryAddresses.length; i++) {
            vm.expectEmit(true, false, false, true);
            emit TreasuryUpdated(treasuryAddresses[i]);

            stoaBase.setTreasury(treasuryAddresses[i]);
            assertEq(stoaBase.treasury(), treasuryAddresses[i]);
        }
    }

    // Ownership Tests (inherited from Ownable)
    function testOwnershipTransfer() public {
        address newOwner = address(0x4);

        stoaBase.transferOwnership(newOwner);

        assertEq(stoaBase.owner(), newOwner);

        // Original owner should no longer be able to call owner functions
        vm.expectRevert();
        stoaBase.setFeeBps(500);

        // New owner should be able to call owner functions
        vm.prank(newOwner);
        stoaBase.setFeeBps(500);
        assertEq(stoaBase.feeBps(), 500);
    }

    function testOwnershipTransferRevertsWithZeroAddress() public {
        vm.expectRevert("Ownable: new owner is the zero address");
        stoaBase.transferOwnership(address(0));

        // Owner should remain unchanged
        assertEq(stoaBase.owner(), owner);
    }

    function testOwnershipRenounce() public {
        stoaBase.renounceOwnership();

        assertEq(stoaBase.owner(), address(0));

        // No one should be able to call owner functions after renouncing
        vm.expectRevert();
        stoaBase.setFeeBps(500);

        vm.expectRevert();
        stoaBase.setTreasury(newTreasury);
    }

    // Edge Cases and Integration Tests
    function testCompleteWorkflow() public {
        // Initial state
        assertEq(stoaBase.feeBps(), 1000);
        assertEq(stoaBase.treasury(), treasury);
        assertEq(stoaBase.owner(), owner);

        // Update fee
        stoaBase.setFeeBps(750);
        assertEq(stoaBase.feeBps(), 750);

        // Update treasury
        stoaBase.setTreasury(newTreasury);
        assertEq(stoaBase.treasury(), newTreasury);

        // Transfer ownership
        address newOwner = address(0x5);
        stoaBase.transferOwnership(newOwner);
        assertEq(stoaBase.owner(), newOwner);

        // New owner can make changes
        vm.prank(newOwner);
        stoaBase.setFeeBps(1250);
        assertEq(stoaBase.feeBps(), 1250);

        address anotherTreasury = address(0x6);
        vm.prank(newOwner);
        stoaBase.setTreasury(anotherTreasury);
        assertEq(stoaBase.treasury(), anotherTreasury);
    }

    function testSetFeeBpsRevertsAboveMax() public {
        uint256 invalidFeeBps = 10001; // Above 100%

        vm.expectRevert("Fee cannot exceed 100%");
        stoaBase.setFeeBps(invalidFeeBps);
    }

    // Creator Fee Tests
    function testSetCreatorFeeBpsAsOwner() public {
        uint256 newCreatorFeeBps = 500; // 5%

        vm.expectEmit(true, false, false, true);
        emit CreatorFeeUpdated(newCreatorFeeBps);

        stoaBase.setCreatorFeeBps(newCreatorFeeBps);

        assertEq(stoaBase.creatorFeeBps(), newCreatorFeeBps);
    }

    function testSetCreatorFeeBpsAsNonOwner() public {
        uint256 newCreatorFeeBps = 500;

        vm.prank(nonOwner);
        vm.expectRevert();
        stoaBase.setCreatorFeeBps(newCreatorFeeBps);

        // Creator fee should remain unchanged
        assertEq(stoaBase.creatorFeeBps(), 1000);
    }

    function testSetCreatorFeeBpsRevertsAboveMax() public {
        uint256 invalidCreatorFeeBps = 10001; // Above 100%

        vm.expectRevert("Creator fee cannot exceed 100%");
        stoaBase.setCreatorFeeBps(invalidCreatorFeeBps);
    }

    function testSetCreatorFeeBpsToZero() public {
        uint256 newCreatorFeeBps = 0;

        vm.expectEmit(true, false, false, true);
        emit CreatorFeeUpdated(newCreatorFeeBps);

        stoaBase.setCreatorFeeBps(newCreatorFeeBps);

        assertEq(stoaBase.creatorFeeBps(), newCreatorFeeBps);
    }

    function testSetCreatorFeeBpsToMaxValue() public {
        uint256 newCreatorFeeBps = 10000; // 100%

        vm.expectEmit(true, false, false, true);
        emit CreatorFeeUpdated(newCreatorFeeBps);

        stoaBase.setCreatorFeeBps(newCreatorFeeBps);

        assertEq(stoaBase.creatorFeeBps(), newCreatorFeeBps);
    }

    // Fuzz Tests
    function testFuzzSetFeeBps(uint256 feeBps) public {
        vm.assume(feeBps <= 10000);
        stoaBase.setFeeBps(feeBps);
        assertEq(stoaBase.feeBps(), feeBps);
    }

    function testFuzzSetCreatorFeeBps(uint256 creatorFeeBps) public {
        vm.assume(creatorFeeBps <= 10000);
        stoaBase.setCreatorFeeBps(creatorFeeBps);
        assertEq(stoaBase.creatorFeeBps(), creatorFeeBps);
    }

    function testFuzzSetTreasury(address _treasury) public {
        vm.assume(_treasury != address(0));

        stoaBase.setTreasury(_treasury);
        assertEq(stoaBase.treasury(), _treasury);
    }

    function testFuzzSetTreasuryRejectsZero(address _treasury) public {
        vm.assume(_treasury == address(0));

        vm.expectRevert("Invalid treasury");
        stoaBase.setTreasury(_treasury);
    }

    // View Function Tests
    function testViewFunctions() public {
        // Test that view functions return correct values
        assertEq(stoaBase.feeBps(), 1000);
        assertEq(stoaBase.treasury(), treasury);
        assertEq(stoaBase.owner(), owner);

        // Update values and test again
        stoaBase.setFeeBps(2000);
        stoaBase.setTreasury(newTreasury);

        assertEq(stoaBase.feeBps(), 2000);
        assertEq(stoaBase.treasury(), newTreasury);
        assertEq(stoaBase.owner(), owner);
    }

    // Gas Usage Tests (informational)
    function testGasUsageSetFeeBps() public {
        uint256 gasBefore = gasleft();
        stoaBase.setFeeBps(500);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for setFeeBps:", gasUsed);
        // This is just informational, no assertion needed
    }

    function testGasUsageSetTreasury() public {
        uint256 gasBefore = gasleft();
        stoaBase.setTreasury(newTreasury);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for setTreasury:", gasUsed);
        // This is just informational, no assertion needed
    }
}
