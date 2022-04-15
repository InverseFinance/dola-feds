pragma solidity 0.8.13;

import "ds-test/test.sol";
import "src/IYearnVault.sol";
import "src/IERC20.sol";
import "src/YearnFed.sol";
import "src/test/MockYearnVault.sol";

interface CheatCodes {
    function prank(address) external;
    function startPrank(address) external;
    function stopPrank() external;
    function assume(bool) external;
}

contract MainnetForkTest is DSTest {
    CheatCodes cheats = CheatCodes(HEVM_ADDRESS);
    IYearnVault vault;
    YearnFed yearnFed;
    IERC20 underlying = IERC20(0x865377367054516e17014CcdED1e7d814EDC9ce4); //Dola
    address operator = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
    address gov = address(0xA);
    address fedChair = address(0xB);

    function setUp() public {
        //Replace with:
        //vault = IYearnVault(vaultMainnetAddress);
        //For mainnet forking against real vault 
        vault = IYearnVault(address(new MockYearnVault()));
        yearnFed = new YearnFed(vault, gov, 5, 5);
        cheats.prank(operator);
        underlying.addMinter(address(yearnFed));
        cheats.prank(gov);
        yearnFed.changeChair(fedChair);
    }

    function testSetFedChair() public{
        //Arrange
        address currentChair = yearnFed.chair();
        cheats.startPrank(gov);

        //Act
        yearnFed.changeChair(gov);

        //Assert
        assertEq(yearnFed.chair(), gov);
        assertTrue(yearnFed.chair() != currentChair);
    }

    function testExpansion_IncreaseDolasBy1ether_When_Expand1Ether() public{
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

    function testFailExpansion_Revert_When_ExpandAboveDepositLimit() public{
        //Arrange
        cheats.startPrank(fedChair);

        //Act
        yearnFed.expansion(vault.depositLimit()+1);
    }

    function testContraction_ShrinkByOneEther_When_ContractByOneEther() public{
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

    function testContractAll_ContractBy3_When_3Total() public{
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

    function testTakeProfit_DoNothing_When_NoProfit() public{
        //Arrange
        cheats.startPrank(fedChair);
        uint preGovBalance = underlying.balanceOf(gov);

        //Act
        yearnFed.expansion(1 ether);
        yearnFed.takeProfit();

        //Assert
        assertEq(underlying.balanceOf(address(gov)), preGovBalance);
    }

    function testEmergencyWithdraw_Withdraw1Dola_When_Withdrawing1Dola() public {
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

    function testFailEmergencyWithdraw_Revert_When_VaultShares() public {
        //Arrange
        cheats.prank(fedChair);
        yearnFed.expansion(1 ether);
        cheats.startPrank(gov);

        //Act
        yearnFed.emergencyWithdraw(address(vault), vault.balanceOf(address(yearnFed)));
    }
}

