// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "ds-test/test.sol";
import "forge-std/Vm.sol";
import "src/ConvexFed.sol";
import "src/IMetaPool.sol";
import "src/IZapDepositor3pool.sol";
import "src/IERC20.sol";
import "src/IConvexBooster.sol";
import "src/IConvexBaseRewardPool.sol";

interface IMinted is IERC20 {
    function addMinter(address minter_) external;
    function removeMinter(address minter_) external;
    function mint(address to, uint amount) external;
}

contract ConvexFedTest is DSTest {
    Vm internal constant vm = Vm(HEVM_ADDRESS);
    uint public convexPID = 62;
    IConvexBooster public convexBooster = IConvexBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    IConvexBaseRewardPool public baseRewardPool = IConvexBaseRewardPool(0x835f69e58087E5B6bffEf182fe2bf959Fe253c3c);
    IMetaPool public crvPool = IMetaPool(0xAA5A67c256e27A5d80712c51971408db3370927D);
    IZapDepositor3pool public zapDepositor = IZapDepositor3pool(0xA79828DF1850E8a3A3064576f380D90aECDD3359);
    ConvexFed public convexFed;
    IMinted public dola = IMinted(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IERC20 public crv = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    IERC20 public cvx = IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    IERC20 public crv3 = IERC20(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490);
    address public gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
    address public chair = address(0xB);
    address public dolaFaucet = address(0xF);
    uint public maxLossExpansionBps = 100;
    uint public maxLossWithdrawBps = 100;
    uint public maxLossTakeProfitBps = 100;

    function setUp() public {
        convexFed = new ConvexFed(
            address(dola),
            address(crv),
            address(cvx),
            address(crvPool),
            address(zapDepositor),
            address(convexBooster),
            address(baseRewardPool),
            gov,
            maxLossExpansionBps,
            maxLossWithdrawBps,
            maxLossTakeProfitBps,
            convexPID
        );
        vm.startPrank(gov);
        convexFed.changeChair(chair);
        dola.addMinter(address(convexFed));
        dola.addMinter(dolaFaucet);
        vm.stopPrank();
        vm.label(0xF403C135812408BFbE8713b5A23a04b3D48AAE31, "convex booster");
        vm.label(0x3Fe65692bfCD0e6CF84cB1E7d24108E434A7587e, "convex base reward pool");
        vm.label(0xAA5A67c256e27A5d80712c51971408db3370927D, "DOLA-3CRV");
        vm.label(0x865377367054516e17014CcdED1e7d814EDC9ce4, "dola");
        vm.label(0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7, "crv");
        vm.label(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B, "cvx");
    }

    function testExpansion_succeed_whenExpandedWithinAcceptableSlippage() public {
        uint initialDolaSupply = convexFed.dolaSupply();
        uint initialCrvLpSupply = convexFed.crvLpSupply();
        uint initialDolaTotalSupply = dola.totalSupply();
        uint amount = 10 ether;

        vm.prank(chair);
        convexFed.expansion(amount);

        assertEq(initialDolaTotalSupply + amount, dola.totalSupply());
        assertEq(initialDolaSupply + amount, convexFed.dolaSupply());
        //TODO: Should have greater precision about the amount of crvLP acquired
        assertGt(convexFed.crvLpSupply(), initialCrvLpSupply);
    }

    function testFailExpansion_fail_whenExpandedOutsideAcceptableSlippage() public {
        uint amount = 1000_000_000 ether;

        vm.prank(chair);
        convexFed.expansion(amount);
    }

    function testContraction_succeed_whenContractedWithinAcceptableSlippage(uint amount) public {
        vm.assume(amount < 10_000_000 * 10**18);
        vm.assume(amount > 10**18);
        vm.prank(chair);
        convexFed.expansion(amount*2);
        uint initialDolaSupply = convexFed.dolaSupply();
        uint initialDolaTotalSupply = dola.totalSupply();
        uint initialCrvLpSupply = convexFed.crvLpSupply();

        vm.prank(chair);
        convexFed.contraction(amount);

        //Make sure basic accounting of contraction is correct:
        assertGt(initialCrvLpSupply, convexFed.crvLpSupply());
        assertGt(initialDolaSupply, convexFed.dolaSupply());
        assertGt(initialDolaTotalSupply, dola.totalSupply());
        assertEq(initialDolaTotalSupply - dola.totalSupply(), initialDolaSupply - convexFed.dolaSupply());

        //Make sure maxLoss wasn't exceeded
        assertLe(initialDolaSupply-convexFed.dolaSupply(), amount*10_000/(10_000-maxLossWithdrawBps), "Amount withdrawn exceeds maxloss"); 
        assertLe(initialDolaTotalSupply-dola.totalSupply(), amount*10_000/(10_000-maxLossWithdrawBps), "Amount withdrawn exceeds maxloss");
        uint percentageToWithdraw = initialDolaSupply * 10**18 / amount;
        uint percentageActuallyWithdrawnCrv = initialCrvLpSupply * 10**18 / (initialCrvLpSupply - convexFed.crvLpSupply());
        assertLe(percentageActuallyWithdrawnCrv * (10_000 - maxLossWithdrawBps) / 10_000, percentageToWithdraw, "Too much crvLP spent");
    }

    function testFailContraction_fail_whenContractedOutsideAcceptableSlippage() public {
        uint amount = 1000_000 ether;

        vm.startPrank(chair);
        convexFed.expansion(amount);
        convexFed.setMaxLossWithdrawBps(0);
        convexFed.contraction(amount);
        vm.stopPrank();
    }

    function testTakeProfit_NoProfit_whenCallingWhenUnprofitable() public {
        vm.startPrank(chair);
        convexFed.expansion(1000_000 ether);
        uint initialCvx = cvx.balanceOf(gov);
        uint initialCvxCrv = crv.balanceOf(gov);
        uint initialCrvLpSupply = convexFed.crvLpSupply();
        uint initialGovDola = dola.balanceOf(gov);
        convexFed.takeProfit(true);
        vm.stopPrank();

        assertEq(cvx.balanceOf(gov), initialCvx, "treasury cvx balance didn't increase");
        assertEq(crv.balanceOf(gov), initialCvxCrv, "treasury crv balance din't increase");
        assertEq(initialCrvLpSupply, convexFed.crvLpSupply());
        assertEq(dola.balanceOf(gov), initialGovDola);
    }

    function testTakeProfit_IncreaseGovCrvCvxBalance_whenCallingWithoutHarvestLpFlag() public {
        vm.startPrank(chair);
        convexFed.expansion(1000_000 ether);
        uint initialCvx = cvx.balanceOf(gov);
        uint initialCvxCrv = crv.balanceOf(gov);
        uint initialCrvLpSupply = convexFed.crvLpSupply();
        uint initialGovDola = dola.balanceOf(gov);
        //Pass time
        vm.warp(baseRewardPool.periodFinish() + 1);
        convexFed.takeProfit(false);
        vm.stopPrank();

        assertGt(cvx.balanceOf(gov), initialCvx, "treasury cvx balance didn't increase");
        assertGt(crv.balanceOf(gov), initialCvxCrv, "treasury crv balance din't increase");
        assertEq(initialCrvLpSupply, convexFed.crvLpSupply());
        assertEq(dola.balanceOf(gov), initialGovDola);
    }

    function testTakeProfit_IncreaseGovDolaBalance_whenCallingWithHarvestLpFlag() public {
        vm.prank(chair);
        convexFed.expansion(1000_000 ether);
        uint initialCrvLpSupply = convexFed.crvLpSupply();
        uint initialGovDola = dola.balanceOf(gov);
        uint input = 10_000_000 ether;
        vm.startPrank(dolaFaucet);
        dola.mint(dolaFaucet, input);
        //Trade back and forth to create a profit
        dola.approve(address(crvPool), type(uint).max);
        crv3.approve(address(crvPool), type(uint).max);
        for(uint i; i < 100; i++){
            uint received = crvPool.exchange(0, 1, input, 1);
            input = crvPool.exchange(1,0, received, 1);
        }
        vm.stopPrank();
        vm.prank(chair);
        convexFed.takeProfit(true);

        assertGt(dola.balanceOf(gov), initialGovDola);
        assertGt(initialCrvLpSupply, convexFed.crvLpSupply());
    }

    function testExpansion_FailWithOnlyChair_whenCalledByOtherAddress() public {
        vm.prank(dolaFaucet);
        vm.expectRevert("ONLY CHAIR");
        convexFed.expansion(1000);
    }

    function testContraction_FailWithOnlyChair_whenCalledByOtherAddress() public {
        vm.prank(dolaFaucet);
        vm.expectRevert("ONLY CHAIR");
        convexFed.contraction(1000);
    }

    function testTakeProfit_FailWithOnlyChair_whenCalledByOtherAddress() public {
        vm.prank(dolaFaucet);
        vm.expectRevert("ONLY CHAIR");
        convexFed.takeProfit(true);
    }

    function testSetMaxLossExpansionBps_succeed_whenCalledByGov() public {
        uint initial = convexFed.maxLossExpansionBps();
        
        vm.prank(gov);
        convexFed.setMaxLossExpansionBps(1);

        assertEq(convexFed.maxLossExpansionBps(), 1);
        assertTrue(initial != convexFed.maxLossExpansionBps());
    }

    function testSetMaxLossWithdrawBps_succeed_whenCalledByGov() public {
        uint initial = convexFed.maxLossWithdrawBps();
        
        vm.prank(gov);
        convexFed.setMaxLossWithdrawBps(1);

        assertEq(convexFed.maxLossWithdrawBps(), 1);
        assertTrue(initial != convexFed.maxLossWithdrawBps());
    }

    function testSetMaxLossTakeProfitBps_succeed_whenCalledByGov() public {
        uint initial = convexFed.maxLossTakeProfitBps();
        
        vm.prank(gov);
        convexFed.setMaxLossTakeProfitBps(1);

        assertEq(convexFed.maxLossTakeProfitBps(), 1);
        assertTrue(initial != convexFed.maxLossTakeProfitBps());
    }

    function testSetMaxLossExpansionBps_fail_whenCalledByNonGov() public {
        uint initial = convexFed.maxLossExpansionBps();
        
        vm.expectRevert("ONLY GOV");
        convexFed.setMaxLossExpansionBps(1);

        assertEq(convexFed.maxLossExpansionBps(), initial);
    }

    function testSetMaxLossWithdrawBps_fail_whenCalledByGov() public {
        uint initial = convexFed.maxLossWithdrawBps();
        
        vm.expectRevert("ONLY GOV");
        convexFed.setMaxLossWithdrawBps(1);

        assertEq(convexFed.maxLossWithdrawBps(), initial);
    }

    function testSetMaxLossTakeProfitBps_fail_whenCalledByGov() public {
        uint initial = convexFed.maxLossTakeProfitBps();
        
        vm.expectRevert("ONLY GOV");
        convexFed.setMaxLossTakeProfitBps(1);

        assertEq(convexFed.maxLossTakeProfitBps(), initial);
    }
}

