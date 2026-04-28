`timescale 1 ns / 1 ps

module top
(
    input           osc_clk_i,          // 50M
    input           resetn_i,           // low-active

    output          SFP_TX_DISABLE,

    output [3:0]    led_o
);

//==============================================================================
// 0) 参数定义
//==============================================================================
`define LANE_WIDTH      1
`define LANE_DATA_WIDTH 32

parameter DATA_WIDTH      = `LANE_DATA_WIDTH * `LANE_WIDTH;
parameter STRB_WIDTH      = DATA_WIDTH/8;
parameter LANE_WIDTH      = `LANE_WIDTH;
parameter LANE_DATA_WIDTH = `LANE_DATA_WIDTH;

// 每帧 16 个 32bit beat
parameter FRAME_BEATS     = 16;



assign  SFP_TX_DISABLE = 1'b0 ;
//==============================================================================
// 1) 用户接口信号
//==============================================================================
wire [DATA_WIDTH-1:0] user_tx_data /* synthesis syn_keep=1 */;
wire [STRB_WIDTH-1:0] user_tx_strb /* synthesis syn_keep=1 */;
wire                  user_tx_valid/* synthesis syn_keep=1 */;
wire                  user_tx_last /* synthesis syn_keep=1 */;
wire                  user_tx_ready/* synthesis syn_keep=1 */;

wire [DATA_WIDTH-1:0] user_rx_data /* synthesis syn_keep=1 */;
wire [STRB_WIDTH-1:0] user_rx_strb /* synthesis syn_keep=1 */;
wire                  user_rx_valid/* synthesis syn_keep=1 */;
wire                  user_rx_last /* synthesis syn_keep=1 */;

wire                  crc_pass_fail_n;
wire                  crc_valid;

wire                  hard_err;
wire                  soft_err;
wire                  frame_err;

wire                  channel_up /* synthesis syn_keep=1 */;
wire [LANE_WIDTH-1:0] lane_up    /* synthesis syn_keep=1 */;

//==============================================================================
// 2) 时钟 / 复位 / SerDes 状态
//==============================================================================
wire                  sys_clk     /* synthesis syn_keep=1 */;
wire                  sys_rst;
wire                  cfg_clk;
wire                  cfg_pll_lock;
wire                  cfg_rst;

wire                  sys_reset_gen;

wire                  gt_reset;
wire                  gt_pcs_tx_reset;
wire                  gt_pcs_rx_reset;

wire [LANE_WIDTH-1:0] gt_pcs_tx_clk;
wire [LANE_WIDTH-1:0] gt_pcs_rx_clk;
wire                  gt_pll_ok;

wire [LANE_WIDTH-1:0] gt_rx_align_link;
wire [LANE_WIDTH-1:0] gt_rx_pma_lock;
wire [LANE_WIDTH-1:0] gt_rx_k_lock;

wire                  link_reset;
wire                  sys_reset;

//==============================================================================
// 3) 最小 TX/RX 测试逻辑
//==============================================================================
reg  [31:0] tx_counter;
reg  [7:0]  tx_beat_cnt;

reg         channel_up_1d;
reg         rx_seen_valid;
reg         rx_seen_last;
reg         rx_activity_toggle;
reg         test_pass;

// 为了方便观察，保留少量“sticky”错误标志
reg         hard_err_seen;
reg         soft_err_seen;
reg         frame_err_seen;
reg         crc_err_seen;

//==============================================================================
// 4) 顶层固定连接
//==============================================================================


// LED 定义：
// LED0: cfg PLL lock
// LED1: GT PLL lock
// LED2: channel_up
// LED3: test_pass
assign led_o[0]          = cfg_pll_lock;
assign led_o[1]          = gt_pll_ok;
assign led_o[2]          = channel_up_1d;
assign led_o[3]          = test_pass;

// 保持与官方参考 top 一致的关键骨架
assign sys_clk           = gt_pcs_tx_clk[0];

// 这一版不再通过寄存器软件控制 GT/PCS 复位，全部固定为 0
assign gt_reset          = 1'b0;
assign gt_pcs_tx_reset   = 1'b0;
assign gt_pcs_rx_reset   = 1'b0;

// 删除 reg_rst，直接使用官方参考思路的精简版
assign sys_reset_gen     = cfg_pll_lock & gt_pll_ok & resetn_i;

//==============================================================================
// 5) 配置时钟与复位生成
//==============================================================================
Gowin_PLL u_Gowin_PLL
(
    .reset      ( !resetn_i     ),
    .lock       ( cfg_pll_lock  ),
    .clkout0    ( cfg_clk       ),
    .clkin      ( osc_clk_i     ),
    .init_clk   (osc_clk_i)
);

reset_gen u1_reset_gen
(
    .i_clk1     ( cfg_clk       ),
    .i_lock     ( cfg_pll_lock  ),
    .o_rst1     ( cfg_rst       )
);

reset_gen u2_reset_gen
(
    .i_clk1     ( sys_clk       ),
    .i_lock     ( sys_reset_gen ),
    .o_rst1     ( sys_rst       )
);

//==============================================================================
// 6) 最小合法 Framing 发送器
//------------------------------------------------------------------------------
// 这版继续保持 Framing，因为官方参考工程这一套接口就是 Framing。
// 每 FRAME_BEATS 个 beat 构成一帧：
//   - user_tx_valid: 在 channel_up 后持续拉高
//   - user_tx_last : 每帧最后一个握手 beat 拉高
//   - user_tx_strb : 固定全有效
//==============================================================================
wire tx_active;
wire tx_fire;

assign tx_active     = channel_up_1d & (~sys_reset);
assign tx_fire       = user_tx_valid & user_tx_ready;

assign user_tx_valid = tx_active;
assign user_tx_data  = tx_counter;
assign user_tx_strb  = {STRB_WIDTH{1'b1}};
assign user_tx_last  = tx_active & (tx_beat_cnt == FRAME_BEATS-1);

always @(posedge sys_clk) begin
    if (sys_reset) begin
        tx_counter  <= 32'd0;
        tx_beat_cnt <= 8'd0;
    end
    else if (!channel_up_1d) begin
        tx_counter  <= 32'd0;
        tx_beat_cnt <= 8'd0;
    end
    else if (tx_fire) begin
        tx_counter <= tx_counter + 32'd1;

        if (tx_beat_cnt == FRAME_BEATS-1)
            tx_beat_cnt <= 8'd0;
        else
            tx_beat_cnt <= tx_beat_cnt + 8'd1;
    end
end

//==============================================================================
// 7) 最小 RX 观察逻辑
//------------------------------------------------------------------------------
// 这版不再关心“数据内容是否逐 beat 递增正确”，只关心：
//   1. 是否收到了有效数据
//   2. 是否收到了完整帧（user_rx_last）
//   3. IP 是否报告了 hard/soft/frame/crc error
//
// test_pass 条件：
//   - channel_up 已建立
//   - 见到过 user_rx_valid
//   - 见到过 user_rx_last
//   - 没有任何 IP 级错误
//==============================================================================
always @(posedge sys_clk) begin
    if (sys_reset) begin
        channel_up_1d      <= 1'b0;
        rx_seen_valid      <= 1'b0;
        rx_seen_last       <= 1'b0;
        rx_activity_toggle <= 1'b0;
        test_pass          <= 1'b0;

        hard_err_seen      <= 1'b0;
        soft_err_seen      <= 1'b0;
        frame_err_seen     <= 1'b0;
        crc_err_seen       <= 1'b0;
    end
    else begin
        channel_up_1d <= channel_up;

        if (!channel_up_1d) begin
            rx_seen_valid      <= 1'b0;
            rx_seen_last       <= 1'b0;
            rx_activity_toggle <= 1'b0;
            test_pass          <= 1'b0;

            hard_err_seen      <= 1'b0;
            soft_err_seen      <= 1'b0;
            frame_err_seen     <= 1'b0;
            crc_err_seen       <= 1'b0;
        end
        else begin
            if (user_rx_valid) begin
                rx_seen_valid      <= 1'b1;
                rx_activity_toggle <= ~rx_activity_toggle;
            end

            if (user_rx_valid && user_rx_last)
                rx_seen_last <= 1'b1;

            if (hard_err)
                hard_err_seen <= 1'b1;

            if (soft_err)
                soft_err_seen <= 1'b1;

            if (frame_err)
                frame_err_seen <= 1'b1;

            if (crc_valid && !crc_pass_fail_n)
                crc_err_seen <= 1'b1;

            if (channel_up_1d &&
                rx_seen_valid &&
                rx_seen_last &&
                !hard_err_seen &&
                !soft_err_seen &&
                !frame_err_seen &&
                !crc_err_seen) begin
                test_pass <= 1'b1;
            end
        end
    end
end

//==============================================================================
// 8) ILA 观测信号（统一 ila_ 前缀）
//==============================================================================

(* keep = "true" *) wire        ila_cfg_clk           = cfg_clk;
(* keep = "true" *) wire        ila_cfg_pll_lock      = cfg_pll_lock;
(* keep = "true" *) wire        ila_cfg_rst           = cfg_rst;

(* keep = "true" *) wire        ila_sys_clk           = sys_clk;
(* keep = "true" *) wire        ila_sys_reset_gen     = sys_reset_gen;
(* keep = "true" *) wire        ila_sys_rst           = sys_rst;
(* keep = "true" *) wire        ila_sys_reset         = sys_reset;
(* keep = "true" *) wire        ila_link_reset        = link_reset;

(* keep = "true" *) wire        ila_gt_reset          = gt_reset;
(* keep = "true" *) wire        ila_gt_pcs_tx_reset   = gt_pcs_tx_reset;
(* keep = "true" *) wire        ila_gt_pcs_rx_reset   = gt_pcs_rx_reset;
(* keep = "true" *) wire        ila_gt_pll_ok         = gt_pll_ok;

(* keep = "true" *) wire [LANE_WIDTH-1:0] ila_gt_pcs_tx_clk    = gt_pcs_tx_clk;
(* keep = "true" *) wire [LANE_WIDTH-1:0] ila_gt_pcs_rx_clk    = gt_pcs_rx_clk;
(* keep = "true" *) wire [LANE_WIDTH-1:0] ila_gt_rx_pma_lock   = gt_rx_pma_lock;
(* keep = "true" *) wire [LANE_WIDTH-1:0] ila_gt_rx_k_lock     = gt_rx_k_lock;
(* keep = "true" *) wire [LANE_WIDTH-1:0] ila_gt_rx_align_link = gt_rx_align_link;

(* keep = "true" *) wire        ila_channel_up        = channel_up;
(* keep = "true" *) wire [LANE_WIDTH-1:0] ila_lane_up = lane_up;
(* keep = "true" *) wire        ila_channel_up_1d     = channel_up_1d;

(* keep = "true" *) wire [DATA_WIDTH-1:0] ila_user_tx_data  = user_tx_data;
(* keep = "true" *) wire [STRB_WIDTH-1:0] ila_user_tx_strb  = user_tx_strb;
(* keep = "true" *) wire                  ila_user_tx_valid = user_tx_valid;
(* keep = "true" *) wire                  ila_user_tx_last  = user_tx_last;
(* keep = "true" *) wire                  ila_user_tx_ready = user_tx_ready;
(* keep = "true" *) wire                  ila_tx_fire       = tx_fire;
(* keep = "true" *) wire [7:0]            ila_tx_beat_cnt   = tx_beat_cnt;
(* keep = "true" *) wire [31:0]           ila_tx_counter    = tx_counter;

(* keep = "true" *) wire [DATA_WIDTH-1:0] ila_user_rx_data  = user_rx_data;
(* keep = "true" *) wire [STRB_WIDTH-1:0] ila_user_rx_strb  = user_rx_strb;
(* keep = "true" *) wire                  ila_user_rx_valid = user_rx_valid;
(* keep = "true" *) wire                  ila_user_rx_last  = user_rx_last;

(* keep = "true" *) wire                  ila_crc_valid       = crc_valid;
(* keep = "true" *) wire                  ila_crc_pass_fail_n = crc_pass_fail_n;
(* keep = "true" *) wire                  ila_hard_err        = hard_err;
(* keep = "true" *) wire                  ila_soft_err        = soft_err;
(* keep = "true" *) wire                  ila_frame_err       = frame_err;

(* keep = "true" *) wire                  ila_rx_seen_valid      = rx_seen_valid;
(* keep = "true" *) wire                  ila_rx_seen_last       = rx_seen_last;
(* keep = "true" *) wire                  ila_rx_activity_toggle = rx_activity_toggle;
(* keep = "true" *) wire                  ila_hard_err_seen      = hard_err_seen;
(* keep = "true" *) wire                  ila_soft_err_seen      = soft_err_seen;
(* keep = "true" *) wire                  ila_frame_err_seen     = frame_err_seen;
(* keep = "true" *) wire                  ila_crc_err_seen       = crc_err_seen;
(* keep = "true" *) wire                  ila_test_pass          = test_pass;

//==============================================================================
// 9) SerDes_Top 实例
//==============================================================================
SerDes_Top u_SerDes_Top
(
    // --------- Clock & Reset
    .RoraLink_8B10B_Top_reset_i               ( sys_rst            ),
    .RoraLink_8B10B_Top_user_clk_i            ( sys_clk            ),
    .RoraLink_8B10B_Top_init_clk_i            ( cfg_clk            ),
    .RoraLink_8B10B_Top_user_pll_locked_i     ( gt_pll_ok          ),

    .RoraLink_8B10B_Top_link_reset_o          ( link_reset         ),
    .RoraLink_8B10B_Top_sys_reset_o           ( sys_reset          ),

    // --------- user TX interface
    .RoraLink_8B10B_Top_user_tx_data_i        ( user_tx_data       ),
    .RoraLink_8B10B_Top_user_tx_valid_i       ( user_tx_valid      ),
    .RoraLink_8B10B_Top_user_tx_ready_o       ( user_tx_ready      ),
    .RoraLink_8B10B_Top_user_tx_strb_i        ( user_tx_strb       ),
    .RoraLink_8B10B_Top_user_tx_last_i        ( user_tx_last       ),

    // --------- user RX interface
    .RoraLink_8B10B_Top_user_rx_data_o        ( user_rx_data       ),
    .RoraLink_8B10B_Top_user_rx_valid_o       ( user_rx_valid      ),
    .RoraLink_8B10B_Top_user_rx_strb_o        ( user_rx_strb       ),
    .RoraLink_8B10B_Top_user_rx_last_o        ( user_rx_last       ),

    .RoraLink_8B10B_Top_crc_pass_fail_n_o     ( crc_pass_fail_n    ),
    .RoraLink_8B10B_Top_crc_valid_o           ( crc_valid          ),

    // --------- Status
    .RoraLink_8B10B_Top_hard_err_o            ( hard_err           ),
    .RoraLink_8B10B_Top_soft_err_o            ( soft_err           ),
    .RoraLink_8B10B_Top_frame_err_o           ( frame_err          ),

    .RoraLink_8B10B_Top_channel_up_o          ( channel_up         ),
    .RoraLink_8B10B_Top_lane_up_o             ( lane_up            ),

    // --------- SerDes
    .RoraLink_8B10B_Top_gt_pcs_tx_reset_i     ( gt_pcs_tx_reset    ),
    .RoraLink_8B10B_Top_gt_pcs_tx_clk_o       ( gt_pcs_tx_clk      ),

    .RoraLink_8B10B_Top_gt_pcs_rx_reset_i     ( gt_pcs_rx_reset    ),
    .RoraLink_8B10B_Top_gt_rx_align_link_o    ( gt_rx_align_link   ),
    .RoraLink_8B10B_Top_gt_rx_pma_lock_o      ( gt_rx_pma_lock     ),
    .RoraLink_8B10B_Top_gt_rx_k_lock_o        ( gt_rx_k_lock       ),
    .RoraLink_8B10B_Top_gt_pcs_rx_clk_o       ( gt_pcs_rx_clk      ),

    .RoraLink_8B10B_Top_gt_reset_i            ( gt_reset           ),
    .RoraLink_8B10B_Top_gt_pll_lock_o         ( gt_pll_ok          )
);

endmodule


//==============================================================================
// reset_gen
//==============================================================================
module reset_gen
(
    input           i_clk1,
    input           i_lock,
    output reg      o_rst1 = 1'b1
);

reg [11:0] r_cnt = 12'd0;

always @(posedge i_clk1) begin
    if (!i_lock) begin
        r_cnt  <= 12'd0;
        o_rst1 <= 1'b1;
    end
    else if (r_cnt < 12'hfff) begin
        r_cnt  <= r_cnt + 12'd1;
        o_rst1 <= 1'b1;
    end
    else begin
        o_rst1 <= 1'b0;
    end
end

endmodule