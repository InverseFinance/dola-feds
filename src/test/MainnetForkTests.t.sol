pragma solidity 0.8.13;

import "ds-test/test.sol";
import "src/IYearnVault.sol";
import "src/test/ITestingYearnVault.sol";
import "src/IERC20.sol";
import "src/YearnFed.sol";
import "src/test/MockYearnVault.sol";

interface CheatCodes {
    function prank(address) external;
    function startPrank(address) external;
    function stopPrank() external;
    function assume(bool) external;
    function label(address, string calldata) external;
}

interface StrategyAPI {
    function name() external view returns (string memory);
    function vault() external view returns (address);
    function want() external view returns (address);
    function apiVersion() external pure returns (string memory);
    function keeper() external view returns (address);
    function isActive() external view returns (bool);
    function delegatedAssets() external view returns (uint256);
    function estimatedTotalAssets() external view returns (uint256);
    function tendTrigger(uint256 callCost) external view returns (bool);
    function tend() external;
    function harvestTrigger(uint256 callCost) external view returns (bool);
    function harvest() external;
    event Harvested(uint256 profit, uint256 loss, uint256 debtPayment, uint256 debtOutstanding);
}

contract MainnetForkTest is DSTest {
    CheatCodes cheats = CheatCodes(HEVM_ADDRESS);
    IYearnVault vault;
    YearnFed yearnFed;
    IERC20 underlying = IERC20(0x865377367054516e17014CcdED1e7d814EDC9ce4); //Dola
    address vaultAddress = 0xD4108Bb1185A5c30eA3f4264Fd7783473018Ce17;
    address operator = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
    address yearnGov = 0x0B634A8D61b09820E9F72F79cdCBc8A4D0Aad26b;
    address yearnStrat = 0x00Ca07f4012dEbb0BD17cF15B1C2841928Da0484;
    address gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
    address fedChair = address(0xB);
    uint depositLimit = 10_000_000 * 1 ether;

    function setUp() public {
        vault = IYearnVault(vaultAddress);
        //cheats.prank(yearnGov);
        //ITestingYearnVault(vaultAddress).setDepositLimit(depositLimit);
        yearnFed = YearnFed(0xcc180262347F84544c3a4854b87C34117ACADf94);//new YearnFed(vault, gov, 5, 5);
        cheats.prank(operator);
        underlying.addMinter(address(yearnFed));
        cheats.prank(gov);
        yearnFed.changeChair(fedChair);
        cheats.label(yearnStrat, "YearnStrat");
        cheats.label(vaultAddress, "Vault");
        cheats.label(address(underlying), "Dola");
    }

    function test_SetFedChair_ChangeChair_WhenSettingNewChair() public{
        //Arrange
        address currentChair = yearnFed.chair();
        cheats.startPrank(gov);

        //Act
        yearnFed.changeChair(gov);

        //Assert
        assertEq(yearnFed.chair(), gov);
        assertTrue(yearnFed.chair() != currentChair);
    }

    function test_SetMaxLossBpContraction_ChangeMaxLossBpForContraction_WhenSettingNewMaxLoss() public{
        //Arrange
        uint preMaxLossBp = yearnFed.maxLossBpContraction();
        cheats.startPrank(gov);

        //Act
        yearnFed.setMaxLossBpContraction(preMaxLossBp+1);

        //Assert
        assertEq(yearnFed.maxLossBpContraction(), preMaxLossBp+1);
    }

    function testFail_SetMaxLossBpContraction_Revert_WhenSettingNewMaxLossAbove10000() public{
        //Arrange
        cheats.startPrank(gov);

        //Act
        yearnFed.setMaxLossBpContraction(10001);
    }

    function test_SetMaxLossBpTakeProfit_ChangeMaxLossBpForTakeProfit_WhenSettingNewMaxLoss() public{
        //Arrange
        uint preMaxLossBp = yearnFed.maxLossBpTakeProfit();
        cheats.startPrank(gov);

        //Act
        yearnFed.setMaxLossBpTakeProfit(preMaxLossBp+1);

        //Assert
        assertEq(yearnFed.maxLossBpTakeProfit(), preMaxLossBp+1);
    }

    function testFail_SetMaxLossBpTakeProfit_Revert_WhenSettingNewMaxLossAbove10000() public{
        //Arrange
        cheats.startPrank(gov);

        //Act
        yearnFed.setMaxLossBpTakeProfit(10001);
    }

    function test_Expansion_IncreaseDolasBy1ether_When_Expand1Ether() public{
        //Arrange
        uint preVaultAssets = vault.totalAssets();
        uint preYearnFedShares = vault.balanceOf(address(yearnFed));
        uint preYearnFedSupply = yearnFed.supply();
        uint preDolaSupply = underlying.totalSupply();
        cheats.prank(fedChair);

        //Act
        yearnFed.expansion(1 ether);

        //Assert
        assertEq(underlying.totalSupply(), preDolaSupply + 1 ether);
        assertGt(vault.balanceOf(address(yearnFed)), preYearnFedShares);
        assertEq(vault.totalAssets(), preVaultAssets + 1 ether);       
        assertEq(yearnFed.supply(), preYearnFedSupply + 1 ether);       
    }

    function testFail_Expansion_Revert_When_ExpandAboveDepositLimit() public{
        //Arrange
        cheats.startPrank(fedChair);

        //Act
        yearnFed.expansion(vault.depositLimit()+1);
    }

    function test_Contraction_ShrinkByOneEther_When_ContractByOneEther() public{
        //Arrange
        cheats.startPrank(fedChair);
        yearnFed.expansion(3 ether);
        uint preVaultAssets = vault.totalAssets();
        uint preDolaSupply = underlying.totalSupply();
        uint preYearnFedShares = vault.balanceOf(address(yearnFed));

        //Act
        yearnFed.contraction(1 ether);

        //Assert
        assertEq(vault.totalAssets(), preVaultAssets - 1 ether);
        assertLt(vault.balanceOf(address(yearnFed)), preYearnFedShares);       
        assertEq(underlying.totalSupply(), preDolaSupply - 1 ether);
    }

    function test_ContractAll_ContractBy3_When_3Total() public{
        //Arrange
        cheats.startPrank(fedChair);
        yearnFed.expansion(3 ether);
        uint preVaultAssets = vault.totalAssets();
        uint preDolaSupply = underlying.totalSupply();
        uint preYearnFedShares = vault.balanceOf(address(yearnFed));

        //Act
        yearnFed.contractAll();

        //Assert
        assertEq(vault.totalAssets(), preVaultAssets - 3 ether);
        assertLt(vault.balanceOf(address(yearnFed)), preYearnFedShares);       
        assertEq(underlying.totalSupply(), preDolaSupply - 3 ether);
    }

    function test_Contraction_ContractWithLoss_When_DeepWithdraw() public{
        //Arrange
        StrategyAPI strategy = StrategyAPI(yearnStrat);
        cheats.startPrank(fedChair);
        yearnFed.expansion(3000 ether);
        uint preVaultAssets = vault.totalAssets();

        //Act
        cheats.startPrank(strategy.keeper());
        strategy.harvest();
        cheats.prank(gov);
        yearnFed.setMaxLossBpContraction(30);
        cheats.startPrank(fedChair);
        yearnFed.contraction(1000 ether);

        //Assert
        assertEq(vault.totalAssets(), preVaultAssets - 1000 ether);
        assertEq(vault.balanceOf(address(yearnFed)), 2000 ether);       
    }

    function test_ContractAll_ContractByAll_When_DeepWithdraw() public{
        //Arrange
        StrategyAPI strategy = StrategyAPI(yearnStrat);
        cheats.startPrank(fedChair);
        yearnFed.expansion(3000 ether);
        uint preVaultAssets = vault.totalAssets();

        //Act
        cheats.startPrank(strategy.keeper());
        strategy.harvest();
        cheats.prank(gov);
        yearnFed.setMaxLossBpContraction(30);
        cheats.startPrank(fedChair);
        yearnFed.contractAll();

        //Assert
        assertEq(vault.totalAssets(), preVaultAssets - 3000 ether);
        assertEq(vault.balanceOf(address(yearnFed)), 0);       
    }


    function test_TakeProfit_DoNothing_When_NoProfit() public{
        //Arrange
        cheats.startPrank(fedChair);
        uint preGovBalance = underlying.balanceOf(gov);

        //Act
        yearnFed.expansion(1 ether);
        yearnFed.takeProfit();

        //Assert
        assertEq(underlying.balanceOf(address(gov)), preGovBalance);
    }

    function test_EmergencyWithdraw_Withdraw1Dola_When_Withdrawing1Dola() public {
        //Arrange
        cheats.prank(operator);
        underlying.mint(address(yearnFed), 1 ether);
        uint preFedUnderlyingBalance = underlying.balanceOf(address(yearnFed));
        uint preGovUnderlyingBalance = underlying.balanceOf(gov);
        cheats.prank(gov);

        //Act
        yearnFed.emergencyWithdraw(address(underlying), 1 ether);

        //Assert
        assertEq(preFedUnderlyingBalance - 1 ether, underlying.balanceOf(address(yearnFed)));
        assertEq(preGovUnderlyingBalance + 1 ether, underlying.balanceOf(gov));
    }

    function testFail_EmergencyWithdraw_Revert_When_VaultShares() public {
        //Arrange
        cheats.prank(fedChair);
        yearnFed.expansion(1 ether);
        cheats.startPrank(gov);

        //Act
        yearnFed.emergencyWithdraw(address(vault), vault.balanceOf(address(yearnFed)));
    }
}

