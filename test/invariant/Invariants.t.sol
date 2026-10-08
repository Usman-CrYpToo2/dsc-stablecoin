// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DStablecoin} from "../../src/DStablecoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {MockERC20} from "../mock/MockERC20.sol";
import {Handler} from "./Handler.t.sol";

/// With prices held constant, no sequence of deposits, mints, burns and
/// redemptions should ever leave the protocol holding less collateral value
/// than the stablecoin it has issued.
contract InvariantsTest is StdInvariant, Test {
    DSCEngine engine;
    DStablecoin dsc;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() public {
        HelperConfig config;
        (dsc, engine, config) = new DeployDSC().run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        handler = new Handler(engine, dsc, weth, wbtc);
        targetContract(address(handler));
    }

    function invariant_protocolIsOvercollateralized() public view {
        uint256 collateralUsd = engine.getUsdValue(weth, MockERC20(weth).balanceOf(address(engine)))
            + engine.getUsdValue(wbtc, MockERC20(wbtc).balanceOf(address(engine)));
        assertGe(collateralUsd, dsc.totalSupply());
    }

    function invariant_everyActorIsHealthy() public view {
        for (uint256 i; i < 3; i++) {
            assertGe(engine.getHealthFactor(handler.actors(i)), 1e18);
        }
    }

    function invariant_gettersNeverRevert() public view {
        engine.getTokenAmountFromUsd(weth, 1e18);
        engine.getUsdValue(wbtc, 1e18);
    }
}
