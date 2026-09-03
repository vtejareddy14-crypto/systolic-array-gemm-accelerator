// -----------------------------------------------------------------------------
// tb_tiling_controller.v - Phase 2 verification + the "before" measurement.
//
// Two jobs:
//   1. CORRECTNESS - every (m,n,k) tile is emitted exactly once, remainders
//      are right, clear_acc fires once per output tile (not once per tile).
//   2. MEASUREMENT - count useful vs total MAC slots. The gap is the waste
//      that zero-padding causes, which is the ceiling on what Phase 3 can save.
//
//        useful slots = rows_valid * cols_valid * depth_valid
//        total  slots = ARR * ARR * ARR      (every tile occupies a full array)
//        utilisation  = useful / total
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_tiling_controller;

    parameter ARR   = 4;
    parameter DIM_W = 16;

    reg                  clk = 1'b0;
    reg                  rst_n;
    reg                  start;
    reg  [DIM_W-1:0]     M, K, N;
    reg                  tile_ack;

    wire [DIM_W-1:0]     m_base, n_base, k_base;
    wire [DIM_W-1:0]     rows_valid, cols_valid, depth_valid;
    wire                 is_boundary;
    wire                 tile_valid, clear_acc, c_tile_done, busy, done;

    integer errors = 0;

    // per-run accounting
    integer tiles_total, tiles_boundary, clears, out_tiles;
    integer useful_slots, total_slots;
    integer exp_useful;

    // coverage map: how many times each (m,n,k) tile was emitted
    integer seen [0:63][0:63][0:63];
    integer mi, ni, ki;

    always #5 clk = ~clk;

    // clear_acc and c_tile_done are single-cycle pulses. The main loop below
    // skips cycles while handshaking tile_ack, so they must be counted by an
    // independent monitor that sees every clock.
    always @(posedge clk) begin
        if (rst_n) begin
            if (clear_acc)   clears    = clears    + 1;
            if (c_tile_done) out_tiles = out_tiles + 1;
        end
    end

    tiling_controller #(.ARR(ARR), .DIM_W(DIM_W)) dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .M(M), .K(K), .N(N), .tile_ack(tile_ack),
        .m_base(m_base), .n_base(n_base), .k_base(k_base),
        .rows_valid(rows_valid), .cols_valid(cols_valid),
        .depth_valid(depth_valid), .is_boundary(is_boundary),
        .tile_valid(tile_valid), .clear_acc(clear_acc),
        .c_tile_done(c_tile_done), .busy(busy), .done(done)
    );

    function integer ceil_div;
        input integer a, b;
        begin
            ceil_div = (a + b - 1) / b;
        end
    endfunction

    // Run one complete GEMM, accounting as we go.
    task run_gemm;
        input integer m_in, k_in, n_in;
        integer guard;
        begin
            M = m_in[DIM_W-1:0];
            K = k_in[DIM_W-1:0];
            N = n_in[DIM_W-1:0];

            tiles_total    = 0;
            tiles_boundary = 0;
            clears         = 0;
            out_tiles      = 0;
            useful_slots   = 0;
            total_slots    = 0;

            for (mi = 0; mi < 64; mi = mi + 1)
                for (ni = 0; ni < 64; ni = ni + 1)
                    for (ki = 0; ki < 64; ki = ki + 1)
                        seen[mi][ni][ki] = 0;

            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;

            guard = 0;
            while (!done && guard < 200000) begin
                @(negedge clk);
                guard = guard + 1;

                if (tile_valid && !tile_ack) begin
                    // record this tile
                    tiles_total = tiles_total + 1;
                    if (is_boundary) tiles_boundary = tiles_boundary + 1;

                    seen[m_base/ARR][n_base/ARR][k_base/ARR] =
                        seen[m_base/ARR][n_base/ARR][k_base/ARR] + 1;

                    useful_slots = useful_slots +
                                   (rows_valid * cols_valid * depth_valid);
                    total_slots  = total_slots + (ARR * ARR * ARR);

                    // sanity: remainders must never exceed ARR or be zero
                    if (rows_valid  > ARR || rows_valid  == 0 ||
                        cols_valid  > ARR || cols_valid  == 0 ||
                        depth_valid > ARR || depth_valid == 0) begin
                        $display("FAIL bad remainder at (%0d,%0d,%0d): %0d %0d %0d",
                                 m_base, n_base, k_base,
                                 rows_valid, cols_valid, depth_valid);
                        errors = errors + 1;
                    end

                    tile_ack = 1'b1;
                    @(negedge clk);
                    tile_ack = 1'b0;
                end
            end

            if (guard >= 200000) begin
                $display("FAIL M=%0d K=%0d N=%0d : controller never finished",
                         m_in, k_in, n_in);
                errors = errors + 1;
            end

            // ---- correctness checks ----
            // every tile exactly once
            for (mi = 0; mi < ceil_div(m_in, ARR); mi = mi + 1)
                for (ni = 0; ni < ceil_div(n_in, ARR); ni = ni + 1)
                    for (ki = 0; ki < ceil_div(k_in, ARR); ki = ki + 1)
                        if (seen[mi][ni][ki] != 1) begin
                            $display("FAIL tile (%0d,%0d,%0d) emitted %0d times",
                                     mi, ni, ki, seen[mi][ni][ki]);
                            errors = errors + 1;
                        end

            if (tiles_total !== ceil_div(m_in,ARR)*ceil_div(n_in,ARR)*ceil_div(k_in,ARR)) begin
                $display("FAIL tile count %0d, expected %0d",
                         tiles_total,
                         ceil_div(m_in,ARR)*ceil_div(n_in,ARR)*ceil_div(k_in,ARR));
                errors = errors + 1;
            end

            // clear_acc must fire once per OUTPUT tile, not once per tile
            if (clears !== ceil_div(m_in,ARR)*ceil_div(n_in,ARR)) begin
                $display("FAIL clear_acc fired %0d times, expected %0d",
                         clears, ceil_div(m_in,ARR)*ceil_div(n_in,ARR));
                errors = errors + 1;
            end

            if (out_tiles !== ceil_div(m_in,ARR)*ceil_div(n_in,ARR)) begin
                $display("FAIL c_tile_done fired %0d times, expected %0d",
                         out_tiles, ceil_div(m_in,ARR)*ceil_div(n_in,ARR));
                errors = errors + 1;
            end

            // useful slots must equal M*K*N exactly - every real MAC, once
            exp_useful = m_in * k_in * n_in;
            if (useful_slots !== exp_useful) begin
                $display("FAIL useful slots %0d, expected M*K*N = %0d",
                         useful_slots, exp_useful);
                errors = errors + 1;
            end

            $display("  %4d x%4d x%4d | tiles %5d | boundary %5d (%5.1f%%) | util %6.2f%% | wasted %0d slots",
                     m_in, k_in, n_in, tiles_total, tiles_boundary,
                     100.0*tiles_boundary/tiles_total,
                     100.0*useful_slots/total_slots,
                     total_slots - useful_slots);
        end
    endtask

    initial begin
        rst_n    = 1'b0;
        start    = 1'b0;
        tile_ack = 1'b0;
        M = 0; K = 0; N = 0;
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        $display("");
        $display("=== exact multiples of ARR=%0d - no boundary tiles expected ===", ARR);
        run_gemm( 4,  4,  4);
        run_gemm( 8,  8,  8);
        run_gemm(16, 16, 16);

        $display("");
        $display("=== one dimension short ===");
        run_gemm( 5,  4,  4);   // M remainder 1
        run_gemm( 4,  5,  4);   // K remainder 1
        run_gemm( 4,  4,  5);   // N remainder 1
        run_gemm( 7,  8,  8);   // M remainder 3
        run_gemm(20,  8,  8);   // 20 is a multiple of 4 - no boundary at ARR=4
        run_gemm(18,  8,  8);   // 18 mod 4 = 2 - M-dimension boundary

        $display("");
        $display("=== all dimensions awkward ===");
        run_gemm( 5,  5,  5);
        run_gemm( 9,  7, 11);
        run_gemm(13, 13, 13);
        run_gemm(17, 19, 23);

        $display("");
        $display("=== degenerate ===");
        run_gemm( 1,  1,  1);
        run_gemm( 1, 16, 16);
        run_gemm(16,  1, 16);

        $display("");
        $display("--------------------------------------------------");
        if (errors == 0)
            $display("PASS - tile sequencing correct for all shapes");
        else
            $display("FAIL - %0d error(s)", errors);
        $display("--------------------------------------------------");
        $finish;
    end

endmodule
