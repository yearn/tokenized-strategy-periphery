# Tokenized Strategy Periphery Contracts

This repo contains the option contracts that can be used for any Yearn V3 tokenized strategy to make strategy development even easier.

## How to start

### Requirements
First you will need to install [Foundry](https://book.getfoundry.sh/getting-started/installation).
NOTE: If you are on a windows machine it is recommended to use [WSL](https://learn.microsoft.com/en-us/windows/wsl/install)

### Fork this repository

    git clone --recursive https://github.com/user/tokenized-strategy-periphery

    cd tokenized-strategy-periphery

    yarn


### Set your environment Variables

Sign up for [Infura](https://infura.io/) and generate an API key and copy your RPC url. Store it in the `ETH_RPC_URL` environment variable.
NOTE: you can use other services.

Use .env file
  1. Make a copy of `.env.example`
  2. Add the values for `ETH_RPC_URL`, `ETHERSCAN_API_KEY` and other example vars
     NOTE: If you set up a global environment variable, that will take precedence.


### Build the project.

```sh
make build
```

Run tests
```sh
make test
```

### Deployment

Deployment of periphery contracts such as the [Apr Oracle](https://github.com/yearn/tokenized-strategy-periphery/blob/master/src/AprOracle/AprOracle.sol) or [Common Report Trigger](https://github.com/yearn/tokenized-strategy-periphery/blob/master/src/ReportTrigger/CommonReportTrigger.sol) are done using a create2 factory in order to get a deterministic address that is the same on each EVM chain.

This can be done permissionlessly if the most recent contract has not yet been deployed on a chain you would like to use it on.

1. Add your deployers Private key under PRIVATE_KEY in your .env file.
     - NOTE: make sure to add `0x` to the beginning of the key.
2. Run the deployment script for the contract you want to deploy.
    ```sh
    forge script script/DeployContractName.s.sol:DeployContractName --broadcast --rpc-url YOUR_RPC_URL
    ```
    - You can do a dry run before officially deploying by removing the `--broadcast` flag.
    - For chains that don't support 1559 tx's you may need to add a `--legacy` flag.
3. The address the contract was deployed at will print in the console and should match any other chain the same version has been deployed on.

## Swapper helper contracts

For strategies that need to swap reward tokens back into 'asset' a series of 'swapper' contracts have been pre-developed to make your preferred method as easy as possible to use.

For example if you want to use Uniswap V3 for swapping you can simply inherit the UniswapV3Swapper.sol, set the needed global variables for your specific strategy, then use the default syntax to swap any 'fromToken' to any 'toToken'.

EX:

    contract Strategy is UniswapV3Swapper, BaseTokenizedStrategy {
    
        ...
        
        ...
        
        function _harvestAndReport() internal override returns (uint256) {
            ... Claim rewards
            
            uint256 rewardBalance = ERC20(rewardToken).balanceOf(address(this));
            _swapFrom(rewardToken, asset, rewardBalance, minAmountOut);
            
            ... reinvest and return the '_totalAssets'
        }
    }
    
NOTE: Its very important to read through all the comments in the swapper contract you use to assure all needed variables are set and any external setter functions that are needed are implemented.

## HealthCheck
Health Checks can be used by a strategy to assure automated reports are not unexpectedly reporting a loss or a extreme profit that a strategist doesn't expect.

It's important to note that the health check does not stop losses from being reported, rather will require manual intervention from 'management' for out of range losses or gains.

A strategist simply has to inherit the [BaseHealthCheck](https://github.com/yearn/tokenized-strategy-periphery/blob/master/src/HealthCheck/BaseHealthCheck.sol) contract in their strategy, set the profit and loss limit ratios with the needed setters, and then override `_harvestAndReport()` just as they otherwise would. If the profit or loss that would be recorded is outside the acceptable bounds the tx will revert.

The profit and loss ratios can adjusted by management through their specific setters as well as turning the healthCheck off for a specific report. If turned off the health check will automatically turn back on for the next report.

## Apr Oracle
For easy integration with on chain debt allocator's as well as off chain interfaces, strategist's can implement their own custom 'AprOracle'.

The goal of the APR oracle to is to return the expected current APY the strategy is expecting to be earning given some `debtChange`.


## Report Triggers
The default use of the Tokenized Strategies and V3 Vaults is for report cycles to be based off of the individual `maxProfitUnlockTime`. The triggers are an easy way for keepers to monitor the status of each strategy and know when `report` should be called on each.

However, if a strategist wants to implement a custom trigger for their strategy or vault you can use the simple `CustomTriggerBase` contracts to inherit the proper interface. Then return the expected APY represented as 1e18 (1e17 == 10%).
