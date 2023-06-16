-include .env

# deps
update:; forge update
build  :; forge build
size  :; forge build --sizes

# storage inspection
inspect :; forge inspect ${contract} storage-layout --pretty

FORK_URL := ${ETH_RPC_URL} 

# local tests without fork
test  :; forge test -vv --fork-url ${FORK_URL} --etherscan-api-key ${ETHERSCAN_API_KEY} --ffi
trace  :; forge test -vvv --fork-url ${FORK_URL} --etherscan-api-key ${ETHERSCAN_API_KEY} --ffi
gas  :; forge test --fork-url ${FORK_URL} --etherscan-api-key ${ETHERSCAN_API_KEY} --gas-report --ffi
test-contract  :; forge test -vv --match-contract $(contract) --fork-url ${FORK_URL} --etherscan-api-key ${ETHERSCAN_API_KEY} --ffi
test-contract-gas  :; forge test --gas-report --match-contract ${contract} --fork-url ${FORK_URL} --etherscan-api-key ${ETHERSCAN_API_KEY} --ffi
trace-contract  :; forge test -vvv --match-contract $(contract) --fork-url ${FORK_URL} --etherscan-api-key ${ETHERSCAN_API_KEY} --ffi
test-test  :; forge test -vv --match-test $(test) --fork-url ${FORK_URL} --etherscan-api-key ${ETHERSCAN_API_KEY} --ffi
trace-test  :; forge test -vvv --match-test $(test) --fork-url ${FORK_URL} --etherscan-api-key ${ETHERSCAN_API_KEY} --ffi

script	:; forge script script/${script} --rpc-url ${FORK_URL} --broadcast -vvv

snapshot :; forge snapshot --fork-url ${FORK_URL} --etherscan-api-key ${ETHERSCAN_API_KEY} --ffi
diff :; forge snapshot --diff --fork-url ${FORK_URL} --etherscan-api-key ${ETHERSCAN_API_KEY} --ffi
clean  :; forge clean
