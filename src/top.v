
`define LVDS_TX_CH 4

module top (
    input  wire                       clk,
    input  wire                       rst_n,

    output wire                       SFP_TX_DISABLE,
    output reg                        led
);

    //==========================================================================
    // 0) 纯 8b10b 最小链路版
    //    - 不再使用 LVDS 显示
    //    - 不再使用 FIFO
    //    - 仅保留 SerDes 发/收 + 自检测
    //==========================================================================

    localparam [7:0]  C_TX_HDR          = 8'h96;
    localparam [15:0] C_PASS_GOOD_WORDS = 16'd1024;
    localparam [23:0] C_RX_TIMEOUT_MAX  = 24'd12_500_000;


    assign   SFP_TX_DISABLE = 1'b0 ;

    //==========================================================================
    // 1) SerDes IP 接口
    //==========================================================================

    wire        user_tx_ready;
    wire [31:0] user_rx_data;
    wire        user_rx_valid;
    wire        hard_err;
    wire        soft_err;
    wire        channel_up;
    wire        lane_up;
    wire        gt_pcs_tx_clk;
    wire        gt_pcs_rx_clk;
    wire        gt_pll_ok;
    wire        gt_rx_align_link;
    wire        gt_rx_pma_lock;
    wire        gt_rx_k_lock;
    wire        link_reset_unused;
    wire        sys_reset_unused;

    wire        tx_clk;
    wire        rx_clk;

    reg  [23:0] tx_cnt;
    wire [31:0] user_tx_data;
    wire        user_tx_valid;

    assign tx_clk = gt_pcs_tx_clk;
    assign rx_clk = gt_pcs_rx_clk;

    assign user_tx_data  = {C_TX_HDR, tx_cnt};
    assign user_tx_valid = user_clk_ready;

    SerDes_Top u_SerDes_Top (
        .RoraLink_8B10B_Top_link_reset_o      (link_reset_unused),
        .RoraLink_8B10B_Top_sys_reset_o       (sys_reset_unused),
        .RoraLink_8B10B_Top_user_tx_ready_o   (user_tx_ready),
        .RoraLink_8B10B_Top_user_rx_data_o    (user_rx_data),
        .RoraLink_8B10B_Top_user_rx_valid_o   (user_rx_valid),
        .RoraLink_8B10B_Top_hard_err_o        (hard_err),
        .RoraLink_8B10B_Top_soft_err_o        (soft_err),
        .RoraLink_8B10B_Top_channel_up_o      (channel_up),
        .RoraLink_8B10B_Top_lane_up_o         (lane_up),
        .RoraLink_8B10B_Top_gt_pcs_tx_clk_o   (gt_pcs_tx_clk),
        .RoraLink_8B10B_Top_gt_pcs_rx_clk_o   (gt_pcs_rx_clk),
        .RoraLink_8B10B_Top_gt_pll_lock_o     (gt_pll_ok),
        .RoraLink_8B10B_Top_gt_rx_align_link_o(gt_rx_align_link),
        .RoraLink_8B10B_Top_gt_rx_pma_lock_o  (gt_rx_pma_lock),
        .RoraLink_8B10B_Top_gt_rx_k_lock_o    (gt_rx_k_lock),

        // 维持你工程当前的接法：user_clk_i 直接接 GT PCS TX 时钟
        .RoraLink_8B10B_Top_user_clk_i        (tx_clk),
        .RoraLink_8B10B_Top_init_clk_i        (clk),

        // 最小版先直接用顶层复位，避免再引入显示/FIFO 那套复位链
        .RoraLink_8B10B_Top_reset_i           (~rst_n),
        .RoraLink_8B10B_Top_user_pll_locked_i (gt_pll_ok),

        .RoraLink_8B10B_Top_user_tx_data_i    (user_tx_data),
        .RoraLink_8B10B_Top_user_tx_valid_i   (user_tx_valid),

        .RoraLink_8B10B_Top_gt_reset_i        (1'b0),
        .RoraLink_8B10B_Top_gt_pcs_tx_reset_i (1'b0),
        .RoraLink_8B10B_Top_gt_pcs_rx_reset_i (1'b0)
    );

    wire serdes_link_ok;
    assign serdes_link_ok =
        channel_up       &
        lane_up          &
        gt_pll_ok        &
        gt_rx_align_link &
        gt_rx_pma_lock   &
        gt_rx_k_lock;

    //==========================================================================
    // 2) user_clk(tx_clk) 域本地复位释放
    //    只用于本地 TX/checker 逻辑，不再拿去复位 SerDes IP
    //==========================================================================

    reg [3:0] user_rst_sync;

    always @(posedge tx_clk or negedge rst_n) begin
        if (!rst_n)
            user_rst_sync <= 4'b0000;
        else if (!gt_pll_ok)
            user_rst_sync <= 4'b0000;
        else
            user_rst_sync <= {user_rst_sync[2:0], 1'b1};
    end

    wire user_clk_ready;
    assign user_clk_ready = user_rst_sync[3];

    //==========================================================================
    // 3) TX：持续发送 0x96 + 24bit 递增计数
    //==========================================================================

    reg [31:0] tx_last_fire_data;
    reg        tx_seen_sticky;

    always @(posedge tx_clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_cnt            <= 24'd0;
            tx_last_fire_data <= 32'd0;
            tx_seen_sticky    <= 1'b0;
        end else if (!user_clk_ready) begin
            tx_cnt            <= 24'd0;
            tx_last_fire_data <= 32'd0;
            tx_seen_sticky    <= 1'b0;
        end else begin
            if (user_tx_valid && user_tx_ready) begin
                tx_last_fire_data <= {C_TX_HDR, tx_cnt};
                tx_cnt            <= tx_cnt + 24'd1;
                tx_seen_sticky    <= 1'b1;
            end
        end
    end

    wire tx_fire;
    assign tx_fire = user_tx_valid & user_tx_ready;

    //==========================================================================
    // 4) RX 自检测
    //    注意：这里统一放在 tx_clk/user_clk 域检查 user_rx_*，不再用 rx_clk 域
    //==========================================================================

    reg [31:0] rx_last_data;
    reg [23:0] rx_expected_cnt;
    reg        rx_seen_sticky;
    reg        rx_lock_sticky;
    reg        rx_match_pulse;
    reg        rx_mismatch_sticky;
    reg        rx_header_err_sticky;
    reg        hard_err_sticky;
    reg        soft_err_sticky;
    reg [15:0] rx_good_word_cnt;
    reg [23:0] rx_timeout_cnt;
    reg        timeout_sticky;
    reg        pass_sticky;
    reg        fail_sticky;

    always @(posedge tx_clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_last_data          <= 32'd0;
            rx_expected_cnt       <= 24'd0;
            rx_seen_sticky        <= 1'b0;
            rx_lock_sticky        <= 1'b0;
            rx_match_pulse        <= 1'b0;
            rx_mismatch_sticky    <= 1'b0;
            rx_header_err_sticky  <= 1'b0;
            hard_err_sticky       <= 1'b0;
            soft_err_sticky       <= 1'b0;
            rx_good_word_cnt      <= 16'd0;
            rx_timeout_cnt        <= 24'd0;
            timeout_sticky        <= 1'b0;
            pass_sticky           <= 1'b0;
            fail_sticky           <= 1'b0;
        end else if (!user_clk_ready) begin
            rx_last_data          <= 32'd0;
            rx_expected_cnt       <= 24'd0;
            rx_seen_sticky        <= 1'b0;
            rx_lock_sticky        <= 1'b0;
            rx_match_pulse        <= 1'b0;
            rx_mismatch_sticky    <= 1'b0;
            rx_header_err_sticky  <= 1'b0;
            hard_err_sticky       <= 1'b0;
            soft_err_sticky       <= 1'b0;
            rx_good_word_cnt      <= 16'd0;
            rx_timeout_cnt        <= 24'd0;
            timeout_sticky        <= 1'b0;
            pass_sticky           <= 1'b0;
            fail_sticky           <= 1'b0;
        end else begin
            rx_match_pulse <= 1'b0;

            if (hard_err) begin
                hard_err_sticky <= 1'b1;
                fail_sticky     <= 1'b1;
            end

            if (soft_err) begin
                soft_err_sticky <= 1'b1;
                fail_sticky     <= 1'b1;
            end

            // 链路已 up 但长时间没看到 RX 数据，记 timeout
            if (serdes_link_ok && !rx_seen_sticky) begin
                if (!timeout_sticky) begin
                    if (rx_timeout_cnt == C_RX_TIMEOUT_MAX) begin
                        timeout_sticky <= 1'b1;
                        fail_sticky    <= 1'b1;
                    end else begin
                        rx_timeout_cnt <= rx_timeout_cnt + 24'd1;
                    end
                end
            end else begin
                rx_timeout_cnt <= 24'd0;
            end

            if (user_rx_valid) begin
                rx_last_data   <= user_rx_data;
                rx_seen_sticky <= 1'b1;

                if (user_rx_data[31:24] != C_TX_HDR) begin
                    rx_header_err_sticky <= 1'b1;
                    rx_lock_sticky       <= 1'b0;
                    rx_good_word_cnt     <= 16'd0;
                    fail_sticky          <= 1'b1;
                end else begin
                    if (!rx_lock_sticky) begin
                        rx_lock_sticky   <= 1'b1;
                        rx_expected_cnt  <= user_rx_data[23:0] + 24'd1;
                        rx_good_word_cnt <= 16'd1;

                        if (C_PASS_GOOD_WORDS == 16'd1)
                            pass_sticky <= 1'b1;
                    end else begin
                        if (user_rx_data[23:0] == rx_expected_cnt) begin
                            rx_match_pulse  <= 1'b1;
                            rx_expected_cnt <= user_rx_data[23:0] + 24'd1;

                            if (rx_good_word_cnt < C_PASS_GOOD_WORDS)
                                rx_good_word_cnt <= rx_good_word_cnt + 16'd1;

                            if (rx_good_word_cnt == (C_PASS_GOOD_WORDS - 16'd1))
                                pass_sticky <= 1'b1;
                        end else begin
                            rx_mismatch_sticky <= 1'b1;
                            rx_expected_cnt    <= user_rx_data[23:0] + 24'd1;
                            rx_good_word_cnt   <= 16'd0;
                            fail_sticky        <= 1'b1;
                        end
                    end
                end
            end
        end
    end

    wire [31:0] rx_expected_data;
    assign rx_expected_data = {C_TX_HDR, rx_expected_cnt};

    //==========================================================================
    // 5) LED：放到 clk 域，做简单 CDC 同步
    //==========================================================================

    reg [1:0] gt_pll_ok_sync;
    reg [1:0] link_ok_sync;
    reg [1:0] rx_seen_sync;
    reg [1:0] pass_sync;
    reg [1:0] fail_sync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gt_pll_ok_sync <= 2'b00;
            link_ok_sync   <= 2'b00;
            rx_seen_sync   <= 2'b00;
            pass_sync      <= 2'b00;
            fail_sync      <= 2'b00;
        end else begin
            gt_pll_ok_sync <= {gt_pll_ok_sync[0], gt_pll_ok};
            link_ok_sync   <= {link_ok_sync[0],   serdes_link_ok};
            rx_seen_sync   <= {rx_seen_sync[0],   rx_seen_sticky};
            pass_sync      <= {pass_sync[0],      pass_sticky};
            fail_sync      <= {fail_sync[0],      fail_sticky};
        end
    end

    wire gt_pll_ok_clk;
    wire link_ok_clk;
    wire rx_seen_clk;
    wire pass_clk;
    wire fail_clk;

    assign gt_pll_ok_clk = gt_pll_ok_sync[1];
    assign link_ok_clk   = link_ok_sync[1];
    assign rx_seen_clk   = rx_seen_sync[1];
    assign pass_clk      = pass_sync[1];
    assign fail_clk      = fail_sync[1];

    reg [25:0] led_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            led_cnt <= 26'd0;
        else
            led_cnt <= led_cnt + 26'd1;
    end

    wire led_blink_slow;
    wire led_blink_fast;
    wire led_blink_mid;

    assign led_blink_slow = led_cnt[25];
    assign led_blink_mid  = led_cnt[24];
    assign led_blink_fast = led_cnt[23];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            led <= 1'b0;
        else if (!gt_pll_ok_clk)
            led <= 1'b0;
        else if (!link_ok_clk)
            led <= led_blink_slow;
        else if (fail_clk)
            led <= led_blink_fast;
        else if (pass_clk)
            led <= 1'b1;
        else if (!rx_seen_clk)
            led <= led_blink_mid;
        else
            led <= led_blink_mid;
    end

    //==========================================================================
    // 6) ILA 观察点
    //    推荐至少抓 ila1_ 这组，时钟用 ila1_clk = tx_clk
    //==========================================================================

    wire        ila1_clk                 = tx_clk;
    wire        ila1_user_clk_ready      = user_clk_ready;
    wire        ila1_gt_pll_ok           = gt_pll_ok;
    wire        ila1_channel_up          = channel_up;
    wire        ila1_lane_up             = lane_up;
    wire        ila1_gt_rx_align_link    = gt_rx_align_link;
    wire        ila1_gt_rx_pma_lock      = gt_rx_pma_lock;
    wire        ila1_gt_rx_k_lock        = gt_rx_k_lock;
    wire        ila1_serdes_link_ok      = serdes_link_ok;
    wire        ila1_hard_err            = hard_err;
    wire        ila1_soft_err            = soft_err;

    wire        ila1_user_tx_valid       = user_tx_valid;
    wire        ila1_user_tx_ready       = user_tx_ready;
    wire [31:0] ila1_user_tx_data        = user_tx_data;
    wire        ila1_tx_fire             = tx_fire;
    wire [23:0] ila1_tx_cnt              = tx_cnt;
    wire [31:0] ila1_tx_last_fire_data   = tx_last_fire_data;
    wire        ila1_tx_seen_sticky      = tx_seen_sticky;

    wire        ila1_user_rx_valid       = user_rx_valid;
    wire [31:0] ila1_user_rx_data        = user_rx_data;
    wire [31:0] ila1_rx_last_data        = rx_last_data;
    wire [31:0] ila1_rx_expected_data    = rx_expected_data;
    wire        ila1_rx_seen_sticky      = rx_seen_sticky;
    wire        ila1_rx_lock_sticky      = rx_lock_sticky;
    wire        ila1_rx_match_pulse      = rx_match_pulse;
    wire        ila1_rx_mismatch_sticky  = rx_mismatch_sticky;
    wire        ila1_rx_header_err_sticky= rx_header_err_sticky;
    wire        ila1_hard_err_sticky     = hard_err_sticky;
    wire        ila1_soft_err_sticky     = soft_err_sticky;
    wire [15:0] ila1_rx_good_word_cnt    = rx_good_word_cnt;
    wire [23:0] ila1_rx_timeout_cnt      = rx_timeout_cnt;
    wire        ila1_timeout_sticky      = timeout_sticky;
    wire        ila1_pass_sticky         = pass_sticky;
    wire        ila1_fail_sticky         = fail_sticky;

    wire        ila2_clk                 = clk;
    wire        ila2_gt_pll_ok_clk       = gt_pll_ok_clk;
    wire        ila2_link_ok_clk         = link_ok_clk;
    wire        ila2_rx_seen_clk         = rx_seen_clk;
    wire        ila2_pass_clk            = pass_clk;
    wire        ila2_fail_clk            = fail_clk;
    wire [25:0] ila2_led_cnt             = led_cnt;
    wire        ila2_led                 = led;
    wire        ila2_tx_clk              = tx_clk;
    wire        ila2_rx_clk              = rx_clk;

endmodule
