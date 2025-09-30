# sbcc-hpl-benchmarking

Reproducible benchmarking of Single Board Computer (SBC) clusters using the High Performance Linpack (HPL) benchmark with ATLAS and OpenBLAS on ARM-based platforms.

## Overview

This repository provides a complete, automated framework for benchmarking HPL on SBC clusters. It supports building optimized ATLAS BLAS libraries, compiling HPL with custom configurations, distributing builds across nodes, and executing HPL runs while collecting performance metrics and throttling data. The setup is designed for reproducibility and extensibility to new SBC platforms.

### Key features

- **Automated Builds**: Parallel compilation of ATLAS and HPL across cluster nodes.  
- **Distributed Execution**: MPI-based HPL runs with configurable parameters (N, NB, P, Q, runs).  
- **Throttling Monitoring**: Tracks CPU throttling during runs for accurate performance analysis.  
- **Configurable**: Platform-specific configs allow easy adaptation to new SBCs (e.g., Raspberry Pi, Odroid).  
- **Reproducibility**: All scripts, configs, and logs ensure experiments can be repeated.  

## 📁 Repository Structure

```
sbcc-hpl-benchmarking/
├── scripts/
│   ├── executor.sh
│   ├── atlas_build/
│   │   ├── build-atlases.sh
│   │   ├── builds_info/
│   ├── hpl_build/
│   │   ├── build-hpl.sh
│   │   ├── Make.generic
│   ├── HPL_run/
│   │   ├── HPL-execute.sh
│   ├── stage-builds.sh
│   ├── throttling/
│   │   ├── get_throttling.sh
│   │   ├── get_throttling_helper.sh
│   ├── wait/
│   │   ├── waitScript.sh
│   └── config-files/
│       ├── base-config.txt
│       └── raspi5B/
├── raw-results/
├── processed-results/
└── README.md
```

## ⚙️ Requirements

### Hardware

- **SBC Cluster**: 1+ ARM-based SBCs (e.g., Raspberry Pi 5, Odroid XU4).  
- **Network**: Static IPs and same subnet. Gigabit Ethernet recommended.  
- **Storage**: 4GB+ RAM per node, 50GB+ disk.  

### Software

- **OS**: Ubuntu/Debian-based (e.g., Raspberry Pi OS, Ubuntu Server).  
- **MPICH**: Version 4.x. Install via `apt` or build from source. Set `MPICH_DIR` (default: `/opt/mpich-ch4-ofi`).  
- **Dependencies**:
  - `build-essential gfortran python3`
  - ATLAS: [http://math-atlas.sourceforge.net/](http://math-atlas.sourceforge.net/)
  - HPL: [https://www.netlib.org/benchmark/hpl/](https://www.netlib.org/benchmark/hpl/)
  - Git

- **Passwordless SSH**: Required. Use `ssh-keygen` and `ssh-copy-id`.  

### Node Setup

1. **Static IPs and Hostnames**: e.g., `raspi31: 10.10.10.91`  
2. **Hostfile** in `$HOME`:
   ```
   10.10.10.91:4
   10.10.10.92:4
   ...
   ```
3. **Directories**:  
   - `$HOME/atlas-builds/`  
   - `$HOME/hpl-builds/`  
   - `$HOME/clustershared/hpl-results/`  
   - `$HOME/wait-files/`  
4. **CPU Governor**:
   ```bash
   sudo cpupower frequency-set -g performance
   ```
5. **Disable Throttling** (if supported via firmware)

## 🚀 Setup and Configuration

### Clone the Repo

```bash
git clone https://github.com/your-repo/sbcc-hpl-benchmarking.git
cd sbcc-hpl-benchmarking
```

### Distribute Scripts

Ensure the `scripts/` folder is at the same path on all nodes (e.g., `$HOME/sbcc-hpl-benchmarking/scripts/`).  
Use `rsync` or `scp`.

### Create Platform Config

- Copy `base-config.txt` to `config-yourplatform.txt`
- Override:
  ```bash
  PLATFORM=yourplatform
  MASTER_DEVICE=raspi31
  HOSTFILE=${HOME}/hostsYourPlatform
  NUM_OF_NODES=4
  CORES_PER_NODE=4
  Ns="52000 53000"
  NBs="64 128"
  Ps="2 4"
  BLAS_IMPL="ATLAS"
  ```
- Make sure all paths exist and are writable.

### Build Info File

Create `scripts/atlas_build/builds_info/builds_info_yourplatform.txt`  
(use `builds_info_raspi5B.txt` as reference)

## 📊 Usage

### Top-Level Scripts

- `executor.sh`: Main entry point for all steps  
- `check-hosts.sh`: Verify connectivity  
- `sync-folder.sh`: Sync files across nodes  

### Execution

```bash
./executor.sh scripts/config-files/yourplatform/config-yourplatform.txt
```

Follow prompts:

1. Clean wait directory  
2. Build ATLAS  
3. Build HPL  
4. Run HPL + throttling  

Logs are saved in `log.txt`, `log-atlas-build.txt`, etc.  
Results go to:  
`$HOME/clustershared/hpl-results/yourplatform/N-node/ATLAS-params/results.txt`

### Customization

- **Multiple builds**: Set `BUILD_RUN="yes"`  
- **Param sweeps**: Set `BUILD_RUN="no"` and modify `Ns`, `NBs`, `Ps`  
- **Throttling**: Enabled by default

## 🔧 Troubleshooting

- SSH not working: Test `ssh nodeX hostname`  
- Hostfile format error: Use only `IP:slots` (no spaces/comments)  
- Build fails: Check ATLAS/HPL source and logs  
- MPI binding fails: Try `MPIEXEC_BIND_TO=""`  
- Result file empty: Confirm ATLAS/HPL paths and nodes are reachable  

## 📈 Data and Results

- **Raw**: All `.out` files from HPL
- **Processed**: Tables with Gflops, run time, throttling
- **Format**:
  ```
  build_name, run, param_string, nround, nb, p, q, time, gflops, date, throttling
  ```

Use Python/pandas for further analysis.

## 📜 License

MIT License. See `LICENSE` for details.

## 📣 Citation

If using this repo, cite:

> Re-evaluating Compute Performance in SBC Clusters: HPL Benchmarking Across Generations  
> Submitted to *Future Generation Computer Systems*, 2025  
> DOI: [TBD]

For questions or contributions, open an issue or PR! 🎉
