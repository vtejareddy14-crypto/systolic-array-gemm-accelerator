// -----------------------------------------------------------------------------
// tiling_controller.v - Phase 2. Sequences an arbitrary MxKxN GEMM as a series
// of ARR x ARR tiles, and reports the live remainder for every tile.
//
// Loop order is  m_base -> n_base -> k_base  (k innermost), because the array
// is output-stationary: every k-tile for a given (m,n) output tile accumulates
// into the SAME PEs. So clear_acc fires once per output tile, not once per
// tile - the k-tiles chain into each other.
//
// The three *_valid outputs are the remainders. For a full tile they equal ARR;
// for a boundary tile they are smaller. Phase 2 uses them only to COUNT wasted
// MAC slots (zero-padding still happens in the datapath). Phase 3 will use the
// same signals to gate the unused rows/columns.
//
//   rows_valid  = min(ARR, M - m_base)   real rows    this tile  (M dimension)
//   cols_valid  = min(ARR, N - n_base)   real columns this tile  (N dimension)
//   depth_valid = min(ARR, K - k_base)   real k-steps this tile  (K dimension)
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tiling_controller #(
    parameter ARR   = 4,     // physical array dimension
    parameter DIM_W = 16     // bit width of M / K / N
) (
    input  wire                clk,
    input  wire                rst_n,

    input  wire                start,      // pulse to begin a GEMM
    input  wire [DIM_W-1:0]    M,
    input  wire [DIM_W-1:0]    K,
    input  wire [DIM_W-1:0]    N,

    input  wire                tile_ack,   // datapath: "current tile consumed"

    output reg  [DIM_W-1:0]    m_base,     // top-left corner of this tile
    output reg  [DIM_W-1:0]    n_base,
    output reg  [DIM_W-1:0]    k_base,

    output wire [DIM_W-1:0]    rows_valid,  // <-- the remainder, live
    output wire [DIM_W-1:0]    cols_valid,
    output wire [DIM_W-1:0]    depth_valid,
    output wire                is_boundary, // any dimension short this tile

    output reg                 tile_valid,  // a tile is presented
    output reg                 clear_acc,   // new output tile starting
    output reg                 c_tile_done, // output tile finished accumulating
    output reg                 busy,
    output reg                 done
);

    localparam S_IDLE = 2'd0,
               S_TILE = 2'd1,
               S_WAIT = 2'd2,
               S_DONE = 2'd3;

    reg [1:0]       state;
    reg [DIM_W-1:0] M_r, K_r, N_r;

    // ---- the remainder computation -------------------------------------------
    // This is the whole point of the module. It is a subtract and a compare on
    // counters the loop already has to maintain, evaluated once per tile.
    wire [DIM_W-1:0] rows_left = M_r - m_base;
    wire [DIM_W-1:0] cols_left = N_r - n_base;
    wire [DIM_W-1:0] deps_left = K_r - k_base;

    assign rows_valid  = (rows_left >= ARR) ? ARR[DIM_W-1:0] : rows_left;
    assign cols_valid  = (cols_left >= ARR) ? ARR[DIM_W-1:0] : cols_left;
    assign depth_valid = (deps_left >= ARR) ? ARR[DIM_W-1:0] : deps_left;

    assign is_boundary = (rows_valid  != ARR) ||
                         (cols_valid  != ARR) ||
                         (depth_valid != ARR);

    // ---- next-position arithmetic --------------------------------------------
    wire k_last = (k_base + ARR) >= K_r;
    wire n_last = (n_base + ARR) >= N_r;
    wire m_last = (m_base + ARR) >= M_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            m_base      <= {DIM_W{1'b0}};
            n_base      <= {DIM_W{1'b0}};
            k_base      <= {DIM_W{1'b0}};
            M_r         <= {DIM_W{1'b0}};
            K_r         <= {DIM_W{1'b0}};
            N_r         <= {DIM_W{1'b0}};
            tile_valid  <= 1'b0;
            clear_acc   <= 1'b0;
            c_tile_done <= 1'b0;
            busy        <= 1'b0;
            done        <= 1'b0;
        end else begin
            // single-cycle pulses default low
            clear_acc   <= 1'b0;
            c_tile_done <= 1'b0;

            case (state)

                S_IDLE: begin
                    done       <= 1'b0;
                    tile_valid <= 1'b0;
                    if (start) begin
                        M_r    <= M;
                        K_r    <= K;
                        N_r    <= N;
                        m_base <= {DIM_W{1'b0}};
                        n_base <= {DIM_W{1'b0}};
                        k_base <= {DIM_W{1'b0}};
                        busy   <= 1'b1;
                        // first output tile starts: clear the accumulators
                        clear_acc <= 1'b1;
                        state     <= S_TILE;
                    end
                end

                // present the tile to the datapath
                S_TILE: begin
                    if (M_r == 0 || K_r == 0 || N_r == 0) begin
                        state <= S_DONE;
                    end else begin
                        tile_valid <= 1'b1;
                        state      <= S_WAIT;
                    end
                end

                // hold until the datapath has consumed it, then advance
                S_WAIT: begin
                    if (tile_ack) begin
                        tile_valid <= 1'b0;

                        if (!k_last) begin
                            // more depth for this same output tile: keep
                            // accumulating in place, do NOT clear
                            k_base <= k_base + ARR[DIM_W-1:0];
                            state  <= S_TILE;
                        end else begin
                            // this output tile is complete
                            c_tile_done <= 1'b1;
                            k_base      <= {DIM_W{1'b0}};

                            if (!n_last) begin
                                n_base    <= n_base + ARR[DIM_W-1:0];
                                clear_acc <= 1'b1;
                                state     <= S_TILE;
                            end else begin
                                n_base <= {DIM_W{1'b0}};
                                if (!m_last) begin
                                    m_base    <= m_base + ARR[DIM_W-1:0];
                                    clear_acc <= 1'b1;
                                    state     <= S_TILE;
                                end else begin
                                    state <= S_DONE;
                                end
                            end
                        end
                    end
                end

                S_DONE: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

            endcase
        end
    end

endmodule
