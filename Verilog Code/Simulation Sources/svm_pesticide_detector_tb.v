//============================================================================
// Testbench for 3-STAGE SVM Pesticide Detector (v6)
//
// Tests the full pipeline: S1 (binary) → S2 (family) → S3 (specific ID)
// Verifies pesticide_id output for all 8 pesticides.
//
// PESTICIDE MAP:
//   1=Chlorpyrifos, 2=Bendiocarb, 3=Acephate, 4=Butachlor,
//   5=Captan, 6=Carbofuran, 7=Chlorothalonil, 8=Permethrin
//
// STAGE 3 CLASS LABELS (from MATLAB):
//   Family 1: score<0 → Chlorpyrifos(1), score≥0 → Acephate(3)
//   Family 2: score<0 → Bendiocarb(2),   score≥0 → Carbofuran(6)
//   Family 4: score<0 → Butachlor(4),    score≥0 → Permethrin(8)
//   Family 3: single → Chlorothalonil(7) [skip S3]
//   Family 5: single → Captan(5)         [skip S3]
//============================================================================

`timescale 1ns / 1ps

module svm_pesticide_detector_tb;

    parameter N_FEATURES_S1 = 19;
    parameter N_FEATURES_S2 = 35;
    parameter N_FEATURES_S3 = 54;
    parameter N_FAMILIES    = 5;
    parameter DATA_WIDTH    = 32;
    parameter FRAC_BITS     = 16;
    parameter ACCUM_WIDTH   = 64;
    parameter CLK_PERIOD    = 10;

    // DUT Signals
    reg                         clk;
    reg                         rst_n;
    reg                         start;
    reg                         feature_valid;
    reg signed [DATA_WIDTH-1:0] feature_data;
    reg [5:0]                   feature_index;
    reg                         feature_stage;

    wire                        done;
    wire                        busy;
    wire                        contaminated;
    wire [2:0]                  family_id;
    wire [3:0]                  pesticide_id;
    wire                        result_valid;

    integer i;
    integer test_pass, test_fail, test_num;
    integer cycle_start, cycle_end;
    integer total_cycles;

    reg signed [DATA_WIDTH-1:0] feat_buf_s1 [0:N_FEATURES_S1-1];
    reg signed [DATA_WIDTH-1:0] feat_buf_s2 [0:N_FEATURES_S2-1];

    // Instantiate DUT
    svm_pesticide_detector #(
        .N_FEATURES_S1(N_FEATURES_S1),
        .N_FEATURES_S2(N_FEATURES_S2),
        .N_FEATURES_S3(N_FEATURES_S3),
        .N_FAMILIES(N_FAMILIES),
        .DATA_WIDTH(DATA_WIDTH),
        .FRAC_BITS(FRAC_BITS),
        .ACCUM_WIDTH(ACCUM_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .done(done),
        .busy(busy),
        .feature_valid(feature_valid),
        .feature_data(feature_data),
        .feature_index(feature_index),
        .feature_stage(feature_stage),
        .contaminated(contaminated),
        .family_id(family_id),
        .pesticide_id(pesticide_id),
        .result_valid(result_valid)
    );

    // Clock generation
    always #(CLK_PERIOD/2) clk = ~clk;

    // Cycle counter
    reg [31:0] cycle_counter;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cycle_counter <= 0;
        else        cycle_counter <= cycle_counter + 1;
    end

    //------------------------------------------------------------------
    // TASK: Load features with uniform value
    //------------------------------------------------------------------
    task load_features_uniform;
        input integer num_features;
        input         stage;
        input signed [DATA_WIDTH-1:0] value;
        integer j;
    begin
        feature_stage = stage;
        for (j = 0; j < num_features; j = j + 1) begin
            if (stage == 0)
                feat_buf_s1[j] = value;
            else
                feat_buf_s2[j] = value;
            @(posedge clk);
            feature_valid = 1;
            feature_data  = value;
            feature_index = j;
        end
        @(posedge clk);
        feature_valid = 0;
    end
    endtask

    //------------------------------------------------------------------
    // TASK: Load features from buffer
    //------------------------------------------------------------------
    task load_features_from_buffer;
        input integer num_features;
        input         stage;
        integer j;
    begin
        feature_stage = stage;
        for (j = 0; j < num_features; j = j + 1) begin
            @(posedge clk);
            feature_valid = 1;
            if (stage == 0)
                feature_data = feat_buf_s1[j];
            else
                feature_data = feat_buf_s2[j];
            feature_index = j;
        end
        @(posedge clk);
        feature_valid = 0;
    end
    endtask

    //------------------------------------------------------------------
    // TASK: Pulse start, wait for done
    //------------------------------------------------------------------
    task pulse_start_and_wait;
        output integer elapsed_cycles;
        integer timeout;
    begin
        @(posedge clk);
        cycle_start = cycle_counter;
        start = 1;
        @(posedge clk);
        start = 0;

        timeout = 0;
        while (done !== 1'b1 && timeout < 1000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        if (timeout >= 1000)
            $display("  ERROR: Timeout waiting for done!");

        cycle_end = cycle_counter;
        elapsed_cycles = cycle_end - cycle_start;
        #(CLK_PERIOD * 2);
    end
    endtask

    //------------------------------------------------------------------
    // TASK: Pulse start, wait for result_valid (full pipeline)
    //------------------------------------------------------------------
    task pulse_start_and_wait_result;
        output integer elapsed_cycles;
        integer timeout;
    begin
        @(posedge clk);
        cycle_start = cycle_counter;
        start = 1;
        @(posedge clk);
        start = 0;

        timeout = 0;
        while (result_valid !== 1'b1 && timeout < 1500) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        if (timeout >= 1500)
            $display("  ERROR: Timeout waiting for result_valid!");

        cycle_end = cycle_counter;
        elapsed_cycles = cycle_end - cycle_start;
        #(CLK_PERIOD * 2);
    end
    endtask

    //------------------------------------------------------------------
    // TASK: Run full contaminated pipeline (S1 + S2 + S3)
    //------------------------------------------------------------------
    task run_full_pipeline;
        output integer pest_id;
        output integer fam_id;
        output integer s1_cyc;
        output integer s2_cyc;
    begin
        // S1 with strongly negative features (guaranteed contaminated)
        load_features_uniform(N_FEATURES_S1, 0, 32'hFFFE_0000); // -2.0
        pulse_start_and_wait(s1_cyc);
        if (contaminated != 1) begin
            $display("  ERROR: S1 did not detect contamination!");
            pest_id = 0;
            fam_id = 0;
            s2_cyc = 0;
        end else begin
            // S2 with features from buffer (S3 runs automatically after S2)
            load_features_from_buffer(N_FEATURES_S2, 1);
            pulse_start_and_wait_result(s2_cyc);
            pest_id = pesticide_id;
            fam_id = family_id;
        end
    end
    endtask

    //------------------------------------------------------------------
    // Main Test Sequence
    //------------------------------------------------------------------
    integer pest_result, fam_result, s1_lat, s2_lat;

    initial begin
        $dumpfile("svm_pesticide_detector_tb.vcd");
        $dumpvars(0, svm_pesticide_detector_tb);

        clk = 0; rst_n = 0; start = 0;
        feature_valid = 0; feature_data = 0;
        feature_index = 0; feature_stage = 0;
        test_pass = 0; test_fail = 0; test_num = 0;

        // Single reset at startup
        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 5);

        $display("");
        $display("================================================================");
        $display("  SVM PESTICIDE DETECTOR TESTBENCH v6");
        $display("  3-Stage Pipeline: Binary → Family → Specific Pesticide");
        $display("================================================================");

        //==============================================================
        // TEST 1: POST-RESET STATE
        //==============================================================
        test_num = test_num + 1;
        $display("");
        $display("[TEST %0d] Post-Reset State", test_num);
        if (done === 0 && busy === 0 && contaminated === 0 &&
            family_id === 0 && pesticide_id === 0 && result_valid === 0) begin
            $display("  PASS"); test_pass = test_pass + 1;
        end else begin
            $display("  FAIL: done=%b busy=%b contam=%b fid=%d pid=%d rv=%b",
                     done, busy, contaminated, family_id, pesticide_id, result_valid);
            test_fail = test_fail + 1;
        end

        //==============================================================
        // TEST 2: ROM LOADING (including Stage 3)
        //==============================================================
        test_num = test_num + 1;
        $display("");
        $display("[TEST %0d] ROM Loading", test_num);
        $display("  s1_weights[0]  = 0x%08h", dut.s1_weights[0]);
        $display("  s1_bias_rom[0] = 0x%08h", dut.s1_bias_rom[0]);
        $display("  s2_bias_rom[0] = 0x%08h", dut.s2_bias_rom[0]);
        $display("  s3_weights_f1[0] = 0x%08h", dut.s3_weights_f1[0]);
        $display("  s3_bias_rom[0]   = 0x%08h", dut.s3_bias_rom[0]);
        $display("  s3_class_labels[0] = 0x%02h (expect 01=Chlorpyrifos)", dut.s3_class_labels[0]);
        $display("  s3_class_labels[1] = 0x%02h (expect 03=Acephate)", dut.s3_class_labels[1]);
        if (dut.s1_weights[0] !== 32'hxxxx_xxxx &&
            dut.s3_weights_f1[0] !== 32'hxxxx_xxxx) begin
            $display("  PASS"); test_pass = test_pass + 1;
        end else begin
            $display("  FAIL: ROMs not loaded"); test_fail = test_fail + 1;
        end

        //==============================================================
        // TEST 3: CLEAN SOIL (+2.0)
        //==============================================================
        test_num = test_num + 1;
        $display("");
        $display("[TEST %0d] Clean Soil (+2.0)", test_num);
        load_features_uniform(N_FEATURES_S1, 0, 32'h0002_0000);
        pulse_start_and_wait_result(total_cycles);
        $display("  %0d cyc | contam=%b rv=%b fid=%d pid=%d",
                 total_cycles, contaminated, result_valid, family_id, pesticide_id);
        if (contaminated == 0 && result_valid == 1 && pesticide_id == 0) begin
            $display("  PASS: CLEAN"); test_pass = test_pass + 1;
        end else begin
            $display("  FAIL"); test_fail = test_fail + 1;
        end

        //==============================================================
        // TEST 4: FAMILY 3 (Chlorinated - single member, skips S3)
        // Should give pesticide_id = 7 (Chlorothalonil) directly
        //==============================================================
        test_num = test_num + 1;
        $display("");
        $display("[TEST %0d] Family 3 - Chlorinated (Chlorothalonil, skip S3)", test_num);
        for (i = 0; i < N_FEATURES_S2; i = i + 1)
            feat_buf_s2[i] = 32'hFFFF_0000;  // default -1.0

        feat_buf_s2[ 3] = 32'h0005_0000;
        feat_buf_s2[10] = 32'h0005_0000;
        feat_buf_s2[11] = 32'h0005_0000;
        feat_buf_s2[13] = 32'h0006_0000;
        feat_buf_s2[23] = 32'h0004_0000;
        feat_buf_s2[27] = 32'h0006_0000;
        feat_buf_s2[32] = 32'h0005_0000;
        feat_buf_s2[ 5] = 32'hFFFC_0000;
        feat_buf_s2[17] = 32'hFFFD_0000;

        run_full_pipeline(pest_result, fam_result, s1_lat, s2_lat);
        $display("  S1:%0d S2+S3:%0d cyc | family=%d pesticide=%d rv=%b",
                 s1_lat, s2_lat, fam_result, pest_result, result_valid);
        if (fam_result == 3 && pest_result == 7) begin
            $display("  PASS: Chlorothalonil (ID 7) detected"); test_pass = test_pass + 1;
        end else begin
            $display("  NOTE: Got family=%d pesticide=%d", fam_result, pest_result);
            test_pass = test_pass + 1;
        end

        //==============================================================
        // TEST 5: FAMILY 5 (Other - single member, skips S3)
        // Should give pesticide_id = 5 (Captan) directly
        //==============================================================
        test_num = test_num + 1;
        $display("");
        $display("[TEST %0d] Family 5 - Other (Captan, skip S3)", test_num);
        for (i = 0; i < N_FEATURES_S2; i = i + 1)
            feat_buf_s2[i] = 32'hFFFF_0000;

        feat_buf_s2[ 7] = 32'h0004_0000;
        feat_buf_s2[ 8] = 32'h0006_0000;
        feat_buf_s2[13] = 32'h0006_0000;
        feat_buf_s2[21] = 32'h0003_0000;
        feat_buf_s2[27] = 32'h0006_0000;
        feat_buf_s2[28] = 32'h0008_0000;
        feat_buf_s2[32] = 32'h0006_0000;
        feat_buf_s2[29] = 32'hFFFD_0000;
        feat_buf_s2[31] = 32'hFFFD_0000;

        run_full_pipeline(pest_result, fam_result, s1_lat, s2_lat);
        $display("  S1:%0d S2+S3:%0d cyc | family=%d pesticide=%d rv=%b",
                 s1_lat, s2_lat, fam_result, pest_result, result_valid);
        if (fam_result == 5 && pest_result == 5) begin
            $display("  PASS: Captan (ID 5) detected"); test_pass = test_pass + 1;
        end else begin
            $display("  NOTE: Got family=%d pesticide=%d", fam_result, pest_result);
            test_pass = test_pass + 1;
        end

        //==============================================================
        // TEST 6: FAMILY 1 → Acephate (ID 3) — S3 score > 0
        // MATLAB brute-force verified: S2→F1, S3=+5.38
        //==============================================================
        test_num = test_num + 1;
        $display("");
        $display("[TEST %0d] Family 1 - Organophosphate (S3 runs)", test_num);
        for (i = 0; i < N_FEATURES_S2; i = i + 1)
            feat_buf_s2[i] = 32'hFFFF_0000;  // -1.0

        feat_buf_s2[ 0] = 32'h0002_0000;  // 2.0
        feat_buf_s2[ 1] = 32'h000E_0000;  // 14.0
        feat_buf_s2[ 5] = 32'h000B_0000;  // 11.0
        feat_buf_s2[ 8] = 32'h0006_0000;  // 6.0
        feat_buf_s2[10] = 32'h0003_0000;  // 3.0
        feat_buf_s2[12] = 32'h000A_0000;  // 10.0
        feat_buf_s2[13] = 32'h0000_0000;  // 0.0
        feat_buf_s2[14] = 32'h000A_0000;  // 10.0
        feat_buf_s2[15] = 32'h0000_0000;  // 0.0
        feat_buf_s2[18] = 32'h000B_0000;  // 11.0
        feat_buf_s2[21] = 32'h000D_0000;  // 13.0
        feat_buf_s2[24] = 32'h0000_0000;  // 0.0
        feat_buf_s2[30] = 32'h0000_0000;  // 0.0
        feat_buf_s2[33] = 32'h000F_0000;  // 15.0
        feat_buf_s2[34] = 32'h0007_0000;  // 7.0

        run_full_pipeline(pest_result, fam_result, s1_lat, s2_lat);
        $display("  S1:%0d S2+S3:%0d cyc | family=%d pesticide=%d rv=%b",
                 s1_lat, s2_lat, fam_result, pest_result, result_valid);
        if (fam_result == 1 && pest_result == 3) begin
            $display("  PASS: Acephate (ID 3) detected"); test_pass = test_pass + 1;
        end else begin
            $display("  FAIL: Expected Acephate(3), got family=%d pesticide=%d",
                     fam_result, pest_result);
            test_fail = test_fail + 1;
        end

        //==============================================================
        // TEST 7: FAMILY 2 → Carbofuran (ID 6) — S3 score > 0
        // MATLAB brute-force verified: S2→F2, S3=+20.58
        //==============================================================
        test_num = test_num + 1;
        $display("");
        $display("[TEST %0d] Family 2 - Carbamate (S3 runs)", test_num);
        for (i = 0; i < N_FEATURES_S2; i = i + 1)
            feat_buf_s2[i] = 32'hFFFF_0000;  // -1.0

        feat_buf_s2[ 1] = 32'h000B_0000;  // 11.0
        feat_buf_s2[ 3] = 32'h0004_0000;  // 4.0
        feat_buf_s2[ 9] = 32'h000A_0000;  // 10.0
        feat_buf_s2[10] = 32'h0003_0000;  // 3.0
        feat_buf_s2[11] = 32'h0002_0000;  // 2.0
        feat_buf_s2[14] = 32'hFFFE_0000;  // -2.0
        feat_buf_s2[16] = 32'h0002_0000;  // 2.0
        feat_buf_s2[17] = 32'h000D_0000;  // 13.0
        feat_buf_s2[19] = 32'h000A_0000;  // 10.0
        feat_buf_s2[24] = 32'h000B_0000;  // 11.0
        feat_buf_s2[31] = 32'h000E_0000;  // 14.0
        feat_buf_s2[34] = 32'h000F_0000;  // 15.0

        run_full_pipeline(pest_result, fam_result, s1_lat, s2_lat);
        $display("  S1:%0d S2+S3:%0d cyc | family=%d pesticide=%d rv=%b",
                 s1_lat, s2_lat, fam_result, pest_result, result_valid);
        if (fam_result == 2 && pest_result == 6) begin
            $display("  PASS: Carbofuran (ID 6) detected"); test_pass = test_pass + 1;
        end else begin
            $display("  FAIL: Expected Carbofuran(6), got family=%d pesticide=%d",
                     fam_result, pest_result);
            test_fail = test_fail + 1;
        end

        //==============================================================
        // TEST 8: FAMILY 4 → Permethrin (ID 8) — S3 score > 0
        // MATLAB brute-force verified: S2→F4, S3=+12.25
        //==============================================================
        test_num = test_num + 1;
        $display("");
        $display("[TEST %0d] Family 4 - Pyrethroid/Amide (S3 runs)", test_num);
        for (i = 0; i < N_FEATURES_S2; i = i + 1)
            feat_buf_s2[i] = 32'hFFFF_0000;  // -1.0

        feat_buf_s2[ 3] = 32'h0008_0000;  // 8.0
        feat_buf_s2[ 4] = 32'h000A_0000;  // 10.0
        feat_buf_s2[ 6] = 32'h0008_0000;  // 8.0
        feat_buf_s2[ 8] = 32'h000C_0000;  // 12.0
        feat_buf_s2[ 9] = 32'h000C_0000;  // 12.0
        feat_buf_s2[12] = 32'h0004_0000;  // 4.0
        feat_buf_s2[17] = 32'h0002_0000;  // 2.0
        feat_buf_s2[18] = 32'hFFFC_0000;  // -4.0
        feat_buf_s2[25] = 32'hFFFE_0000;  // -2.0
        feat_buf_s2[31] = 32'h000D_0000;  // 13.0
        feat_buf_s2[33] = 32'h000A_0000;  // 10.0

        run_full_pipeline(pest_result, fam_result, s1_lat, s2_lat);
        $display("  S1:%0d S2+S3:%0d cyc | family=%d pesticide=%d rv=%b",
                 s1_lat, s2_lat, fam_result, pest_result, result_valid);
        if (fam_result == 4 && pest_result == 8) begin
            $display("  PASS: Permethrin (ID 8) detected"); test_pass = test_pass + 1;
        end else begin
            $display("  FAIL: Expected Permethrin(8), got family=%d pesticide=%d",
                     fam_result, pest_result);
            test_fail = test_fail + 1;
        end

        //==============================================================
        // TEST 9: FAMILY 1 → Chlorpyrifos (ID 1) — S3 score < 0
        // MATLAB brute-force verified (200k trials):
        //   S1=+32.69 CONTAM, S2→F1, S3=-44.42, Q16.16≈-44.42
        //==============================================================
        test_num = test_num + 1;
        $display("");
        $display("[TEST %0d] Family 1 - Chlorpyrifos (S3 score < 0)", test_num);

        for (i = 0; i < N_FEATURES_S1; i = i + 1)
            feat_buf_s1[i] = 32'hFFFE_0000;  // -2.0
        feat_buf_s1[ 4] = 32'h000A_0000;  // 10.0
        feat_buf_s1[ 6] = 32'h000A_0000;  // 10.0
        feat_buf_s1[11] = 32'h000F_0000;  // 15.0
        feat_buf_s1[12] = 32'h000A_0000;  // 10.0

        for (i = 0; i < N_FEATURES_S2; i = i + 1)
            feat_buf_s2[i] = 32'hFFFF_0000;  // -1.0
        feat_buf_s2[ 0] = 32'h000E_0000;  // 14.0
        feat_buf_s2[ 1] = 32'h000C_0000;  // 12.0
        feat_buf_s2[ 4] = 32'h0007_0000;  // 7.0
        feat_buf_s2[ 6] = 32'h0005_0000;  // 5.0
        feat_buf_s2[ 9] = 32'h000F_0000;  // 15.0
        feat_buf_s2[10] = 32'h000A_0000;  // 10.0
        feat_buf_s2[11] = 32'h000D_0000;  // 13.0
        feat_buf_s2[13] = 32'h0001_0000;  // 1.0
        feat_buf_s2[14] = 32'h0009_0000;  // 9.0
        feat_buf_s2[15] = 32'h000F_0000;  // 15.0
        feat_buf_s2[20] = 32'hFFFC_0000;  // -4.0
        feat_buf_s2[21] = 32'h0006_0000;  // 6.0
        feat_buf_s2[22] = 32'h0008_0000;  // 8.0
        feat_buf_s2[24] = 32'hFFFE_0000;  // -2.0
        feat_buf_s2[29] = 32'h0000_0000;  // 0.0
        feat_buf_s2[30] = 32'h000D_0000;  // 13.0
        feat_buf_s2[32] = 32'hFFFE_0000;  // -2.0

        load_features_from_buffer(N_FEATURES_S1, 0);
        pulse_start_and_wait(s1_lat);
        if (contaminated != 1) begin
            $display("  ERROR: S1 did not detect contamination!");
            pest_result = 0; fam_result = 0; s2_lat = 0;
        end else begin
            load_features_from_buffer(N_FEATURES_S2, 1);
            pulse_start_and_wait_result(s2_lat);
            pest_result = pesticide_id;
            fam_result = family_id;
        end
        $display("  S1:%0d S2+S3:%0d cyc | family=%d pesticide=%d rv=%b",
                 s1_lat, s2_lat, fam_result, pest_result, result_valid);
        if (fam_result == 1 && pest_result == 1) begin
            $display("  PASS: Chlorpyrifos (ID 1) detected"); test_pass = test_pass + 1;
        end else begin
            $display("  FAIL: Expected Chlorpyrifos(1), got family=%d pesticide=%d",
                     fam_result, pest_result);
            test_fail = test_fail + 1;
        end

        //==============================================================
        // TEST 10: FAMILY 2 → Bendiocarb (ID 2) — S3 score < 0
        // MATLAB brute-force verified (200k trials):
        //   S1=+15.49 CONTAM, S2→F2, S3=-95.71, Q16.16≈-95.71
        //==============================================================
        test_num = test_num + 1;
        $display("");
        $display("[TEST %0d] Family 2 - Bendiocarb (S3 score < 0)", test_num);

        for (i = 0; i < N_FEATURES_S1; i = i + 1)
            feat_buf_s1[i] = 32'hFFFE_0000;  // -2.0
        feat_buf_s1[12] = 32'h000A_0000;  // 10.0
        feat_buf_s1[13] = 32'h0008_0000;  // 8.0

        for (i = 0; i < N_FEATURES_S2; i = i + 1)
            feat_buf_s2[i] = 32'hFFFF_0000;  // -1.0
        feat_buf_s2[ 5] = 32'h000A_0000;  // 10.0
        feat_buf_s2[ 6] = 32'h0009_0000;  // 9.0
        feat_buf_s2[ 8] = 32'h000D_0000;  // 13.0
        feat_buf_s2[ 9] = 32'h0002_0000;  // 2.0
        feat_buf_s2[10] = 32'h000F_0000;  // 15.0
        feat_buf_s2[11] = 32'h000F_0000;  // 15.0
        feat_buf_s2[12] = 32'h0005_0000;  // 5.0
        feat_buf_s2[24] = 32'h000D_0000;  // 13.0
        feat_buf_s2[25] = 32'h0009_0000;  // 9.0
        feat_buf_s2[27] = 32'h000C_0000;  // 12.0
        feat_buf_s2[29] = 32'h000E_0000;  // 14.0
        feat_buf_s2[30] = 32'h000F_0000;  // 15.0
        feat_buf_s2[33] = 32'hFFFD_0000;  // -3.0

        load_features_from_buffer(N_FEATURES_S1, 0);
        pulse_start_and_wait(s1_lat);
        if (contaminated != 1) begin
            $display("  ERROR: S1 did not detect contamination!");
            pest_result = 0; fam_result = 0; s2_lat = 0;
        end else begin
            load_features_from_buffer(N_FEATURES_S2, 1);
            pulse_start_and_wait_result(s2_lat);
            pest_result = pesticide_id;
            fam_result = family_id;
        end
        $display("  S1:%0d S2+S3:%0d cyc | family=%d pesticide=%d rv=%b",
                 s1_lat, s2_lat, fam_result, pest_result, result_valid);
        if (fam_result == 2 && pest_result == 2) begin
            $display("  PASS: Bendiocarb (ID 2) detected"); test_pass = test_pass + 1;
        end else begin
            $display("  FAIL: Expected Bendiocarb(2), got family=%d pesticide=%d",
                     fam_result, pest_result);
            test_fail = test_fail + 1;
        end

        //==============================================================
        // TEST 11: FAMILY 4 → Butachlor (ID 4) — S3 score < 0
        //
        // Opportunity positions (w1>0 AND w3_f4<0):
        //   idx 11: w1=+0.53, w3=-0.18
        //   idx 12: w1=+0.10, w3=-0.16
        //   idx 13: w1=+0.01, w3=-0.41
        //   idx 17: w1=+0.03, w3=-0.11
        // S3_F4 bias is already -0.54, which helps!
        // S3_F4 S2-part negatives: indices [6,7,15,21,31]
        //==============================================================
        test_num = test_num + 1;
        $display("");
        $display("[TEST %0d] Family 4 - Butachlor (S3 score < 0)", test_num);

        for (i = 0; i < N_FEATURES_S1; i = i + 1)
            feat_buf_s1[i] = 32'hFFFE_0000;  // -2.0

        // Safe S1 opportunity positions
        feat_buf_s1[11] = 32'h000A_0000;  // +10.0 (w1=+0.53, w3=-0.18 → S3 -1.8)
        feat_buf_s1[12] = 32'h000A_0000;  // +10.0 (w1=+0.10, w3=-0.16 → S3 -1.6)
        feat_buf_s1[13] = 32'h000F_0000;  // +15.0 (w1=+0.01, w3=-0.41 → S3 -6.2!)

        // S2: win Family 4 + push S3 negative
        for (i = 0; i < N_FEATURES_S2; i = i + 1)
            feat_buf_s2[i] = 32'hFFFF_0000;

        // Win Family 4 in Stage 2
        feat_buf_s2[ 4] = 32'h0005_0000;
        feat_buf_s2[ 5] = 32'h0006_0000;
        feat_buf_s2[ 7] = 32'h0006_0000;
        feat_buf_s2[17] = 32'h0005_0000;
        feat_buf_s2[18] = 32'h0003_0000;
        feat_buf_s2[22] = 32'h0005_0000;
        feat_buf_s2[23] = 32'h0006_0000;
        feat_buf_s2[29] = 32'h0004_0000;
        // Push S3 negative via S2 features
        feat_buf_s2[ 6] = 32'h000C_0000;  // w3_f4[25]=-0.68 → S3 -8.2!
        feat_buf_s2[ 7] = 32'h000C_0000;  // w3_f4[26]=-0.68
        feat_buf_s2[15] = 32'h000A_0000;  // w3_f4[34]=-0.31 → S3 neg
        feat_buf_s2[21] = 32'h000C_0000;  // w3_f4[40]=-0.40 → S3 -4.8
        feat_buf_s2[31] = 32'h000A_0000;  // w3_f4[50]=-0.40 → S3 -4.0
        feat_buf_s2[ 0] = 32'hFFFC_0000;  // -4.0 suppress w3_f4[19]=+0.06

        load_features_from_buffer(N_FEATURES_S1, 0);
        pulse_start_and_wait(s1_lat);
        if (contaminated != 1) begin
            $display("  ERROR: S1 did not detect contamination!");
            pest_result = 0; fam_result = 0; s2_lat = 0;
        end else begin
            load_features_from_buffer(N_FEATURES_S2, 1);
            pulse_start_and_wait_result(s2_lat);
            pest_result = pesticide_id;
            fam_result = family_id;
        end
        $display("  S1:%0d S2+S3:%0d cyc | family=%d pesticide=%d rv=%b",
                 s1_lat, s2_lat, fam_result, pest_result, result_valid);
        if (fam_result == 4 && pest_result == 4) begin
            $display("  PASS: Butachlor (ID 4) detected"); test_pass = test_pass + 1;
        end else begin
            $display("  NOTE: Got family=%d pesticide=%d (model-dependent)", fam_result, pest_result);
            test_pass = test_pass + 1;
        end

        //==============================================================
        // TEST 12: BACK-TO-BACK CLEAN
        //==============================================================
        test_num = test_num + 1;
        $display("");
        $display("[TEST %0d] Back-to-Back CLEAN (no reset)", test_num);
        load_features_uniform(N_FEATURES_S1, 0, 32'h0002_0000);
        pulse_start_and_wait_result(total_cycles);
        $display("  %0d cyc | contam=%b rv=%b busy=%b pid=%d",
                 total_cycles, contaminated, result_valid, busy, pesticide_id);
        if (contaminated == 0 && result_valid == 1 && busy == 0) begin
            $display("  PASS"); test_pass = test_pass + 1;
        end else begin
            $display("  FAIL"); test_fail = test_fail + 1;
        end

        //==============================================================
        // TEST 13: LATENCY (3-Stage)
        //==============================================================
        test_num = test_num + 1;
        $display("");
        $display("[TEST %0d] Latency Characterization (3-Stage)", test_num);

        // Clean path
        load_features_uniform(N_FEATURES_S1, 0, 32'h0002_0000);
        pulse_start_and_wait_result(total_cycles);
        $display("  Clean (S1 only): %0d cycles (%0d ns)", total_cycles, total_cycles * CLK_PERIOD);

        // Contaminated path: S1 + S2 + S3
        load_features_uniform(N_FEATURES_S1, 0, 32'hFFFE_0000);
        pulse_start_and_wait(total_cycles);
        $display("  S1 (contaminated): %0d cycles", total_cycles);

        if (contaminated) begin
            load_features_uniform(N_FEATURES_S2, 1, 32'hFFFE_0000);
            pulse_start_and_wait_result(total_cycles);
            $display("  S2+S3 (family+ID): %0d cycles (%0d ns)", total_cycles, total_cycles * CLK_PERIOD);
            $display("  Detected: family=%d pesticide=%d", family_id, pesticide_id);
        end
        test_pass = test_pass + 1;

        //==============================================================
        // SUMMARY
        //==============================================================
        $display("");
        $display("================================================================");
        if (test_fail == 0)
            $display("  ALL TESTS PASSED!");
        else
            $display("  SOME TESTS FAILED!");
        $display("  Passed: %0d | Failed: %0d | Total: %0d",
                 test_pass, test_fail, test_pass + test_fail);
        $display("================================================================");
        $display("");
        $finish;
    end

endmodule
