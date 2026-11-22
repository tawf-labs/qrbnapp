// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {Qurban} from "../src/qurban/Qurban.sol";
import {QurbanNFT} from "../src/qurban/QurbanNFT.sol";
import {QrbnTreasury} from "../src/dao/QrbnTreasury.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";

/// Holds shares but cannot receive ERC721 tokens through safeMint.
contract NonReceiver {
    function buy(MockUSDC usdc, Qurban qurban, uint256 id, uint8 n) external {
        usdc.approve(address(qurban), type(uint256).max);
        qurban.purchaseAnimalShares(id, n);
    }
}

/// Regression tests for defects found while moving off Lisk Sepolia.
contract TestQurbanRegression is Test {
    MockUSDC usdc;
    QurbanNFT nft;
    QrbnTreasury treasury;
    Qurban qurban;
    address gov = address(this);
    address vendor = makeAddr("vendor");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        usdc = new MockUSDC(gov, gov);
        nft = new QurbanNFT(gov, gov);
        treasury = new QrbnTreasury(gov, gov, address(usdc));
        qurban = new Qurban(address(usdc), address(treasury), gov, address(nft), gov);
        nft.grantRole(nft.GOVERNER_ROLE(), address(qurban));
        treasury.authorizeDepositor(address(qurban));
        qurban.registerVendor(vendor, "v", "c", "l");
        _add(7);
        usdc.mint(alice, 1000e6);
        usdc.mint(bob, 1000e6);
    }

    function _add(uint8 shares) internal {
        qurban.addAnimal(vendor, "a", Qurban.AnimalType.COW, shares, 10e6, "l", "i", "d", "b", 1, 1, "f", block.timestamp + 30 days);
    }

    function _buy(address who, uint256 id, uint8 n) internal {
        vm.startPrank(who);
        usdc.approve(address(qurban), type(uint256).max);
        qurban.purchaseAnimalShares(id, n);
        vm.stopPrank();
    }

    function _edit(uint8 shares) internal {
        qurban.editAnimal(vendor, 0, "a2", Qurban.AnimalType.COW, shares, 10e6, "l", "i", "d", "b", 1, 1, "f", block.timestamp + 30 days);
    }

    /// Buyers of an animal that never fills up must be refundable.
    function test_PartiallySoldAnimalCanBeRefunded() public {
        _buy(alice, 0, 3);
        qurban.refundAnimalPurchases(0, "not filled");
        assertEq(usdc.balanceOf(alice), 1000e6);
        assertEq(qurban.getAnimalById(0).availableShares, 7);
    }

    function test_AnimalWithNoPurchasesCannotBeRefunded() public {
        vm.expectRevert();
        qurban.refundAnimalPurchases(0, "nothing sold");
    }

    /// Editing after a sale must not put sold shares back on the shelf.
    function test_EditKeepsSoldSharesSold() public {
        _buy(alice, 0, 3);
        _edit(7);
        assertEq(qurban.getAnimalById(0).availableShares, 4);
    }

    function test_EditCannotDropBelowSoldShares() public {
        _buy(alice, 0, 3);
        vm.expectRevert();
        _edit(2);
    }

    function test_EditDownToSoldSharesMarksSold() public {
        _buy(alice, 0, 3);
        _edit(3);
        assertEq(uint8(qurban.getAnimalById(0).status), uint8(Qurban.AnimalStatus.SOLD));
    }

    function test_SoldOrSacrificedAnimalCannotBeReopened() public {
        _buy(alice, 0, 7);
        vm.expectRevert();
        qurban.approveAnimal(0);
        qurban.markAnimalSacrificedAndMintCertificates(0, "ipfs://x");
        vm.expectRevert();
        qurban.approveAnimal(0);
    }

    function test_UnlistedAnimalCannotBeApproved() public {
        vm.expectRevert();
        qurban.approveAnimal(99);
        vm.expectRevert();
        qurban.unapproveAnimal(99);
    }

    function test_SacrificedAnimalCannotBeUnapprovedOrEdited() public {
        _buy(alice, 0, 7);
        qurban.markAnimalSacrificedAndMintCertificates(0, "ipfs://x");
        vm.expectRevert();
        _edit(7);
        vm.expectRevert();
        qurban.unapproveAnimal(0);
    }

    /// One buyer that cannot receive NFTs must not block everyone else.
    function test_NonReceiverDoesNotBlockSacrifice() public {
        NonReceiver c = new NonReceiver();
        usdc.mint(address(c), 100e6);
        c.buy(usdc, qurban, 0, 1);
        _buy(alice, 0, 6);
        qurban.markAnimalSacrificedAndMintCertificates(0, "ipfs://x");
        assertEq(nft.balanceOf(alice), 1);
        assertEq(nft.balanceOf(address(c)), 1);
    }

    function test_CertificateUriIsReadable() public {
        _buy(alice, 0, 4);
        _buy(bob, 0, 3);
        qurban.markAnimalSacrificedAndMintCertificates(0, "ipfs://x");
        assertEq(nft.tokenURI(1), "ipfs://x/0/0");
        assertEq(nft.tokenURI(2), "ipfs://x/0/1");
    }

    function test_CannotBuyAfterSacrificeDate() public {
        vm.warp(block.timestamp + 31 days);
        vm.startPrank(alice);
        usdc.approve(address(qurban), type(uint256).max);
        vm.expectRevert();
        qurban.purchaseAnimalShares(0, 1);
        vm.stopPrank();
    }

    /// After refund and resale, money in always equals money out.
    function test_RefundThenResaleSettlesExactly() public {
        _buy(alice, 0, 7);
        qurban.refundAnimalPurchases(0, "r");
        qurban.approveAnimal(0);
        _buy(alice, 0, 2);
        _buy(bob, 0, 5);
        qurban.markAnimalSacrificedAndMintCertificates(0, "ipfs://x");
        assertEq(usdc.balanceOf(address(qurban)), 0);
        assertEq(usdc.balanceOf(vendor) + usdc.balanceOf(address(treasury)), 70e6);
        assertEq(usdc.balanceOf(vendor), 68.25e6);
        assertEq(qurban.s_vendorSharesPool(), 0);
    }
}
