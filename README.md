# FPGA-Based Pesticide Detection in Soil using SVM Classification and Mid-Infrared Spectroscopy

## Overview
This project involves the design and implementation of a 3-stage Support Vector Machine (SVM) classification pipeline on an FPGA. The system is designed to detect and classify pesticide residues in soil by analyzing mid-infrared spectroscopy data.

Machine learning models developed in MATLAB serve as the baseline, leveraging **10-Fold Stratified Cross-Validation** on double-precision data to ensure robust training. The inference algorithm is then translated into Verilog, utilizing **Q16.16 fixed-point arithmetic**. This approach optimizes the design for hardware execution while minimizing accuracy loss due to quantization.

## Key Features
* **Hardware Acceleration:** Custom SVM inference pipeline implemented on an FPGA for real-time classification.
* **Algorithm Translation:** Seamless transition from MATLAB double-precision algorithms to Verilog Q16.16 fixed-point logic.
* **Rigorous Validation:** Performance benchmarking across 500 independent test samples, comparing accuracy, per-sample latency, and throughput between MATLAB and FPGA endpoints.
* **Hardware Verification:** Synthesized, simulated, and visualized using Xilinx Vivado to ensure optimal logic resource utilization and functionality.

## Hardware Mapping (Nexys 4)

### Inputs (Switches & Buttons)
* **CLK100MHZ (E3):** 100 MHz oscillator
* **BTNC (Center Button):** Start classification
* **BTNU (Up Button):** Active-low reset
* **SW[2:0]:** Sample select (0-7: pick which test vector)
* **SW[15:14]:** Mode select:
  * `00` = BRAM mode (use pre-loaded features of the selected sample)
  * `01` = Demo: All features = +2.0 (CLEAN)
  * `10` = Demo: All features = -2.0 (CONTAMINATED)
  * `11` = Demo: All features = -0.5 (CONTAMINATED)

### Outputs (LEDs & 7-Segment)
* **SEG[7:0] & AN[7:0]:** 7-segment display (shows pesticide name or "CLEAN")
* **LED[0]:** Busy (processing)
* **LED[1]:** Done
* **LED[2]:** Contaminated
* **LED[3]:** Result valid
* **LED[6:4]:** Family ID (binary: 001-101)
* **LED[7]:** Loader active
* **LED[11:8]:** Pesticide ID (1-8)
* **LED[14:12]:** Sample select echo
* **LED[15]:** Heartbeat (blinks to show FPGA is running)

## Repository Contents
* `Verilog Code/` - Contains the Verilog hardware description files for the 3-stage SVM pipeline.

## Tools & Technologies
* **Languages:** Verilog (HDL), MATLAB
* **Tools:** Xilinx Vivado
* **Concepts:** Support Vector Machines (SVM), K-Fold Cross Validation, Fixed-Point Arithmetic (Q16.16), Digital Logic Design.

## Results
The hardware implementation successfully maintains high classification accuracy while significantly improving latency and throughput compared to the software baseline. 

When testing the model using 500 independent samples on both the MATLAB (double-precision) and FPGA (Q16.16 fixed-point) pipelines, the test accuracies achieved were:
* **Stage 1 (Binary Classification - Pesticide vs. Pure Soil):** 100% accuracy
* **Stage 2 (Family Classification):** 85.89% accuracy
* **Stage 3 (Specific Pesticide Classification):** 73.21% accuracy

**Key Hardware Finding:** There was exactly **0% accuracy loss** when translating the double-precision software model into the Q16.16 fixed-point hardware format for the FPGA, demonstrating successful hardware logic optimization.
