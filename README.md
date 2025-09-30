sbcc-hpl-benchmarking
Reproducible benchmarking of Single Board Computer (SBC) clusters using the High Performance Linpack (HPL) benchmark with ATLAS and OpenBLAS on ARM-based platforms.

## Overview
This repository provides a complete, automated framework for benchmarking HPL on SBC clusters. It supports building optimized ATLAS BLAS libraries, compiling HPL with custom configurations, distributing builds across nodes, and executing HPL runs while collecting performance metrics and throttling data. The setup is designed for reproducibility and extensibility to new SBC platforms.

### Key Features

- Automated Builds: Parallel compilation of ATLAS and HPL across cluster nodes.
- Distributed Execution: MPI-based HPL runs with configurable parameters (N, NB, P, Q, runs).
- Throttling Monitoring: Tracks CPU throttling during runs for accurate performance analysis.
- Configurable: Platform-specific configs allow easy adaptation to new SBCs (e.g., Raspberry Pi, Odroid).
- Reproducibility: All scripts, configs, and logs ensure experiments can be repeated.

📁 Repository Structure

sbcc-hpl-benchmarking/
├── scripts/                          # Main scripts for automation
│   ├── executor.sh                   # Main orchestrator script
│   ├── atlas_build/                  # ATLAS-related scripts
│   │   ├── build-atlases.sh          # Builds ATLAS libraries
│   │   ├── builds_info/              # Build configuration files (e.g., builds_info_raspi5B.txt)
│   ├── hpl_build/                    # HPL-related scripts
│   │   ├── build-hpl.sh              # Builds HPL binaries
│   │   ├── Make.generic              # Template HPL makefile
│   ├── HPL_run/                      # Execution scripts
│   │   ├── HPL-execute.sh            # Runs HPL and collects results
│   ├── stage-builds.sh               # Stages builds to central storage
│   ├── throttling/                   # Throttling monitoring
│   │   ├── get_throttling.sh         # Collects throttling data across nodes
│   │   ├── get_throttling_helper.sh  # Helper for per-node throttling
│   ├── wait/                         # Synchronization utilities
│   │   ├── waitScript.sh             # Waits for completion signals
│   └── config-files/                 # Configuration files
│       ├── base-config.txt           # Base config with defaults
│       └── raspi5B/                  # Platform-specific configs (e.g., config-raspi5B.txt)
├── raw-results/                      # Raw HPL output files (.out)
├── processed-results/                # Summarized performance data and tables
└── README.md                         # This file

⚙️ Requirements
### Hardware
SBC Cluster: 1+ ARM-based SBCs (e.g., Raspberry Pi 5, Odroid XU4). Tested on Raspberry Pi 5 (raspi5B platform).
Network: All nodes on the same subnet with static IP addresses. Gigabit Ethernet recommended for performance.
Storage: Sufficient RAM (4GB+ per node) and storage (50GB+ for builds and results).
### Software
OS: Ubuntu/Debian-based Linux (e.g., Raspberry Pi OS, Ubuntu Server).
MPICH: Version 4.x (e.g., mpich or mpich-ch4-ofi). Install via sudo apt install mpich or build from source. Set MPICH_DIR in config (default: /opt/mpich-ch4-ofi).
Dependencies:
- Build tools: sudo apt install build-essential gfortran python3
- ATLAS source: Download from http://math-atlas.sourceforge.net/ and extract to $HOME/ATLAS.
- HPL source: Download HPL 2.3 from https://www.netlib.org/benchmark/hpl/ and extract to $HOME/hpl-2.3.
- Git: For cloning this repo.
- Passwordless SSH: Required for inter-node communication. Set up with ssh-keygen and ssh-copy-id.
### Node Setup
Assign Static IPs: Ensure each node has a unique IP (e.g., raspi31: 10.10.10.91, raspi32: 10.10.10.92).
Hostname Mapping: Update hosts on all nodes to map hostnames to IPs.
Create Hostfile: In $HOME, create hostsRPi5B (or your platform name) with lines like:
- Format: IP:slots (slots = cores per node, e.g., 4 for quad-core).
No comments or extra spaces.
Directories: Create $HOME/atlas-builds/, $HOME/hpl-builds/, $HOME/clustershared/hpl-results/, $HOME/wait-files/.
CPU Governor: Set to performance to minimize throttling: sudo cpupower frequency-set -g performance.
Disable Throttling: If applicable (e.g., on Raspberry Pi), disable hardware throttling via firmware settings.
🚀 Setup and Configuration
### Clone the Repo

