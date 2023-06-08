-include .env

# deps
update:; forge update
build  :; forge build
size  :; forge build --sizes

# storage inspection
inspect :; forge inspect ${contract} storage-layout --pretty

FORK_URL := ${ETH_RPC_URL} 

# local tests without fork
test  :; forge test -vv --fork-url ${FORK_URL} --etherscan-api-key ${ETHERSCAN_API_KEY}
trace  :; forge test -vvv --fork-url ${FORK_URL} --etherscan-api-key ${ETHERSCAN_API_KEY}
gas  :; forge test --fork-url ${FORK_URL} --etherscan-api-key ${ETHERSCAN_API_KEY} --gas-report
test-contract  :; forge test -vv --match-contract $(contract) --fork-url ${FORK_URL} --etherscan-api-key ${ETHERSCAN_API_KEY}
test-contract-gas  :; forge test --gas-report --match-contract ${contract} --fork-url ${FORK_URL} --etherscan-api-key ${ETHERSCAN_API_KEY}
trace-contract  :; forge test -vvv --match-contract $(contract) --fork-url ${FORK_URL} --etherscan-api-key ${ETHERSCAN_API_KEY}
test-test  :; forge test -vv --match-test $(test) --fork-url ${FORK_URL} --etherscan-api-key ${ETHERSCAN_API_KEY}
trace-test  :; forge test -vvv --match-test $(test) --fork-url ${FORK_URL} --etherscan-api-key ${ETHERSCAN_API_KEY}

clean  :; forge clean
snapshot :; forge snapshot