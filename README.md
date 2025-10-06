# lean quickstart

A single command line quickstart to spin up lean node(s)

## Requirements

1. Shell terminal: Preferably linux especially if you want to pop out separate new terminals for node
2. Genesis configuration
3. Zeam Build (other clients to be supported soon)
4. **yq**: YAML processor for automated configuration parsing
   - Install on macOS: `brew install yq`
   - Install on Linux: See [yq installation guide](https://github.com/mikefarah/yq#install)

## Scenarios

### Quickly startup various nodes as a local devnet

```sh
NETWORK_DIR=local-devnet ./spin-node.sh --node all --freshStart --popupTerminal
```

### Startup specific nodes only

```sh
# Run only zeam_0 and ream_0 nodes (comma-separated)
NETWORK_DIR=local-devnet ./spin-node.sh --node zeam_0,ream_0 --freshStart --popupTerminal

# Run only zeam_0 and ream_0 nodes (space-separated)
NETWORK_DIR=local-devnet ./spin-node.sh --node "zeam_0 ream_0" --freshStart --popupTerminal

# Run only a single node
NETWORK_DIR=local-devnet ./spin-node.sh --node zeam_0 --freshStart --popupTerminal
```
  
## Args

1. `NETWORK_DIR` is an env to specify the network directory. Should have a `genesis` directory with genesis config. A `data` folder will be created inside this `NETWORK_DIR` if not already there.
  `genesis` directory should have the following files

    a. `validator-config.yaml` which has node setup information for all the bootnodes
    b. `validators.yaml` which assigns validator indices
    c. `nodes.yaml` which has the enrs generated for each of the respective nodes.
    d. `config.yaml` the actual network config

2. `--freshStart` reset the genesis time in the `config.yaml` to now
3. `--popupTerminal` if you want to pop out new terminals to run the nodes, opens gnome terminals
4. `--node` specify which node(s) you want to run:
   - Use `all` to run all the nodes in a single go
   - Specify a single node name (e.g., `zeam_0`) to run just that node
   - Use comma-separated node names (e.g., `zeam_0,ream_0`) to run multiple specific nodes
   - Use whitespace-separated node names (e.g., `"zeam_0 ream_0"`) to run multiple specific nodes
   
   The client is provided this input so as to parse the correct node configuration to startup the node.
5. `--validatorConfig` is the path to specify your nodes `validator-config.yaml`, `validators.yaml` (for which `--node` is still the node key to index) if your node is not a bootnode. 
3. `--generateGenesis` force regeneration of genesis files (`validators.yaml`, `nodes.yaml`, and `.key` files) from `validator-config.yaml`
4. `--popupTerminal` if you want to pop out new terminals to run the nodes, opens gnome terminals
5. `--node` specify which node you want to run, use `all` to run all the nodes in a single go, otherwise you may specify which node you want to run from `validator_config.yaml`.
  The client is provided this input so as to parse the correct node configuration to startup the node.
6. `--validatorConfig` is the path to specify your nodes `validator_config.yaml`, `validators.yaml` (for which `--node` is still the node key to index) if your node is not a bootnode.
>>>>>>> 9591164 (Integrate genesis generator to replace hardcoded configuration files)
  If unspecified it assumes value of `genesis_bootnode` which is to say that your node config is to be picked from `genesis` folder with `--node` as the node key index.
  This value is further provided to the client so that they can parse the correct config information.

## Genesis Generator

The quickstart includes an automated genesis generator that eliminates the need for hardcoded `validators.yaml` and `nodes.yaml` files.

### How It Works

The genesis generator (`generate-genesis.sh`) reads `config.yaml` and `validator-config.yaml` to automatically generate:

1. **validators.yaml** - Validator index assignments using round-robin distribution
2. **nodes.yaml** - ENR (Ethereum Node Records) for peer discovery
3. **.key files** - Private key files for each node

### Usage

The genesis generator runs automatically when:
- `validators.yaml` or `nodes.yaml` don't exist, OR
- You use the `--generateGenesis` flag

```sh
# Force regenerate genesis files
NETWORK_DIR=local-devnet ./spin-node.sh --node all --freshStart --generateGenesis
```

You can also run the generator standalone:
```sh
./generate-genesis.sh local-devnet/genesis
```

### Requirements

- **yq**: YAML processor (already required)
- **zeam-tools**: For ENR generation - build with `zig build tools -Doptimize=ReleaseFast`

### Benefits

- ✅ **No hardcoded files** - All genesis files are generated dynamically
- ✅ **Single source of truth** - `validator-config.yaml` defines everything
- ✅ **Easy to modify** - Add/remove nodes by editing `validator-config.yaml`
- ✅ **Automatic ENR generation** - No manual ENR creation needed
- ✅ **Flexible validator distribution** - Round-robin by default

## Automation Features

This quickstart now includes automated configuration parsing:

- **Genesis File Generation**: Automatically generates `validators.yaml`, `nodes.yaml`, and `.key` files
- **QUIC Port Detection**: Automatically extracts QUIC ports from `validator-config.yaml` using `yq`
- **Node Detection**: Dynamically discovers available nodes from the validator configuration
- **Private Key Management**: Automatically extracts and creates `.key` files for each node
- **ENR Generation**: Automatically generates Ethereum Node Records for peer discovery
- **Error Handling**: Provides clear error messages when nodes or ports are not found
- **No Hardcoding**: Eliminates the need for manual configuration in scripts

The system now reads all configuration from YAML files, making it easy to add new nodes or modify existing ones without changing any scripts.

## Client branches

Clients can maintain their own branches to integrated and use binay with their repos as the static targets (check `git diff main zeam_repo`). And those branches can be rebased as per client convinience whenever the `main` code is updated.
