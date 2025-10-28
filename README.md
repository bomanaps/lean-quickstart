# lean quickstart

A single command line quickstart to spin up lean node(s)

### Benefits

- ✅ **Official Tool**: Uses PK's `eth-beacon-genesis` docker tool (not custom tooling)
- ✅ **Complete Genesis State**: Generates full genesis state (JSON + SSZ) plus config files
- ✅ **No hardcoded files** - All genesis files are generated dynamically
- ✅ **Single source of truth** - `validator-config.yaml` defines everything
- ✅ **Easy to modify** - Add/remove nodes by editing `validator-config.yaml`
- ✅ **Standards compliant** - Uses ethpandaops maintained tool

### Requirements

1. Shell terminal: Preferably linux especially if you want to pop out separate new terminals for node
2. Genesis configuration
3. Zeam Build (other clients to be supported soon)
4. **Docker**: Required to run PK's eth-beacon-genesis tool
   - Install from: [Docker Desktop](https://docs.docker.com/get-docker/)
5. **yq**: YAML processor for automated configuration parsing
   - Install on macOS: `brew install yq`
   - Install on Linux: See [yq installation guide](https://github.com/mikefarah/yq#install)
6. **Rust/Cargo**: Required to build the hash-sig-cli tool for post-quantum keys
   - Install from: [https://rustup.rs/](https://rustup.rs/)

## Quick Start

### First Time Setup:
```sh
# 1. Clone the repository
git clone <repo-url>
cd lean-quickstart

# 2. Initialize hash-sig-cli submodule
git submodule update --init --recursive

# 3. **Run** genesis generation:
./generate-genesis.sh local-devnet/genesis
```

## Scenarios

### Quickly startup various nodes as a local devnet

```sh
NETWORK_DIR=local-devnet ./spin-node.sh --node all --generateGenesis --popupTerminal
```

### Startup specific nodes only

```sh
# Run only zeam_0 and ream_0 nodes (comma-separated)
NETWORK_DIR=local-devnet ./spin-node.sh --node zeam_0,ream_0 --generateGenesis --popupTerminal

# Run only zeam_0 and qlean_0 nodes (space-separated)
NETWORK_DIR=local-devnet ./spin-node.sh --node "zeam_0 qlean_0" --generateGenesis --popupTerminal

# Run only a single node
NETWORK_DIR=local-devnet ./spin-node.sh --node zeam_0 --generateGenesis --popupTerminal
```
  
## Args

1. `NETWORK_DIR` is an env to specify the network directory. Should have a `genesis` directory with genesis config. A `data` folder will be created inside this `NETWORK_DIR` if not already there.
  `genesis` directory should have the following files

    a. `validator-config.yaml` which has node setup information for all the bootnodes
    b. `validators.yaml` which assigns validator indices
    c. `nodes.yaml` which has the enrs generated for each of the respective nodes.
    d. `config.yaml` the actual network config

2. `--generateGenesis` regenerate all genesis files with fresh genesis time and clean data directories
3. `--popupTerminal` if you want to pop out new terminals to run the nodes, opens gnome terminals
4. `--node` specify which node(s) you want to run:
   - Use `all` to run all the nodes in a single go
   - Specify a single node name (e.g., `zeam_0`) to run just that node
   - Use comma-separated node names (e.g., `zeam_0,qlean_0`) to run multiple specific nodes
   - Use whitespace-separated node names (e.g., `"zeam_0 ream_0"`) to run multiple specific nodes
   
   The client is provided this input so as to parse the correct node configuration to startup the node.
5. `--validatorConfig` is the path to specify your nodes `validator-config.yaml`, `validators.yaml` (for which `--node` is still the node key to index) if your node is not a bootnode.
   If unspecified it assumes value of `genesis_bootnode` which is to say that your node config is to be picked from `genesis` folder with `--node` as the node key index.
   This value is further provided to the client so that they can parse the correct config information.

## Genesis Generator

The quickstart includes an automated genesis generator that eliminates the need for hardcoded `validators.yaml` and `nodes.yaml` files.

### Clients supported

Current following clients are supported:

1. Zeam
2. Ream
3. Qlean

However adding a lean client to this setup is very easy. Feel free to do the PR or reach out to the maintainers.

### How It Works

The genesis generator (`generate-genesis.sh`) uses PK's official `eth-beacon-genesis` docker tool to automatically generate:

1. **validators.yaml** - Validator index assignments using round-robin distribution
2. **nodes.yaml** - ENR (Ethereum Node Records) for peer discovery
3. **genesis.json** - Genesis state in JSON format
4. **genesis.ssz** - Genesis state in SSZ format
5. **.key files** - Private key files for each node

**Docker Image**: `ethpandaops/eth-beacon-genesis:pk910-leanchain`  
**Source**: https://github.com/ethpandaops/eth-beacon-genesis/pull/36

### Usage

The genesis generator runs automatically when:
- `validators.yaml` or `nodes.yaml` don't exist, OR
- You use the `--generateGenesis` flag

```sh
# Regenerate genesis files with fresh genesis time
NETWORK_DIR=local-devnet ./spin-node.sh --node all --generateGenesis
```

You can also run the generator standalone:
```sh
./generate-genesis.sh local-devnet/genesis
```

## Hash-Based Signature (Post-Quantum) Validator Keys

This quickstart includes integrated support for **post-quantum secure hash-based signatures** for validator keys. The system automatically generates and manages hash-sig keys during genesis generation.

### How It Works

The genesis generator automatically:
1. **Builds hash-sig-cli** (if not already built) from the submodule
2. **Generates hash-sig keys** for N validators (Step 1 of genesis generation)
3. **Stores keys** in `genesis/hash-sig-keys/` directory
4. **Loads keys** automatically when nodes start via environment variables

### Key Generation

When you run the genesis generator, it creates post-quantum secure keys for each validator:

```sh
./generate-genesis.sh local-devnet/genesis
```

**Generated files:**
```
local-devnet/genesis/hash-sig-keys/
├── validator-keys-manifest.yaml    # Metadata for all keys
├── validator_0_pk.json             # Public key for validator 0
├── validator_0_sk.json             # Secret key for validator 0
├── validator_1_pk.json             # Public key for validator 1
├── validator_1_sk.json             # Secret key for validator 1
└── ...                             # Keys for additional validators
```

### Signature Scheme

The system uses the **SIGTopLevelTargetSumLifetime32Dim64Base8** hash-based signature scheme, which provides:

- **Post-quantum security**: Resistant to attacks from quantum computers
- **Active epochs**: 2^18 (262,144 signatures)
- **Total lifetime**: 2^32 (4,294,967,296 signatures)
- **Stateful signatures**: Uses hierarchical signature tree structure

### Configuration

Each validator in `validator-config.yaml` must specify its hash-sig configuration:

```yaml
validators:
  - name: "zeam_0"
    privkey: "bdf953adc161873ba026330c56450453f582e3c4ee6cb713644794bcfdd85fe5"
    keyType: "hash-sig"         # Required: Indicates using hash-sig keys
    hashSigKeyIndex: 0          # Required: Index into generated keys (0, 1, 2, ...)
    enrFields:
      ip: "127.0.0.1"
      quic: 9000
    metricsPort: 8080
    count: 1
```

**Key Fields:**
- `keyType`: Must be set to `"hash-sig"` for post-quantum keys
- `hashSigKeyIndex`: Index number mapping to `validator_{index}_pk.json` and `validator_{index}_sk.json`

### Key Loading

The `parse-vc.sh` script automatically loads hash-sig keys when starting nodes:

1. Reads `keyType` and `hashSigKeyIndex` from validator config
2. Locates corresponding key files in `genesis/hash-sig-keys/`
3. Exports environment variables for client use:
   - `HASH_SIG_PK_PATH`: Path to public key file
   - `HASH_SIG_SK_PATH`: Path to secret key file
   - `HASH_SIG_KEY_INDEX`: Validator's key index

**Client Integration:**

Your client implementation should read these environment variables and use the hash-sig keys for validator operations.

### Key Management

#### Key Lifetime

Each hash-sig key has a **finite lifetime** of 2^32 signatures. The keys are structured as:
- **Active epochs**: 2^18 epochs before requiring key rotation
- **Total lifetime**: 2^32 total signatures possible

#### Key Rotation

Hash-based signatures are **stateful** - each signature uses a unique one-time key from the tree. Once exhausted, keys must be rotated:

```sh
# Regenerate all hash-sig keys
./generate-genesis.sh local-devnet/genesis
```

**Warning**: Keep track of signature counts to avoid key exhaustion.

#### Key Security

**Secret keys are highly sensitive:**
- ⚠️ **Never commit** `validator_*_sk.json` files to version control
- ⚠️ **Never share** secret keys
- ✅ **Backup** secret keys in secure, encrypted storage
- ✅ **Restrict permissions** on key files (e.g., `chmod 600`)

The `.gitignore` should already exclude hash-sig keys:
```
local-devnet/genesis/hash-sig-keys/
```

### Verifying Keys

The manifest file (`validator-keys-manifest.yaml`) contains metadata about all generated keys:

```yaml
# Hash-Sig Validator Keys Manifest
# Generated: 2024-01-15T10:30:00Z

scheme: "SIGTopLevelTargetSumLifetime32Dim64Base8"
activeEpochs: 262144  # 2^18
totalLifetime: 4294967296  # 2^32
validatorCount: 3

validators:
  - index: 0
    publicKey: "validator_0_pk.json"
    secretKey: "validator_0_sk.json"
  - index: 1
    publicKey: "validator_1_pk.json"
    secretKey: "validator_1_sk.json"
  # ... additional validators
```

### Troubleshooting

**Problem**: `hash-sig-cli submodule not found`
```
❌ Error: hash-sig-cli submodule not found at tools/hash-sig-cli
```

**Solution**: Initialize the git submodule:
```sh
git submodule update --init --recursive
```

---

**Problem**: `Failed to build hash-sig-cli`
```
❌ Error: Failed to build hash-sig-cli
```

**Solution**: Make sure Rust/Cargo is installed:
```sh
# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Then run genesis generation again
./generate-genesis.sh local-devnet/genesis
```

---

**Problem**: Hash-sig keys not loading during node startup
```
Warning: Hash-sig public key not found at genesis/hash-sig-keys/validator_0_pk.json
```

**Solution**: Run the genesis generator to create keys:
```sh
./generate-genesis.sh local-devnet/genesis
```

---

**Problem**: Wrong key index in validator config
```
Warning: Hash-sig secret key not found at genesis/hash-sig-keys/validator_5_sk.json
```

**Solution**: Ensure `hashSigKeyIndex` in `validator-config.yaml` matches an existing validator index (0 to N-1).

## Automation Features

This quickstart includes automated configuration parsing:

- **Official Genesis Generation**: Uses PK's `eth-beacon-genesis` docker tool from [PR #36](https://github.com/ethpandaops/eth-beacon-genesis/pull/36)
- **Complete File Set**: Generates `validators.yaml`, `nodes.yaml`, `genesis.json`, `genesis.ssz`, and `.key` files
- **QUIC Port Detection**: Automatically extracts QUIC ports from `validator-config.yaml` using `yq`
- **Node Detection**: Dynamically discovers available nodes from the validator configuration
- **Private Key Management**: Automatically extracts and creates `.key` files for each node
- **Error Handling**: Provides clear error messages when nodes or ports are not found

The system reads all configuration from YAML files, making it easy to add new nodes or modify existing ones without changing any scripts.

## Client branches

Clients can maintain their own branches to integrated and use binay with their repos as the static targets (check `git diff main zeam_repo`). And those branches can be rebased as per client convinience whenever the `main` code is updated.
