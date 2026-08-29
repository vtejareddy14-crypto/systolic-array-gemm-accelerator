// -----------------------------------------------------------------------------
// tb_array_random.v - randomized GEMM check, parameterized by array size.
//
// Runs NUM_TRIALS random matrix pairs through the array and compares every
// output element against a behavioural golden model. Set N at compile time:
//     iverilog -PtbN=8 ... (or edit the parameter below)
//
// Also demonstrates that array size (N) and operand precision (DATA_WIDTH)
// are independent knobs.
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_array_random;

`ifdef ARRAY_N
    parameter N = `ARRAY_N;
`else
    parameter N = 4;
`endif

    parameter K          = N;    // square GEMM for this test
    parameter DATA_WIDTH = 8;
    parameter ACC_WIDTH  = 32;
    parameter NUM_TRIALS = 50;

    reg                      clk = 1'b0;
    reg                      rst_n;
    reg                      enable;
    reg                      clear_acc;
    reg  [N*DATA_WIDTH-1:0]  a_edge;
    reg  [N*DATA_WIDTH-1:0]  b_edge;
    wire [N*N*ACC_WIDTH-1:0] c_flat;

    integer i, j, k, t, trial;
    integer errors = 0;

    reg signed [DATA_WIDTH-1:0] A [0:N-1][0:K-1];
    reg signed [DATA_WIDTH-1:0] B [0:K-1][0:N-1];
    reg signed [ACC_WIDTH-1:0]  C_gold [0:N-1][0:N-1];
    reg signed [ACC_WIDTH-1:0]  c_hw;

    always #5 clk = ~clk;

    systolic_array #(
        .N          (N),
        .DATA_WIDTH (DATA_WIDTH),
        .ACC_WIDTH  (ACC_WIDTH)
    ) dut (
        .clk(clk), .rst_n(rst_n), .enable(enable), .clear_acc(clear_acc),
        .a_edge(a_edge), .b_edge(b_edge), .c_flat(c_flat)
    );

    task drive_cycle;
        input integer t;
        integer r, c, idx;
        begin
            a_edge = {N*DATA_WIDTH{1'b0}};
            b_edge = {N*DATA_WIDTH{1'b0}};
            for (r = 0; r < N; r = r + 1) begin
                idx = t - r;
                if (idx >= 0 && idx < K)
                    a_edge[r*DATA_WIDTH +: DATA_WIDTH] = A[r][idx];
            end
            for (c = 0; c < N; c = c + 1) begin
                idx = t - c;
                if (idx >= 0 && idx < K)
                    b_edge[c*DATA_WIDTH +: DATA_WIDTH] = B[idx][c];
            end
        end
    endtask

    initial begin
        rst_n     = 1'b0;
        enable    = 1'b1;
        clear_acc = 1'b0;
        a_edge    = {N*DATA_WIDTH{1'b0}};
        b_edge    = {N*DATA_WIDTH{1'b0}};
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        for (trial = 0; trial < NUM_TRIALS; trial = trial + 1) begin

            // fresh random operands, full int8 range
            for (i = 0; i < N; i = i + 1)
                for (k = 0; k < K; k = k + 1)
                    A[i][k] = $random;
            for (k = 0; k < K; k = k + 1)
                for (j = 0; j < N; j = j + 1)
                    B[k][j] = $random;

            // golden model
            for (i = 0; i < N; i = i + 1)
                for (j = 0; j < N; j = j + 1) begin
                    C_gold[i][j] = 0;
                    for (k = 0; k < K; k = k + 1)
                        C_gold[i][j] = C_gold[i][j] + A[i][k] * B[k][j];
                end

            // clear between trials - operands zeroed too, or the stale pair
            // gets multiplied into the freshly cleared accumulator
            @(negedge clk);
            clear_acc = 1'b1;
            a_edge = {N*DATA_WIDTH{1'b0}};
            b_edge = {N*DATA_WIDTH{1'b0}};
            @(posedge clk);
            @(negedge clk);
            clear_acc = 1'b0;

            // stream the skewed wavefront
            for (t = 0; t < K + 2*N; t = t + 1) begin
                @(negedge clk);
                drive_cycle(t);
                @(posedge clk);
            end

            @(negedge clk);
            a_edge = {N*DATA_WIDTH{1'b0}};
            b_edge = {N*DATA_WIDTH{1'b0}};
            @(posedge clk);
            #1;

            for (i = 0; i < N; i = i + 1)
                for (j = 0; j < N; j = j + 1) begin
                    c_hw = $signed(c_flat[(i*N + j)*ACC_WIDTH +: ACC_WIDTH]);
                    if (c_hw !== C_gold[i][j]) begin
                        $display("FAIL trial %0d  C[%0d][%0d] hw=%0d gold=%0d",
                                 trial, i, j, c_hw, C_gold[i][j]);
                        errors = errors + 1;
                    end
                end
        end

        $display("--------------------------------------------------");
        $display("array %0dx%0d, int%0d operands, %0d random trials, %0d elements checked",
                 N, N, DATA_WIDTH, NUM_TRIALS, NUM_TRIALS*N*N);
        if (errors == 0)
            $display("PASS - all elements bit-exact against golden model");
        else
            $display("FAIL - %0d mismatch(es)", errors);
        $display("--------------------------------------------------");
        $finish;
    end

endmodule
