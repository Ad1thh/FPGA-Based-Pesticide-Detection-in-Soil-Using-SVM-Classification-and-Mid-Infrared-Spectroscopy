# FPGA-Based Pesticide Detection in Soil using SVM Classification and Mid-Infrared Spectroscopy

## Overview
This project involves the design and implementation of a 3-stage Support Vector Machine (SVM) classification pipeline on an FPGA. The system is designed to detect and classify pesticide residues in soil by analyzing mid-infrared spectroscopy data.

Machine learning models developed in MATLAB serve as the baseline, leveraging K-Fold Cross-Validation on double-precision data to ensure robust training. The inference algorithm is then translated into Verilog, utilizing Q16.16 fixed-point arithmetic. This approach optimizes the design for hardware execution while minimizing accuracy loss due to quantization.

## Key Features
* **Hardware Acceleration:** Custom SVM inference pipeline implemented on an FPGA for real-time classification.
* **Algorithm Translation:** Seamless transition from MATLAB double-precision algorithms to Verilog Q16.16 fixed-point logic.
* **Rigorous Validation:** Performance benchmarking across 500 independent test samples, comparing accuracy, per-sample latency, and throughput between MATLAB and FPGA endpoints.
* **Hardware Verification:** Synthesized, simulated, and visualized using Xilinx Vivado to ensure optimal logic resource utilization and functionality.

## Repository Contents
* `Verilog Code/` - Contains the Verilog hardware description files for the 3-stage SVM pipeline.
* `Results/` - Contains performance benchmarking, resource utilization metrics, and timing comparison results.

## Tools & Technologies
* **Languages:** Verilog (HDL), MATLAB
* **Tools:** Xilinx Vivado
* **Concepts:** Support Vector Machines (SVM), K-Fold Cross Validation, Fixed-Point Arithmetic (Q16.16), Digital Logic Design.

## Results
The hardware implementation successfully maintains high classification accuracy while significantly improving latency and throughput compared to the software baseline. Detailed timing and resource utilization metrics are available in the `Results` directory.
