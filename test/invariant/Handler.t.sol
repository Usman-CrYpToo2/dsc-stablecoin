// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DStablecoin} from "../../src/DStablecoin.sol";
import {MockERC20} from "../mock/MockERC20.sol";

/// Drives the engine with random but valid actions, so the fuzzer explores
/// real user flows instead of reverting on nonsense inputs.
contract Handler is Test {
    DSCEngine engine;
    DStablecoin dsc;
    MockERC20[2] collateral;
    address[] public actors;

    uint256 constant MAX_DEPOSIT = 1_000_000 ether;

    constructor(DSCEngine _engine, DStablecoin _dsc, address weth, address wbtc) {
        engine = _engine;
        dsc = _dsc;
        collateral[0] = MockERC20(weth);
        collateral[1] = MockERC20(wbtc);
        for (uint256 i; i < 3; i++) {
            actors.push(makeAddr(string(abi.encode("actor", i))));
        }
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _token(uint256 seed) internal view returns (MockERC20) {
        return collateral[seed % 2];
    }

    function deposit(uint256 actorSeed, uint256 tokenSeed, uint256 amount) external {
        address actor = _actor(actorSeed);
        MockERC20 token = _token(tokenSeed);
        amount = bound(amount, 1, MAX_DEPOSIT);
        token.mint(actor, amount);
        vm.startPrank(actor);
        token.approve(address(engine), amount);
        engine.depositCollateral(address(token), amount);
        vm.stopPrank();
    }

    function mint(uint256 actorSeed, uint256 amount) external {
        address actor = _actor(actorSeed);
        (uint256 minted, uint256 collateralUsd) = engine.getAccountInformation(actor);
        uint256 maxMint = collateralUsd / 2; // 50% liquidation threshold
        if (maxMint <= minted) return;
        amount = bound(amount, 1, maxMint - minted);
        vm.prank(actor);
        engine.mintDsc(amount);
    }

    function burn(uint256 actorSeed, uint256 amount) external {
        address actor = _actor(actorSeed);
        uint256 balance = dsc.balanceOf(actor);
        if (balance == 0) return;
        amount = bound(amount, 1, balance);
        vm.startPrank(actor);
        dsc.approve(address(engine), amount);
        engine.burnDsc(amount);
        vm.stopPrank();
    }

    function redeem(uint256 actorSeed, uint256 tokenSeed, uint256 amount) external {
        address actor = _actor(actorSeed);
        MockERC20 token = _token(tokenSeed);
        uint256 deposited = engine.s_CollateralDeposits(actor, address(token));
        if (deposited == 0) return;
        amount = bound(amount, 1, deposited);
        (uint256 minted, uint256 collateralUsd) = engine.getAccountInformation(actor);
        // only redeem what keeps the position healthy
        if ((collateralUsd - engine.getUsdValue(address(token), amount)) / 2 < minted) return;
        vm.prank(actor);
        engine.redeemCollateral(address(token), amount);
    }
}
