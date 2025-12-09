// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {ShieldAuctionTaskHook} from "@project/l2-contracts/ShieldAuctionTaskHook.sol";

contract DeployShieldL2Contracts is Script {
    using stdJson for string;

    struct Context {
        address avs;
        uint256 avsPrivateKey;
        uint256 deployerPrivateKey;
        address shieldAuctionHook;  // Address of the main Shield Auction Hook (deployed separately)
        address serviceManager;  // Address of the L1 service manager
    }

    struct Output {
        string name;
        address contractAddress;
    }

    function run(string memory environment, string memory _context) public {
        // Read the context
        Context memory context = _readContext(environment, _context);

        vm.startBroadcast(context.deployerPrivateKey);
        console.log("Deployer address:", vm.addr(context.deployerPrivateKey));

        // Deploy Shield Auction Task Hook (connector to main hook)
        ShieldAuctionTaskHook taskHook = new ShieldAuctionTaskHook(
            context.shieldAuctionHook,
            context.serviceManager
        );
        console.log("ShieldAuctionTaskHook deployed to:", address(taskHook));
        console.log("Connected to main Shield Hook at:", context.shieldAuctionHook);
        console.log("Connected to service manager at:", context.serviceManager);

        vm.stopBroadcast();

        vm.startBroadcast(context.avsPrivateKey);
        console.log("AVS address:", context.avs);

        // TODO: Implement any additional L2 setup for task hook
        // - Configure task fees
        // - Set up task type validations
        // - Connect with main Shield Auction Hook

        vm.stopBroadcast();

        // Output the deployed contracts
        Output[] memory outputs = new Output[](1);
        outputs[0] = Output("ShieldAuctionTaskHook", address(taskHook));

        _writeOutput(environment, outputs);
    }

    function _readContext(string memory environment, string memory _context) internal view returns (Context memory) {
        string memory contextJson = vm.readFile(string.concat(".hourglass/context/", environment, ".json"));

        Context memory context;
        context.avs = contextJson.readAddress(".avs.address");
        context.avsPrivateKey = contextJson.readUint(".avs.privateKey");
        context.deployerPrivateKey = contextJson.readUint(".deployer.privateKey");
        
        // Read L2-specific configuration for connector
        context.shieldAuctionHook = contextJson.readAddress(".l2.shieldAuctionHook");  // Main hook address
        context.serviceManager = contextJson.readAddress(".l1.serviceManager");  // L1 service manager

        return context;
    }

    function _writeOutput(string memory environment, Output[] memory outputs) internal {
        string memory outputDir = string.concat(".hourglass/context/", environment, "/");
        string memory outputFile = string.concat(outputDir, "l2-contracts.json");

        string memory json = "";
        for (uint256 i = 0; i < outputs.length; i++) {
            json = vm.serializeAddress(json, outputs[i].name, outputs[i].contractAddress);
        }

        vm.writeFile(outputFile, json);
        console.log("L2 contract addresses written to:", outputFile);
    }
}

