// -----------------------------------------------------------------------------
// tb_systolic_array.v - 4x4 output-stationary GEMM, checked bit-exact against
// a behavioural golden model.
//
// The testbench performs the SKEW that the array itself does not:
//   A[i][k] is injected into row i    at cycle k + i
//   B[k][j] is injected into column j at cycle k + j
// so both land on PE(i,j) at cycle k + i + j and meet there.
// Outside that window the edges are driven with zeros (pipeline fill/drain).
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_systolic_array;

    parameter N          = 4;
    parameter K          = 4;   // inner dimension
    parameter DATA_WIDTH = 8;
    parameter ACC_WIDTH  = 32;

    reg                     clk = 1'b0;
    reg                     rst_n;
    reg                     enable;
    reg                     clear_acc;
    reg  [N*DATA_WIDTH-1:0] a_edge;
    reg  [N*DATA_WIDTH-1:0] b_edge;
    wire [N*N*ACC_WIDTH-1:0] c_flat;

    integer i, j, k, t;
    integer errors = 0;

    reg signed [DATA_WIDTH-1:0] A [0:N-1][0:K-1];
    reg signed [DATA_WIDTH-1:0] B [0:K-1][0:N-1];
    reg signed [ACC_WIDTH-1:0]  C_gold [0:N-1][0:N-1];
    reg signed [ACC_WIDTH-1:0]  c_hw;

    always #5 clk = ~clk;

    // ---- debug view -----------------------------------------------------
    // c_flat is a 512-bit packed bus - unreadable in a waveform. This unpacks
    // it into a 2-D array so each result can be waved individually as
    // c_view[i][j]. Testbench only: costs nothing, synthesizes to nothing.
    //     add wave /tb_systolic_array/c_view
    wire signed [ACC_WIDTH-1:0] c_view [0:N-1][0:N-1];
    genvar gi, gj;
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : g_view_row
            for (gj = 0; gj < N; gj = gj + 1) begin : g_view_col
                assign c_view[gi][gj] =
                    $signed(c_flat[(gi*N + gj)*ACC_WIDTH +: ACC_WIDTH]);
            end
        end
    endgenerate

    systolic_array #(
        .N          (N),
        .DATA_WIDTH (DATA_WIDTH),
        .ACC_WIDTH  (ACC_WIDTH)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .enable    (enable),
        .clear_acc (clear_acc),
        .a_edge    (a_edge),
        .b_edge    (b_edge),
        .c_flat    (c_flat)
    );

    // Drive one cycle of the skewed wavefront at time step t.
    task drive_cycle;
        input integer t;
        integer r, c, idx;
        begin
            a_edge = {N*DATA_WIDTH{1'b0}};
            b_edge = {N*DATA_WIDTH{1'b0}};

            // A[r][t-r] enters row r at cycle t
            for (r = 0; r < N; r = r + 1) begin
                idx = t - r;
                if (idx >= 0 && idx < K)
                    a_edge[r*DATA_WIDTH +: DATA_WIDTH] = A[r][idx];
            end

            // B[t-c][c] enters column c at cycle t
            for (c = 0; c < N; c = c + 1) begin
                idx = t - c;
                if (idx >= 0 && idx < K)
                    b_edge[c*DATA_WIDTH +: DATA_WIDTH] = B[idx][c];
            end
        end
    endtask

    initial begin
        $dumpfile("sim/tb_systolic_array.vcd");
        $dumpvars(0, tb_systolic_array);

        // ---- operands ----
        A[0][0]= 1; A[0][1]= 2; A[0][2]= 3; A[0][3]= 4;
        A[1][0]= 5; A[1][1]= 6; A[1][2]= 7; A[1][3]= 8;
        A[2][0]= 9; A[2][1]=10; A[2][2]=11; A[2][3]=12;
        A[3][0]=13; A[3][1]=-14;A[3][2]=15; A[3][3]=-16;   // negatives on purpose

        B[0][0]= 1; B[0][1]= 0; B[0][2]= 2; B[0][3]= 1;
        B[1][0]= 0; B[1][1]= 1; B[1][2]= 1; B[1][3]= 2;
        B[2][0]= 2; B[2][1]= 1; B[2][2]= 0; B[2][3]=-1;
        B[3][0]= 1; B[3][1]= 2; B[3][2]=-1; B[3][3]= 0;

        // ---- golden model ----
        for (i = 0; i < N; i = i + 1)
            for (j = 0; j < N; j = j + 1) begin
                C_gold[i][j] = 0;
                for (k = 0; k < K; k = k + 1)
                    C_gold[i][j] = C_gold[i][j] + A[i][k] * B[k][j];
            end

        // ---- reset ----
        rst_n     = 1'b0;
        enable    = 1'b1;
        clear_acc = 1'b0;
        a_edge    = {N*DATA_WIDTH{1'b0}};
        b_edge    = {N*DATA_WIDTH{1'b0}};
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        // ---- stream the skewed wavefront ----
        // last operand enters at cycle (K-1)+(N-1) and needs (N-1) more hops
        // to reach PE(N-1,N-1), so K + 2N - 2 cycles covers fill + drain.
        for (t = 0; t < K + 2*N; t = t + 1) begin
            @(negedge clk);
            drive_cycle(t);
            @(posedge clk);
        end

        // let the final accumulate settle
        @(negedge clk);
        a_edge = {N*DATA_WIDTH{1'b0}};
        b_edge = {N*DATA_WIDTH{1'b0}};
        @(posedge clk);
        #1;

        // ---- compare ----
        $display("      C (hardware)                 C (golden)");
        for (i = 0; i < N; i = i + 1) begin
            for (j = 0; j < N; j = j + 1) begin
                c_hw = $signed(c_flat[(i*N + j)*ACC_WIDTH +: ACC_WIDTH]);
                if (c_hw !== C_gold[i][j]) begin
                    $display("FAIL  C[%0d][%0d] hw=%0d gold=%0d",
                             i, j, c_hw, C_gold[i][j]);
                    errors = errors + 1;
                end
            end
        end

        for (i = 0; i < N; i = i + 1) begin
            $write("  ");
            for (j = 0; j < N; j = j + 1)
                $write("%6d", $signed(c_flat[(i*N + j)*ACC_WIDTH +: ACC_WIDTH]));
            $write("      ");
            for (j = 0; j < N; j = j + 1)
                $write("%6d", C_gold[i][j]);
            $write("\n");
        end

        $display("--------------------------------");
        if (errors == 0)
            $display("PASS - 4x4 GEMM bit-exact against golden model");
        else
            $display("FAIL - %0d element(s) mismatched", errors);
        $display("--------------------------------");

        $finish;
    end

endmodule
