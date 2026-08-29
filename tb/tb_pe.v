// -----------------------------------------------------------------------------
// tb_pe.v - Testbench for the single Processing Element.
//
// Checks three things:
//   1. MAC accumulation - acc_out builds up sum of products over cycles
//   2. Operand forwarding - a_out/b_out present last cycle's operands (1 hop)
//   3. clear_acc - zeros the accumulator between GEMMs
//
// Includes negative operands to prove the signed arithmetic is real.
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_pe;

    parameter DATA_WIDTH = 8;
    parameter ACC_WIDTH  = 32;

    reg                          clk = 1'b0;
    reg                          rst_n;
    reg                          enable;
    reg                          clear_acc;
    reg  signed [DATA_WIDTH-1:0] a_in;
    reg  signed [DATA_WIDTH-1:0] b_in;

    wire signed [DATA_WIDTH-1:0] a_out;
    wire signed [DATA_WIDTH-1:0] b_out;
    wire signed [ACC_WIDTH-1:0]  acc_out;

    integer errors = 0;

    // 100 MHz
    always #5 clk = ~clk;

    pe #(
        .DATA_WIDTH (DATA_WIDTH),
        .ACC_WIDTH  (ACC_WIDTH)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .enable    (enable),
        .clear_acc (clear_acc),
        .a_in      (a_in),
        .b_in      (b_in),
        .a_out     (a_out),
        .b_out     (b_out),
        .acc_out   (acc_out)
    );

    // Drive one operand pair, advance one clock, then check the results that
    // the PE registered on that edge.
    task mac_step;
        input signed [DATA_WIDTH-1:0] a;
        input signed [DATA_WIDTH-1:0] b;
        input signed [ACC_WIDTH-1:0]  exp_acc;
        begin
            @(negedge clk);
            a_in = a;
            b_in = b;
            @(posedge clk);
            #1;
            if (acc_out !== exp_acc) begin
                $display("FAIL  a=%0d b=%0d : acc_out=%0d expected=%0d",
                         a, b, acc_out, exp_acc);
                errors = errors + 1;
            end else begin
                $display("ok    a=%4d b=%4d -> acc_out=%0d", a, b, acc_out);
            end

            // Operand forwarding: what went in this cycle comes out this cycle,
            // visible to the neighbour on the NEXT edge - one hop per cycle.
            if (a_out !== a || b_out !== b) begin
                $display("FAIL  forwarding: a_out=%0d (exp %0d) b_out=%0d (exp %0d)",
                         a_out, a, b_out, b);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("sim/tb_pe.vcd");
        $dumpvars(0, tb_pe);

        // ---- reset ----
        rst_n     = 1'b0;
        enable    = 1'b1;
        clear_acc = 1'b0;
        a_in      = 8'sd0;
        b_in      = 8'sd0;
        repeat (2) @(posedge clk);
        #1;
        if (acc_out !== 0) begin
            $display("FAIL  acc_out not zero after reset: %0d", acc_out);
            errors = errors + 1;
        end else begin
            $display("ok    acc_out == 0 after reset");
        end

        @(negedge clk);
        rst_n = 1'b1;

        // ---- MAC accumulation ----
        // running sum, computed by hand:
        //   2*3   =   6            -> 6
        //   4*5   =  20   6+20     -> 26
        //  -3*6   = -18   26-18    -> 8
        //   7*7   =  49   8+49     -> 57
        $display("--- accumulation ---");
        mac_step( 8'sd2,  8'sd3,  32'sd6 );
        mac_step( 8'sd4,  8'sd5,  32'sd26);
        mac_step(-8'sd3,  8'sd6,  32'sd8 );
        mac_step( 8'sd7,  8'sd7,  32'sd57);

        // ---- clear_acc ----
        $display("--- clear_acc ---");
        @(negedge clk);
        clear_acc = 1'b1;
        a_in      = 8'sd0;
        b_in      = 8'sd0;
        @(posedge clk);
        #1;
        if (acc_out !== 0) begin
            $display("FAIL  clear_acc did not zero accumulator: %0d", acc_out);
            errors = errors + 1;
        end else begin
            $display("ok    clear_acc zeroed accumulator");
        end

        @(negedge clk);
        clear_acc = 1'b0;

        // ---- accumulate again after clear, proving no leftover state ----
        $display("--- second GEMM after clear ---");
        mac_step( 8'sd10, 8'sd10, 32'sd100);
        mac_step( 8'sd1,  8'sd2,  32'sd102);

        // ---- extremes: int8 range is -128..127 ----
        $display("--- signed extremes ---");
        @(negedge clk);
        clear_acc = 1'b1;
        // Zero the operands too. Otherwise the stale a_in/b_in from the last
        // mac_step are still multiplied on the cycle after clear_acc drops,
        // injecting a stray product into the "cleared" accumulator.
        a_in = 8'sd0;
        b_in = 8'sd0;
        @(posedge clk);
        @(negedge clk);
        clear_acc = 1'b0;
        // -128 * -128 = 16384
        mac_step(-8'sd128, -8'sd128, 32'sd16384);
        //  127 * -128 = -16256   16384-16256 = 128
        mac_step( 8'sd127, -8'sd128, 32'sd128);

        $display("--------------------------------");
        if (errors == 0)
            $display("PASS - all PE checks passed");
        else
            $display("FAIL - %0d check(s) failed", errors);
        $display("--------------------------------");

        $finish;
    end

endmodule
