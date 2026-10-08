// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DStablecoin} from "../../src/DStablecoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {OracleLib} from "../../src/OracleLib.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {MockV3Aggregator} from "../mock/MockV3Aggregator.sol";
import {MockERC20} from "../mock/MockERC20.sol";

contract DSCEngineTest is Test {
    DStablecoin dsc;
    DSCEngine engine;
    HelperConfig config;
    address wethFeed;
    address weth;
    address wbtc;

    address user = makeAddr("user");
    address liquidator = makeAddr("liquidator");

    uint256 constant COLLATERAL = 10 ether; // 10 WETH at $2,000 = $20,000
    uint256 constant MAX_SAFE_MINT = 10_000e18; // 50% liquidation threshold

    function setUp() public {
        (dsc, engine, config) = new DeployDSC().run();
        (wethFeed,, weth, wbtc,) = config.activeNetworkConfig();
        MockERC20(weth).mint(user, 100 ether);
        MockERC20(weth).mint(liquidator, 100 ether);
    }

    // ---------------------------------------------------------------- helpers

    function _deposit(address who, uint256 amount) internal {
        vm.startPrank(who);
        MockERC20(weth).approve(address(engine), amount);
        engine.depositCollateral(weth, amount);
        vm.stopPrank();
    }

    function _depositAndMint(address who, uint256 collateral, uint256 dscAmount) internal {
        vm.startPrank(who);
        MockERC20(weth).approve(address(engine), collateral);
        engine.depositCollateralAndMintDsc(weth, collateral, dscAmount);
        vm.stopPrank();
    }

    // ------------------------------------------------------------ constructor

    function test_constructor_revertsOnLengthMismatch() public {
        address[] memory tokens = new address[](2);
        address[] memory feeds = new address[](1);
        vm.expectRevert(DSCEngine.DSCEngine_tokensAndPriceFeedLengthMustBeSame.selector);
        new DSCEngine(tokens, feeds, address(dsc));
    }

    function test_constructor_revertsOnZeroDsc() public {
        vm.expectRevert(DSCEngine.DSCEngine_zeroAddress.selector);
        new DSCEngine(new address[](0), new address[](0), address(0));
    }

    // ----------------------------------------------------------------- prices

    function test_getUsdValue() public view {
        assertEq(engine.getUsdValue(weth, 15 ether), 30_000e18); // 15 * $2,000
    }

    function test_getTokenAmountFromUsd() public view {
        assertEq(engine.getTokenAmountFromUsd(weth, 100e18), 0.05 ether); // $100 / $2,000
    }

    function test_stalePrice_reverts() public {
        vm.warp(block.timestamp + 3 hours + 1);
        vm.expectRevert(OracleLib.Oracle_priceStale.selector);
        engine.getUsdValue(weth, 1 ether);
    }

    function test_nonPositivePrice_reverts() public {
        MockV3Aggregator(wethFeed).updateAnswer(0);
        vm.expectRevert(OracleLib.Oracle_invalidPrice.selector);
        engine.getUsdValue(weth, 1 ether);

        MockV3Aggregator(wethFeed).updateAnswer(-1);
        vm.expectRevert(OracleLib.Oracle_invalidPrice.selector);
        engine.getTokenAmountFromUsd(weth, 1e18);
    }

    // ---------------------------------------------------------------- deposit

    function test_deposit_updatesAccount() public {
        _deposit(user, COLLATERAL);
        (uint256 minted, uint256 collateralUsd) = engine.getAccountInformation(user);
        assertEq(minted, 0);
        assertEq(collateralUsd, 20_000e18);
        assertEq(MockERC20(weth).balanceOf(address(engine)), COLLATERAL);
    }

    function test_deposit_revertsOnZero() public {
        vm.prank(user);
        vm.expectRevert(DSCEngine.DSCEngine_moreThanZero.selector);
        engine.depositCollateral(weth, 0);
    }

    function test_deposit_revertsOnUnknownToken() public {
        MockERC20 random = new MockERC20("random", "RND", user, 100 ether);
        vm.prank(user);
        vm.expectRevert(DSCEngine.DSCEngine_tokenNotAllowed.selector);
        engine.depositCollateral(address(random), 1 ether);
    }

    // ------------------------------------------------------------------- mint

    function test_mint_works() public {
        _depositAndMint(user, COLLATERAL, 1_000e18);
        assertEq(dsc.balanceOf(user), 1_000e18);
        assertEq(dsc.totalSupply(), 1_000e18);
    }

    function test_mint_upToTheLimit() public {
        _depositAndMint(user, COLLATERAL, MAX_SAFE_MINT);
        assertEq(engine.getHealthFactor(user), 1e18);
    }

    function test_mint_revertsWhenHealthFactorBreaks() public {
        vm.startPrank(user);
        MockERC20(weth).approve(address(engine), COLLATERAL);
        // one wei over the limit pushes the health factor just below 1
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine_BreaksHealthFactor.selector, 1e18 - 1));
        engine.depositCollateralAndMintDsc(weth, COLLATERAL, MAX_SAFE_MINT + 1);
        vm.stopPrank();
    }

    function test_healthFactor_isMaxWithoutDebt() public {
        _deposit(user, COLLATERAL);
        assertEq(engine.getHealthFactor(user), type(uint256).max);
    }

    // ------------------------------------------------------------------- burn

    function test_burn_reducesDebt() public {
        _depositAndMint(user, COLLATERAL, 1_000e18);
        vm.startPrank(user);
        dsc.approve(address(engine), 400e18);
        engine.burnDsc(400e18);
        vm.stopPrank();
        (uint256 minted,) = engine.getAccountInformation(user);
        assertEq(minted, 600e18);
        assertEq(dsc.totalSupply(), 600e18);
    }

    // ----------------------------------------------------------------- redeem

    function test_redeem_withoutDebt() public {
        _deposit(user, COLLATERAL);
        uint256 before = MockERC20(weth).balanceOf(user);
        vm.prank(user);
        engine.redeemCollateral(weth, 4 ether);
        assertEq(MockERC20(weth).balanceOf(user), before + 4 ether);
    }

    function test_redeem_revertsIfItBreaksHealthFactor() public {
        _depositAndMint(user, COLLATERAL, MAX_SAFE_MINT);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine_BreaksHealthFactor.selector, 0.9e18));
        engine.redeemCollateral(weth, 1 ether);
    }

    function test_redeemCollateralForDsc_closesPosition() public {
        _depositAndMint(user, COLLATERAL, 1_000e18);
        vm.startPrank(user);
        dsc.approve(address(engine), 1_000e18);
        engine.redeemCollateralForDsc(weth, COLLATERAL, 1_000e18);
        vm.stopPrank();
        (uint256 minted, uint256 collateralUsd) = engine.getAccountInformation(user);
        assertEq(minted, 0);
        assertEq(collateralUsd, 0);
    }

    // -------------------------------------------------------------- liquidate

    function test_liquidate_revertsWhenHealthy() public {
        _depositAndMint(user, COLLATERAL, 1_000e18);
        vm.prank(liquidator);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine_PositionIsHealthy.selector, 10e18));
        engine.liquidate(weth, user, 100e18);
    }

    function test_liquidate_paysBonus() public {
        _depositAndMint(user, COLLATERAL, MAX_SAFE_MINT);
        MockV3Aggregator(wethFeed).updateAnswer(1_800e8); // ETH drops 10%, user's health factor falls to 0.9

        _depositAndMint(liquidator, 20 ether, MAX_SAFE_MINT);
        uint256 wethBefore = MockERC20(weth).balanceOf(liquidator);

        vm.startPrank(liquidator);
        dsc.approve(address(engine), MAX_SAFE_MINT);
        engine.liquidate(weth, user, MAX_SAFE_MINT);
        vm.stopPrank();

        // $10,000 of debt at $1,800/ETH is 5.555... ETH, plus a 10% bonus
        uint256 covered = engine.getTokenAmountFromUsd(weth, MAX_SAFE_MINT);
        uint256 expected = covered + covered * 10 / 100;
        assertEq(MockERC20(weth).balanceOf(liquidator) - wethBefore, expected);
        (uint256 userDebt,) = engine.getAccountInformation(user);
        assertEq(userDebt, 0);
    }

    /// Known limitation: if collateral falls below 110% of the debt, a full
    /// liquidation needs more collateral than the user has (debt plus the 10%
    /// bonus), so it reverts and the bad debt cannot be cleared.
    function test_knownLimitation_cannotLiquidateBelow110Percent() public {
        _depositAndMint(user, COLLATERAL, MAX_SAFE_MINT);
        MockV3Aggregator(wethFeed).updateAnswer(1_050e8); // collateral now worth $10,500, about 105% of the debt

        _depositAndMint(liquidator, 50 ether, MAX_SAFE_MINT);
        vm.startPrank(liquidator);
        dsc.approve(address(engine), MAX_SAFE_MINT);
        vm.expectRevert(); // underflow: needs about 10.48 ETH of the user's 10 ETH
        engine.liquidate(weth, user, MAX_SAFE_MINT);
        vm.stopPrank();
    }

    // ------------------------------------------------------------- stablecoin

    function test_dsc_onlyEngineCanMint() public {
        vm.prank(user);
        vm.expectRevert();
        dsc.mint(user, 1e18);
    }

    function test_dsc_burnFromIsDisabled() public {
        vm.expectRevert("burnFrom is disabled");
        dsc.burnFrom(user, 1e18);
    }
}
