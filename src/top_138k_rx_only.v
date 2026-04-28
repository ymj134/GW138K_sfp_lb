`timescale 1 ns / 1 ps

// =============================================================================
// GW15K -> GW138K cross-board 8B10B verification
// Role : 138K RX checker only
// Mode : RoraLink 8B10B Framing mode, 32-bit user data, 1 lane
// =============================================================================
module top
(
    input  osc_clk_i,       // 50 MHz
    input  resetn_i,        // low-active
    output SFP_TX_DISABLE,
    output [3:0] led_o
);

`define LANE_WIDTH       1
`define LANE_DATA_WIDTH  32

parameter DATA_WIDTH      = `LANE_DATA_WIDTH * `LANE_WIDTH;
parameter STRB_WIDTH      = DATA_WIDTH / 8;
parameter LANE_WIDTH      = `LANE_WIDTH;
parameter LANE_DATA_WIDTH = `LANE_DATA_WIDTH;
parameter FRAME_BEATS     = 16;

localparam [31:0] TOP_VERSION = 32'h1381_0001;
localparam [15:0] PASS_FRAME_TH = 16'd8;

// Must match the 15K TX top.
localparam [31:0] TX_PATTERN0 = 32'h12_34_56_78;
localparam [31:0] TX_PATTERN1 = 32'h9A_BC_DE_F0;
localparam [31:0] TX_PATTERN2 = 32'h55_AA_C3_3C;
localparam [31:0] TX_PATTERN3 = 32'h0F_1E_2D_3C;

assign SFP_TX_DISABLE = 1'b0;

// -----------------------------------------------------------------------------
// User interface
// -----------------------------------------------------------------------------
wire [DATA_WIDTH-1:0] user_tx_data  /* synthesis syn_keep=1 */;
wire [STRB_WIDTH-1:0] user_tx_strb  /* synthesis syn_keep=1 */;
wire                  user_tx_valid /* synthesis syn_keep=1 */;
wire                  user_tx_last  /* synthesis syn_keep=1 */;
wire                  user_tx_ready /* synthesis syn_keep=1 */;

wire [DATA_WIDTH-1:0] user_rx_data  /* synthesis syn_keep=1 */;
wire [STRB_WIDTH-1:0] user_rx_strb  /* synthesis syn_keep=1 */;
wire                  user_rx_valid /* synthesis syn_keep=1 */;
wire                  user_rx_last  /* synthesis syn_keep=1 */;

wire crc_pass_fail_n;
wire crc_valid;
wire hard_err;
wire soft_err;
wire frame_err;
wire channel_up                  /* synthesis syn_keep=1 */;
wire [LANE_WIDTH-1:0] lane_up    /* synthesis syn_keep=1 */;

// -----------------------------------------------------------------------------
// Clock / reset / SerDes status
// -----------------------------------------------------------------------------
wire sys_clk                     /* synthesis syn_keep=1 */;
wire sys_rst;
wire cfg_clk;
wire cfg_pll_lock;
wire cfg_rst;
wire sys_reset_gen;
wire gt_reset;
wire gt_pcs_tx_reset;
wire gt_pcs_rx_reset;
wire [LANE_WIDTH-1:0] gt_pcs_tx_clk;
wire [LANE_WIDTH-1:0] gt_pcs_rx_clk;
wire gt_pll_ok;
wire [LANE_WIDTH-1:0] gt_rx_align_link;
wire [LANE_WIDTH-1:0] gt_rx_pma_lock;
wire [LANE_WIDTH-1:0] gt_rx_k_lock;
wire link_reset;
wire sys_reset;

assign sys_clk = gt_pcs_tx_clk[0];

assign gt_reset        = 1'b0;
assign gt_pcs_tx_reset = 1'b0;
assign gt_pcs_rx_reset = 1'b0;

assign sys_reset_gen = cfg_pll_lock & gt_pll_ok & resetn_i;

// LED definition:
// led_o[0] = cfg PLL lock
// led_o[1] = GT PLL lock
// led_o[2] = channel_up sampled in sys_clk
// led_o[3] = RX checker pass
assign led_o[0] = cfg_pll_lock;
assign led_o[1] = gt_pll_ok;
assign led_o[2] = channel_up_1d;
assign led_o[3] = test_pass;

// -----------------------------------------------------------------------------
// PLL and reset generator
// Keep using the 138K PLL port list from your current project.
// -----------------------------------------------------------------------------
Gowin_PLL u_Gowin_PLL
(
    .reset    (!resetn_i),
    .lock     (cfg_pll_lock),
    .clkout0  (cfg_clk),
    .clkin    (osc_clk_i),
    .init_clk (osc_clk_i)
);

reset_gen u_cfg_reset_gen
(
    .i_clk1 (cfg_clk),
    .i_lock (cfg_pll_lock),
    .o_rst1 (cfg_rst)
);

reset_gen u_sys_reset_gen
(
    .i_clk1 (sys_clk),
    .i_lock (sys_reset_gen),
    .o_rst1 (sys_rst)
);

// -----------------------------------------------------------------------------
// RX-only board: do not inject user payload from 138K.
// The IP can still transmit its own idles/link control while user_tx_valid = 0.
// -----------------------------------------------------------------------------
assign user_tx_data  = {DATA_WIDTH{1'b0}};
assign user_tx_strb  = {STRB_WIDTH{1'b1}};
assign user_tx_valid = 1'b0;
assign user_tx_last  = 1'b0;

// -----------------------------------------------------------------------------
// RX checker
// First received user_rx_last is used as frame boundary acquisition. After that,
// the next valid beat must be pattern0, then pattern1/2/3..., last on beat 15.
// -----------------------------------------------------------------------------
reg        channel_up_1d;
reg        rx_aligned;
reg [7:0]  rx_beat_cnt;
reg [31:0] rx_last_data;
reg [31:0] rx_expected_d;
reg [31:0] rx_first_bad_data;
reg [31:0] rx_first_bad_expected;
reg [7:0]  rx_first_bad_beat;
reg [31:0] rx_valid_cnt;
reg [31:0] rx_frame_cnt;
reg [15:0] rx_good_frame_cnt;
reg        rx_seen_valid;
reg        rx_seen_last;
reg        rx_activity_toggle;
reg        payload_err_seen;
reg        last_err_seen;
reg        hard_err_seen;
reg        soft_err_seen;
reg        frame_err_seen;
reg        crc_err_seen;
reg        test_pass;

wire [31:0] rx_expected_word;
wire        rx_payload_mismatch;
wire        rx_last_expected;
wire        rx_last_mismatch;
wire        rx_frame_good_now;
wire        any_err_seen;
wire        any_err_now;

function [31:0] f_rx_pattern;
    input [1:0] sel;
    begin
        case (sel)
            2'd0: f_rx_pattern = TX_PATTERN0;
            2'd1: f_rx_pattern = TX_PATTERN1;
            2'd2: f_rx_pattern = TX_PATTERN2;
            2'd3: f_rx_pattern = TX_PATTERN3;
            default: f_rx_pattern = TX_PATTERN0;
        endcase
    end
endfunction

assign rx_expected_word    = f_rx_pattern(rx_beat_cnt[1:0]);
assign rx_last_expected    = (rx_beat_cnt == FRAME_BEATS-1);
assign rx_payload_mismatch = rx_aligned & user_rx_valid & (user_rx_data != rx_expected_word);
assign rx_last_mismatch    = rx_aligned & user_rx_valid & (user_rx_last != rx_last_expected);
assign rx_frame_good_now   = rx_aligned & user_rx_valid & user_rx_last & rx_last_expected &
                             !rx_payload_mismatch & !rx_last_mismatch;
assign any_err_seen        = payload_err_seen | last_err_seen | hard_err_seen |
                             soft_err_seen | frame_err_seen | crc_err_seen;
assign any_err_now         = hard_err | soft_err | frame_err |
                             (crc_valid & !crc_pass_fail_n) |
                             rx_payload_mismatch | rx_last_mismatch;

always @(posedge sys_clk) begin
    if (sys_rst) begin
        channel_up_1d         <= 1'b0;
        rx_aligned            <= 1'b0;
        rx_beat_cnt           <= 8'd0;
        rx_last_data          <= 32'd0;
        rx_expected_d         <= 32'd0;
        rx_first_bad_data     <= 32'd0;
        rx_first_bad_expected <= 32'd0;
        rx_first_bad_beat     <= 8'd0;
        rx_valid_cnt          <= 32'd0;
        rx_frame_cnt          <= 32'd0;
        rx_good_frame_cnt     <= 16'd0;
        rx_seen_valid         <= 1'b0;
        rx_seen_last          <= 1'b0;
        rx_activity_toggle    <= 1'b0;
        payload_err_seen      <= 1'b0;
        last_err_seen         <= 1'b0;
        hard_err_seen         <= 1'b0;
        soft_err_seen         <= 1'b0;
        frame_err_seen        <= 1'b0;
        crc_err_seen          <= 1'b0;
        test_pass             <= 1'b0;
    end else begin
        channel_up_1d <= channel_up;

        if (!channel_up_1d) begin
            rx_aligned            <= 1'b0;
            rx_beat_cnt           <= 8'd0;
            rx_last_data          <= 32'd0;
            rx_expected_d         <= 32'd0;
            rx_first_bad_data     <= 32'd0;
            rx_first_bad_expected <= 32'd0;
            rx_first_bad_beat     <= 8'd0;
            rx_valid_cnt          <= 32'd0;
            rx_frame_cnt          <= 32'd0;
            rx_good_frame_cnt     <= 16'd0;
            rx_seen_valid         <= 1'b0;
            rx_seen_last          <= 1'b0;
            rx_activity_toggle    <= 1'b0;
            payload_err_seen      <= 1'b0;
            last_err_seen         <= 1'b0;
            hard_err_seen         <= 1'b0;
            soft_err_seen         <= 1'b0;
            frame_err_seen        <= 1'b0;
            crc_err_seen          <= 1'b0;
            test_pass             <= 1'b0;
        end else begin
            if (hard_err) hard_err_seen <= 1'b1;
            if (soft_err) soft_err_seen <= 1'b1;
            if (frame_err) frame_err_seen <= 1'b1;
            if (crc_valid && !crc_pass_fail_n) crc_err_seen <= 1'b1;

            if (user_rx_valid) begin
                rx_seen_valid      <= 1'b1;
                rx_valid_cnt       <= rx_valid_cnt + 32'd1;
                rx_activity_toggle <= ~rx_activity_toggle;
                rx_last_data       <= user_rx_data;
                rx_expected_d      <= rx_expected_word;

                if (user_rx_last)
                    rx_seen_last <= 1'b1;

                if (!rx_aligned) begin
                    if (user_rx_last) begin
                        rx_aligned  <= 1'b1;
                        rx_beat_cnt <= 8'd0;
                        rx_frame_cnt <= rx_frame_cnt + 32'd1;
                    end
                end else begin
                    if (rx_payload_mismatch) begin
                        payload_err_seen <= 1'b1;
                        if (!payload_err_seen) begin
                            rx_first_bad_data     <= user_rx_data;
                            rx_first_bad_expected <= rx_expected_word;
                            rx_first_bad_beat     <= rx_beat_cnt;
                        end
                    end

                    if (rx_last_mismatch)
                        last_err_seen <= 1'b1;

                    if (rx_payload_mismatch || rx_last_mismatch) begin
                        rx_good_frame_cnt <= 16'd0;
                    end else if (rx_frame_good_now) begin
                        if (rx_good_frame_cnt != 16'hffff)
                            rx_good_frame_cnt <= rx_good_frame_cnt + 16'd1;
                    end

                    if (user_rx_last) begin
                        rx_beat_cnt <= 8'd0;
                        rx_frame_cnt <= rx_frame_cnt + 32'd1;
                    end else if (rx_beat_cnt == FRAME_BEATS-1) begin
                        rx_beat_cnt <= 8'd0;
                    end else begin
                        rx_beat_cnt <= rx_beat_cnt + 8'd1;
                    end
                end
            end

            if (any_err_seen || any_err_now)
                test_pass <= 1'b0;
            else if (rx_good_frame_cnt >= PASS_FRAME_TH)
                test_pass <= 1'b1;
        end
    end
end

// -----------------------------------------------------------------------------
// ILA signals, search prefix: ila138_
// Recommended ILA clock: sys_clk / gt_pcs_tx_clk[0]
// Recommended trigger  : ila138_user_rx_valid == 1, or any *_err_seen == 1
// -----------------------------------------------------------------------------
wire [31:0] ila138_top_version          /* synthesis syn_keep=1 */ = TOP_VERSION;
wire        ila138_cfg_pll_lock         /* synthesis syn_keep=1 */ = cfg_pll_lock;
wire        ila138_cfg_rst              /* synthesis syn_keep=1 */ = cfg_rst;
wire        ila138_gt_pll_ok            /* synthesis syn_keep=1 */ = gt_pll_ok;
wire        ila138_sys_rst              /* synthesis syn_keep=1 */ = sys_rst;
wire        ila138_sys_reset            /* synthesis syn_keep=1 */ = sys_reset;
wire        ila138_link_reset           /* synthesis syn_keep=1 */ = link_reset;
wire        ila138_channel_up           /* synthesis syn_keep=1 */ = channel_up;
wire        ila138_channel_up_1d        /* synthesis syn_keep=1 */ = channel_up_1d;
wire [0:0]  ila138_lane_up              /* synthesis syn_keep=1 */ = lane_up;
wire [0:0]  ila138_gt_rx_pma_lock       /* synthesis syn_keep=1 */ = gt_rx_pma_lock;
wire [0:0]  ila138_gt_rx_k_lock         /* synthesis syn_keep=1 */ = gt_rx_k_lock;
wire [0:0]  ila138_gt_rx_align_link     /* synthesis syn_keep=1 */ = gt_rx_align_link;
wire [31:0] ila138_user_rx_data         /* synthesis syn_keep=1 */ = user_rx_data;
wire [3:0]  ila138_user_rx_strb         /* synthesis syn_keep=1 */ = user_rx_strb;
wire        ila138_user_rx_valid        /* synthesis syn_keep=1 */ = user_rx_valid;
wire        ila138_user_rx_last         /* synthesis syn_keep=1 */ = user_rx_last;
wire [7:0]  ila138_rx_beat_cnt          /* synthesis syn_keep=1 */ = rx_beat_cnt;
wire [31:0] ila138_rx_expected_word     /* synthesis syn_keep=1 */ = rx_expected_word;
wire [31:0] ila138_rx_last_data         /* synthesis syn_keep=1 */ = rx_last_data;
wire [31:0] ila138_rx_expected_d        /* synthesis syn_keep=1 */ = rx_expected_d;
wire        ila138_rx_aligned           /* synthesis syn_keep=1 */ = rx_aligned;
wire        ila138_rx_payload_mismatch  /* synthesis syn_keep=1 */ = rx_payload_mismatch;
wire        ila138_rx_last_expected     /* synthesis syn_keep=1 */ = rx_last_expected;
wire        ila138_rx_last_mismatch     /* synthesis syn_keep=1 */ = rx_last_mismatch;
wire [31:0] ila138_rx_first_bad_data    /* synthesis syn_keep=1 */ = rx_first_bad_data;
wire [31:0] ila138_rx_first_bad_expected/* synthesis syn_keep=1 */ = rx_first_bad_expected;
wire [7:0]  ila138_rx_first_bad_beat    /* synthesis syn_keep=1 */ = rx_first_bad_beat;
wire [31:0] ila138_rx_valid_cnt         /* synthesis syn_keep=1 */ = rx_valid_cnt;
wire [31:0] ila138_rx_frame_cnt         /* synthesis syn_keep=1 */ = rx_frame_cnt;
wire [15:0] ila138_rx_good_frame_cnt    /* synthesis syn_keep=1 */ = rx_good_frame_cnt;
wire        ila138_rx_seen_valid        /* synthesis syn_keep=1 */ = rx_seen_valid;
wire        ila138_rx_seen_last         /* synthesis syn_keep=1 */ = rx_seen_last;
wire        ila138_rx_activity_toggle   /* synthesis syn_keep=1 */ = rx_activity_toggle;
wire        ila138_crc_valid            /* synthesis syn_keep=1 */ = crc_valid;
wire        ila138_crc_pass_fail_n      /* synthesis syn_keep=1 */ = crc_pass_fail_n;
wire        ila138_hard_err             /* synthesis syn_keep=1 */ = hard_err;
wire        ila138_soft_err             /* synthesis syn_keep=1 */ = soft_err;
wire        ila138_frame_err            /* synthesis syn_keep=1 */ = frame_err;
wire        ila138_payload_err_seen     /* synthesis syn_keep=1 */ = payload_err_seen;
wire        ila138_last_err_seen        /* synthesis syn_keep=1 */ = last_err_seen;
wire        ila138_hard_err_seen        /* synthesis syn_keep=1 */ = hard_err_seen;
wire        ila138_soft_err_seen        /* synthesis syn_keep=1 */ = soft_err_seen;
wire        ila138_frame_err_seen       /* synthesis syn_keep=1 */ = frame_err_seen;
wire        ila138_crc_err_seen         /* synthesis syn_keep=1 */ = crc_err_seen;
wire        ila138_any_err_seen         /* synthesis syn_keep=1 */ = any_err_seen;
wire        ila138_any_err_now          /* synthesis syn_keep=1 */ = any_err_now;
wire        ila138_test_pass            /* synthesis syn_keep=1 */ = test_pass;
wire [31:0] ila138_user_tx_data         /* synthesis syn_keep=1 */ = user_tx_data;
wire        ila138_user_tx_valid        /* synthesis syn_keep=1 */ = user_tx_valid;
wire        ila138_user_tx_ready        /* synthesis syn_keep=1 */ = user_tx_ready;

// -----------------------------------------------------------------------------
// SerDes / RoraLink 8B10B IP
// -----------------------------------------------------------------------------
SerDes_Top u_SerDes_Top
(
    .RoraLink_8B10B_Top_reset_i           (sys_rst),
    .RoraLink_8B10B_Top_user_clk_i        (sys_clk),
    .RoraLink_8B10B_Top_init_clk_i        (cfg_clk),
    .RoraLink_8B10B_Top_user_pll_locked_i (gt_pll_ok),
    .RoraLink_8B10B_Top_link_reset_o      (link_reset),
    .RoraLink_8B10B_Top_sys_reset_o       (sys_reset),

    .RoraLink_8B10B_Top_user_tx_data_i    (user_tx_data),
    .RoraLink_8B10B_Top_user_tx_valid_i   (user_tx_valid),
    .RoraLink_8B10B_Top_user_tx_ready_o   (user_tx_ready),
    .RoraLink_8B10B_Top_user_tx_strb_i    (user_tx_strb),
    .RoraLink_8B10B_Top_user_tx_last_i    (user_tx_last),

    .RoraLink_8B10B_Top_user_rx_data_o    (user_rx_data),
    .RoraLink_8B10B_Top_user_rx_valid_o   (user_rx_valid),
    .RoraLink_8B10B_Top_user_rx_strb_o    (user_rx_strb),
    .RoraLink_8B10B_Top_user_rx_last_o    (user_rx_last),
    .RoraLink_8B10B_Top_crc_pass_fail_n_o (crc_pass_fail_n),
    .RoraLink_8B10B_Top_crc_valid_o       (crc_valid),

    .RoraLink_8B10B_Top_hard_err_o        (hard_err),
    .RoraLink_8B10B_Top_soft_err_o        (soft_err),
    .RoraLink_8B10B_Top_frame_err_o       (frame_err),
    .RoraLink_8B10B_Top_channel_up_o      (channel_up),
    .RoraLink_8B10B_Top_lane_up_o         (lane_up),

    .RoraLink_8B10B_Top_gt_pcs_tx_reset_i (gt_pcs_tx_reset),
    .RoraLink_8B10B_Top_gt_pcs_tx_clk_o   (gt_pcs_tx_clk),
    .RoraLink_8B10B_Top_gt_pcs_rx_reset_i (gt_pcs_rx_reset),
    .RoraLink_8B10B_Top_gt_rx_align_link_o(gt_rx_align_link),
    .RoraLink_8B10B_Top_gt_rx_pma_lock_o  (gt_rx_pma_lock),
    .RoraLink_8B10B_Top_gt_rx_k_lock_o    (gt_rx_k_lock),
    .RoraLink_8B10B_Top_gt_pcs_rx_clk_o   (gt_pcs_rx_clk),
    .RoraLink_8B10B_Top_gt_reset_i        (gt_reset),
    .RoraLink_8B10B_Top_gt_pll_lock_o     (gt_pll_ok)
);

endmodule

// =============================================================================
// reset_gen
// =============================================================================
module reset_gen
(
    input      i_clk1,
    input      i_lock,
    output reg o_rst1 = 1'b1
);
    reg [11:0] r_cnt = 12'd0;

    always @(posedge i_clk1) begin
        if (!i_lock) begin
            r_cnt  <= 12'd0;
            o_rst1 <= 1'b1;
        end else if (r_cnt < 12'hfff) begin
            r_cnt  <= r_cnt + 12'd1;
            o_rst1 <= 1'b1;
        end else begin
            o_rst1 <= 1'b0;
        end
    end
endmodule
