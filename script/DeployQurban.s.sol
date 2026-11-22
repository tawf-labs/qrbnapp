// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console} from "forge-std/Script.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Qurban} from "../src/qurban/Qurban.sol";
import {QurbanNFT} from "../src/qurban/QurbanNFT.sol";
import {QrbnTreasury} from "../src/dao/QrbnTreasury.sol";

/// @notice Deploys only what qurban.tawf.foundation uses (Qurban, certificate NFT, treasury)
/// to Arbitrum Sepolia, pays in Circle's test USDC, and lists three sample animals.
/// @dev TESTNET ONLY: the deployer is the governor. Mainnet needs a timelock or multisig.
contract DeployQurban is Script {
    uint256 internal constant ARBITRUM_SEPOLIA = 421614;
    address internal constant USDC = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;
    uint256 internal constant SACRIFICE_DATE = 1810425600; // 2027-05-16 00:00 UTC
    string internal constant NOTE =
        "Sample listing for the testnet preview. Not a real animal.";

    function run() external returns (Qurban qurban, QurbanNFT nft, QrbnTreasury treasury) {
        require(block.chainid == ARBITRUM_SEPOLIA, "Arbitrum Sepolia only");
        require(IERC20Metadata(USDC).decimals() == 6, "unexpected USDC");

        vm.startBroadcast();
        (, address deployer, ) = vm.readCallers();
        address vendor = vm.envOr("VENDOR_ADDRESS", deployer);

        nft = new QurbanNFT(deployer, deployer);
        treasury = new QrbnTreasury(deployer, deployer, USDC);
        qurban = new Qurban(USDC, address(treasury), deployer, address(nft), deployer);

        nft.grantRole(nft.GOVERNER_ROLE(), address(qurban));
        treasury.authorizeDepositor(address(qurban));

        qurban.registerVendor(vendor, "Test vendor", "salam@tawflabs.com", "Testnet");
        _list(qurban, vendor, "Sample goat", Qurban.AnimalType.GOAT, 1, 5e6, "/animals/goat.png", 35, 2);
        _list(qurban, vendor, "Sample sheep", Qurban.AnimalType.SHEEP, 1, 5e6, "/animals/sheep.png", 40, 2);
        _list(qurban, vendor, "Sample cow", Qurban.AnimalType.COW, 7, 2e6, "/animals/cow.png", 350, 3);
        vm.stopBroadcast();

        console.log("Deployer and governor:", deployer);
        console.log("Vendor:", vendor);
        console.log("Qurban:", address(qurban));
        console.log("QurbanNFT:", address(nft));
        console.log("QrbnTreasury:", address(treasury));
    }

    function _list(
        Qurban qurban,
        address vendor,
        string memory name,
        Qurban.AnimalType kind,
        uint8 shares,
        uint256 price,
        string memory image,
        uint16 weight,
        uint16 age
    ) internal {
        qurban.addAnimal(
            vendor, name, kind, shares, price, "Testnet", image, NOTE,
            "Sample", weight, age, "Sample farm", SACRIFICE_DATE
        );
    }
}
