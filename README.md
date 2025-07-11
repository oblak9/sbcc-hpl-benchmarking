# sbcc-hpl-benchmarking
Reproducible benchmarking of SBC clusters using HPL with ATLAS and OpenBLAS on ARM-based platforms

# HPL Benchmarking on SBC Clusters

This repository contains all scripts, raw outputs, and processed data from our study on benchmarking Single Board Computer Clusters (SBCCs) using the HPL benchmark with ATLAS and OpenBLAS across multiple ARM-based platforms.

## 📁 Repository Structure

- `scripts/`: Shell scripts for compiling ATLAS, OpenBLAS, HPL, and running experiments.
- `raw-results/`: Raw HPL `.out` files and collected performance text dumps for each run.
- `processed-results/`: Cleaned and structured performance data, metadata about boards, and Excel summaries for analysis.

## ⚙️ Reproducibility

To reproduce our experiments:

1. Review the setup and execution scripts in `scripts/`.
2. Prepare the SBC environment (hardware and OS details in Section X of the paper).
3. Run the appropriate script (`run_all_openblas.sh` or `run_all_atlas.sh`) for the desired configuration.
4. Results will be collected in the corresponding directory.

## 📊 Data

- All raw `.out` files from HPL runs are preserved for verification and traceability.
- Summary tables and charts in `processed-results/` align with the figures and tables in the paper.
- Metadata includes SBC model, SoC architecture, core counts, memory type, and more.

## 📜 License

This project is licensed under the MIT License. See `LICENSE` for details.

## 📣 Citation

If you use this repository, please cite:

> Re-evaluating Compute Performance in SBC Clusters: HPL Benchmarking Across Generations 
> Krpic, Z.; Lukic, I.; Habijan, M.; Loina, L. 
> Future Generation Computer Systems, 2025  
> DOI will be available
