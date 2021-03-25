# aRaiEthInsurance

# Challenge

https://gitcoin.co/issue/reflexer-labs/geb/98/100024984
To build an insurance solution where Safe owners can deposit ETH on [Aave](https://docs.aave.com/developers/the-core-protocol/atokens) and keep the received aWETH in a saviour contract. When a Safe gets liquidated, the saviour should redeem ETH from Aave and add it in the Safe.


# Solution

Created a deposit function to receive Eth and mint aWEth on Aave, and update scaled Balance of aWEth. In other implementations it makes sense to keep track of collateral cover, but balance of aWeth will keep increasing, so to track balance for each individual safe, it made sense to store scaledBalance and use it to derive collateral cover for that safe.

While withdrawing or saving safe, we can calculate underlying Eth for safe by multiplying scaled balance with (```getReserveNormalizedIncome()```) of lending pool.

Created a withdrawal function which redeems aWeth tokens in exchange of Eth and transfer it back to caller of the function, hence owner of safe should be careful in giving access to his safe, because it will also give him access to withdraw collateral kept in aRaiEthInsurance

When liquidation occurs, liquidation engine calls saveSafe function of saviour method, which calculates amount of collateral required to save safe and then, call withdrawEth function of WEthGateway to get required collateral which is Eth back, and then convert it into WETH and approve amount required for collateral join, and then we mark it save in SaviourRegistry and modifySafeCollateralization of safeEngine and repay keeper the reward amount


# Kovan Testing
Contract Address for Kovan: https://kovan.etherscan.io/address/0x7dbb19d664445f39b8ef4ebee8a76af949b2511b

Min Keeper Payout: 50 USD

Keeper Payout: 0.1 eth

In liquidation call 0.0157884 ether was total spent on gas, given 25 Gwei as gas cost, if we scale it to 150 Gwei gas cost on mainnet, it comes to be about 0.09 eth, giving 0.01 eth as profit for keeper. We can increase this value more to a more acceptable number, but keeping it atleast 0.1 eth looks like good idea to ensure proper incentive for keeper

payoutToSAFESize: 20 (was kept 20 for testing purpose, can be increased to 50 or 100, and should be adjustable for each safe)

Created a safe with id: 218

Collateral : 2.2 Eth

Debt : 768.57 RAI

[Attached saviour for safe](https://kovan.etherscan.io/tx/0x1ad27f7d09bedf590e63a009c2377d2ae0c2268a4da8e03645de14d0163a86f0)

[Deposited 0.4 eth in insurance contract](https://kovan.etherscan.io/tx/0x6d59af5d7ac61b75b0419336fdb9f088979143efb9940e7d362cea220e8f998d)
aWEth minted : 0.4

On collateral price below 145%, I triggered liquidateSafe method of Liquidation Engine
https://kovan.etherscan.io/tx/0xecdf8ab730e775c805b1c70b1561cc5d88d3308c40d34db2c85b3991fff70ddb
aRaiEthInsurance contract redeemed 0.340769837365782227 aWEth for 0.340769837365782227 eth, and transferred 0.1 eth to keeper and left to change collateral ration to 160
