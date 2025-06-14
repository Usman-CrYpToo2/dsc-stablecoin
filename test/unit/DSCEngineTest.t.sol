// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DStablecoin} from "../../src/DStablecoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import { HelperConfig } from "../../script/HelperConfig.s.sol";
import {MockV3Aggregator} from "../mock/Mockv3Aggregator.sol";
import {MockERC20} from "../mock/MockERC20.sol";
import {console} from "forge-std/Console.sol";

contract DSCEngineTest is Test {
     DeployDSC public deployer;
     DStablecoin public dsc;
     DSCEngine public dse ;
     HelperConfig public config ;
     address public wethPriceFeed;
     address public weth;
     address public user;
    //  MockV3Aggregator public btcPriceFeed;
    //  MockERC20 public btc;

     function setUp() public {
         deployer = new DeployDSC();
         (dsc, dse, config) = deployer.run();  
          (wethPriceFeed, , weth ,, ) = config.activeNetworkConfig();
          user = makeAddr("user");
           MockERC20(weth).mint(user, 100 ether);
     } 


     function test_getUsdValue() public view {
        uint256 eth_amount = 0.1 ether;
         uint256 usdValue = dse.getUsdValue(weth, eth_amount);
         console.log(usdValue / 1e18);
     }

     function test_getCollateralAmount() public view {
         uint256 usdValue = 1000e18;
         uint256 collateralAmount = dse.getTokenAmountFromUsd(weth, usdValue);
         console.log(collateralAmount);
     }
      
      modifier depositCollateral() {
          vm.startPrank(user);
          MockERC20(weth).approve(address(dse), 100 ether);
          dse.depositCollateral(weth, 1 ether);
          vm.stopPrank();
          _;
      }
     function test_depositCollateralAndGetAccountInformation() public depositCollateral() {
          (uint256 totalDscMinted, uint256 collateralInUsd ) = dse._getAccountInformation(user);
           console.log(collateralInUsd / 1 ether);
     }


}