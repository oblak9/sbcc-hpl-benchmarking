# sbcc-hpl-benchmarking
Reproducible benchmarking of SBC clusters using HPL with ATLAS and OpenBLAS on ARM-based platforms

## HPL Benchmarking on SBC Clusters

This repository contains all scripts, raw outputs, and processed data from a study on benchmarking Single Board Computer Clusters (SBCCs) using the HPL benchmark with ATLAS and OpenBLAS across multiple ARM-based platforms.

## 📁 Repository Structure

- `scripts/`: Shell scripts for compiling ATLAS, OpenBLAS, and HPL, and running experiments.
- `raw-results/`: Raw HPL `.out` files and performance logs from individual runs.
- `processed-results/`: Structured performance data, board metadata, and summary tables aligned with the figures in the accompanying paper.

## ⚙️ Reproducibility

To reproduce the experiments, follow these steps:

### Requirements

- MPICH installed in `$HOME/mpich-install`
- Add MPICH to the path:
  ```bash
  export PATH=$PATH:$HOME/mpich-install/bin
  ```
- HPL 2.3 source extracted in the home directory
- ATLAS source extracted in the home directory
- Passwordless SSH between all nodes
- Set CPU frequency governor to `performance`
- Disable hardware throttling if applicable on your platform
- Create a `hosts` file for MPI in the `$HOME` directory
- Create directories for storing logs

### Expected Node Setup

- Nodes must have static IP addresses
- Hostnames must be mapped in the `hosts` file (e.g., `raspi31`, `raspi32`, etc.)
- Hostnames should follow the convention: `<prefix><numeric_id>` (e.g., `raspi31`, `raspi32`)
- The `scripts/` folder must reside at the same path on all nodes

## 🚀 Script Usage

The following top-level scripts are available in the `scripts/` folder:

- `check-hosts.sh`: Verifies reachability of all nodes via ping
- `sync-folder.sh`: Synchronizes the `scripts/` folder across all nodes
- `get-flagsearch-results.sh`: Collects flagsearch results from a specific ATLAS build
- `executor.sh`: Launches the experiment using a specified configuration file

### Examples

Check if nodes are reachable:
```bash
./check-hosts.sh raspi31 4
```

Synchronize scripts across all nodes:
```bash
./sync-folder.sh raspi31 4
```

Extract flagsearch results from a specific ATLAS build:
```bash
./get-flagsearch-results.sh atlarch-cpu-tune-flags
```

Run an experiment using a selected configuration:
```bash
./executor.sh /home/user/scripts/config-files/raspi5B/config-raspi5B.txt
```

> **Note:** Internal helper scripts are used by the top-level scripts and generally do not require direct user interaction.

## 📊 Data

- All raw `.out` files from HPL runs are preserved for verification and traceability.
- Processed summary tables and visualizations correspond to those used in the paper.
- Metadata includes SBC model, architecture, core count, memory specifications, and compiler flags.

## 📜 License

This repository is licensed under the MIT License. See `LICENSE` for full terms.

## 📣 Citation

If you use or reference this repository, please cite:

> Re-evaluating Compute Performance in SBC Clusters: HPL Benchmarking Across Generations  
> Submitted to *Future Generation Computer Systems*, 2025  
> DOI will be added upon acceptance
