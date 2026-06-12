// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/SubscriptionProtocol.sol";

contract DeploySubscriptionProtocol is Script {
    function run() external {
        // This checks if a private key was passed via the --private-key terminal flag first
        uint256 deployerPrivateKey;

        try vm.envUint("PRIVATE_KEY") returns (uint256 key) {
            deployerPrivateKey = key;
        } catch {
            // Fallback to reading the active executing wallet if --private-key flag is used
            deployerPrivateKey = msg.sender.balance > 0
                ? uint256(0)
                : uint256(0);
        }

        // Set your constructor arguments here
        uint256 initialFee = 0.01 ether;
        string memory baseURI = "ipfs://QmYourBaseMetadataCID/";

        // If you passed a key via terminal flag, vm.startBroadcast() handles it automatically!
        vm.startBroadcast();

        SubscriptionProtocol protocol = new SubscriptionProtocol(
            initialFee,
            baseURI
        );

        vm.stopBroadcast();

        console.log("SubscriptionProtocol deployed to:", address(protocol));
    }
}