Synchronize Scripts: Copy scripts to the same path on all nodes (e.g., $HOME/sbcc-hpl-benchmarking/scripts/).

Use rsync or scp for distribution.
### Create Platform Config

Copy base-config.txt to a new file (e.g., config-yourplatform.txt).
Override variables for your SBC (see config-raspi5B.txt as an example):
PLATFORM=yourplatform
MASTER_DEVICE=yourmaster (e.g., raspi31)
HOSTFILE=${HOME}/hostsYourPlatform
NUM_OF_NODES=4
CORES_PER_NODE=4
Adjust Ns, NBs, Ps, RUNs for your benchmarks.
Set BLAS_IMPL="ATLAS" or "OpenBLAS".
Ensure paths (e.g., ATLAS_STORAGE, HPL_STORAGE) exist and are writable.
Build Info Files: Create scripts/atlas_build/builds_info/builds_info_yourplatform.txt with ATLAS build configurations (see builds_info_raspi5B.txt for format).

📊 Usage
### Top-Level Scripts
executor.sh: Main script to run steps interactively.
check-hosts.sh: Ping nodes to verify connectivity.
sync-folder.sh: Sync scripts across nodes.
### Execution Steps
Run executor.sh /path/to/config-yourplatform.txt` and select steps:

Clean Wait Directory: Removes old synchronization files.
Run ATLAS Builds: Compiles ATLAS libraries in parallel across nodes.
Run HPL Makefiles: Builds HPL binaries with custom makefiles.
Run HPL Execution: Executes HPL, collects results, and monitors throttling.
#### Example Full Run

Parallel Execution: Builds and staging run in parallel on nodes.
Logs: Check log.txt, log-atlas-build.txt, log-hpl-build.txt, etc., for details.
Results: Output in $HOME/clustershared/hpl-results/yourplatform/N-node/ATLAS-params/results.txt.
### Customizing Runs
Multiple Builds: Set BUILD_RUN="yes" and list builds in builds_info_yourplatform.txt.
Parameter Sweeps: Set BUILD_RUN="no" and specify ranges in Ns, NBs, Ps.
Throttling: Enabled by default; data appended to results.
🔧 Troubleshooting
Based on common issues:

- SSH Failures: Ensure passwordless SSH between all nodes. Test: ssh user@node hostname.
- Hostfile Errors: Use IP:slots format without comments. Test: mpiexec -hostfile $HOSTFILE -n 4 hostname.
- Build Failures: Check logs for missing dependencies. Ensure ATLAS/HPL sources are in $HOME.
- Path Issues: Verify ATLAS_STORAGE, HPL_STORAGE, and HPL_DIR exist and match configs.
- Throttling Zeros: Normal if no throttling occurs. Check /sys/devices/system/cpu/cpu0/cpufreq/stats/time_in_state for updates.
- MPI Binding: If --bind-to core fails, set MPIEXEC_BIND_TO="" in config.
- Quotes in Configs: Config values like Ns="52000" are auto-stripped; no manual changes needed.
- Fanout/Staging: Ensure central storage (${USER}@${MASTER_DEVICE}) is accessible via SSH.
For new platforms, start with config-raspi5B.txt and adjust hardware-specific vars.

📈 Data and Results
- Raw Data: .out files in raw-results contain full HPL output.
- Processed Data: processed-results has tables with Gflops, execution time, throttling diffs, and timestamps.
- Format: Results file columns: build_name, run, param_string, nround, nb, p, q, time, gflops, date, throttling.
- Analysis: Use scripts or tools like Python/pandas for plotting performance vs. params.
📜 License
MIT License. See LICENSE for details.

📣 Citation
If using this repo, cite:

Re-evaluating Compute Performance in SBC Clusters: HPL Benchmarking Across Generations
Submitted to Future Generation Computer Systems, 2025
DOI: [TBD]

For questions or contributions, open an issue or PR! 🎉