# sbcc-hpl-benchmarking
Reproducible benchmarking of SBC clusters using HPL with ATLAS and OpenBLAS on ARM-based platforms

## HPL Benchmarking on SBC Clusters

This repository contains all scripts, raw outputs, and processed data from a study on benchmarking Single Board Computer Clusters (SBCCs) using the HPL benchmark with ATLAS and OpenBLAS across multiple ARM-based platforms.

## 📁 Repository Structure

- `scripts/`: Shell scripts for compiling ATLAS, OpenBLAS, HPL, and running experiments.
- `raw-results/`: Raw HPL `.out` files and performance logs from individual runs.
- `processed-results/`: Structured performance data, board metadata, and summary tables aligned with the figures in the accompanying paper.

## ⚙️ Reproducibility

To reproduce the experiments:

1. Review the setup and execution scripts in `scripts/`.
2. Prepare the target SBC system (details on hardware, OS, and toolchains are described in the manuscript).
3. Run the benchmark using the relevant automation script (`run_all_openblas.sh` or `run_all_atlas.sh`).
4. Collected results will be saved in the corresponding output directory.

## 📊 Data

- All raw `.out` files from HPL runs are preserved for verification and traceability.
- Processed summary tables and visualizations correspond to those used in the paper.
- Metadata includes SBC identifiers, architecture details, core counts, memory specifications, and compiler options.

## 📜 License

This repository is licensed under the MIT License. See `LICENSE` for full terms.

## 📣 Citation

If you use or reference this repository, please cite:

> Re-evaluating Compute Performance in SBC Clusters: HPL Benchmarking Across Generations  
> Submitted to *Future Generation Computer Systems*, 2025  
> DOI will be added upon acceptance
