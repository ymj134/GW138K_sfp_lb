//Copyright (C)2014-2025 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: Template file for instantiation
//Tool Version: V1.9.12 (64-bit)
//Part Number: GW5AST-LV138FPG676AC2/I1
//Device: GW5AST-138
//Device Version: B
//Created Time: Wed Apr 15 15:52:10 2026

//Change the instance name and port connections to the signal names
//--------Copy here to design--------

    SerDes_Top your_instance_name(
        .RoraLink_8B10B_Top_link_reset_o(RoraLink_8B10B_Top_link_reset_o), //output RoraLink_8B10B_Top_link_reset_o
        .RoraLink_8B10B_Top_sys_reset_o(RoraLink_8B10B_Top_sys_reset_o), //output RoraLink_8B10B_Top_sys_reset_o
        .RoraLink_8B10B_Top_user_tx_ready_o(RoraLink_8B10B_Top_user_tx_ready_o), //output RoraLink_8B10B_Top_user_tx_ready_o
        .RoraLink_8B10B_Top_user_rx_data_o(RoraLink_8B10B_Top_user_rx_data_o), //output [31:0] RoraLink_8B10B_Top_user_rx_data_o
        .RoraLink_8B10B_Top_user_rx_valid_o(RoraLink_8B10B_Top_user_rx_valid_o), //output RoraLink_8B10B_Top_user_rx_valid_o
        .RoraLink_8B10B_Top_hard_err_o(RoraLink_8B10B_Top_hard_err_o), //output RoraLink_8B10B_Top_hard_err_o
        .RoraLink_8B10B_Top_soft_err_o(RoraLink_8B10B_Top_soft_err_o), //output RoraLink_8B10B_Top_soft_err_o
        .RoraLink_8B10B_Top_channel_up_o(RoraLink_8B10B_Top_channel_up_o), //output RoraLink_8B10B_Top_channel_up_o
        .RoraLink_8B10B_Top_lane_up_o(RoraLink_8B10B_Top_lane_up_o), //output RoraLink_8B10B_Top_lane_up_o
        .RoraLink_8B10B_Top_gt_pcs_tx_clk_o(RoraLink_8B10B_Top_gt_pcs_tx_clk_o), //output RoraLink_8B10B_Top_gt_pcs_tx_clk_o
        .RoraLink_8B10B_Top_gt_pcs_rx_clk_o(RoraLink_8B10B_Top_gt_pcs_rx_clk_o), //output RoraLink_8B10B_Top_gt_pcs_rx_clk_o
        .RoraLink_8B10B_Top_gt_pll_lock_o(RoraLink_8B10B_Top_gt_pll_lock_o), //output RoraLink_8B10B_Top_gt_pll_lock_o
        .RoraLink_8B10B_Top_gt_rx_align_link_o(RoraLink_8B10B_Top_gt_rx_align_link_o), //output RoraLink_8B10B_Top_gt_rx_align_link_o
        .RoraLink_8B10B_Top_gt_rx_pma_lock_o(RoraLink_8B10B_Top_gt_rx_pma_lock_o), //output RoraLink_8B10B_Top_gt_rx_pma_lock_o
        .RoraLink_8B10B_Top_gt_rx_k_lock_o(RoraLink_8B10B_Top_gt_rx_k_lock_o), //output RoraLink_8B10B_Top_gt_rx_k_lock_o
        .RoraLink_8B10B_Top_user_clk_i(RoraLink_8B10B_Top_user_clk_i), //input RoraLink_8B10B_Top_user_clk_i
        .RoraLink_8B10B_Top_init_clk_i(RoraLink_8B10B_Top_init_clk_i), //input RoraLink_8B10B_Top_init_clk_i
        .RoraLink_8B10B_Top_reset_i(RoraLink_8B10B_Top_reset_i), //input RoraLink_8B10B_Top_reset_i
        .RoraLink_8B10B_Top_user_pll_locked_i(RoraLink_8B10B_Top_user_pll_locked_i), //input RoraLink_8B10B_Top_user_pll_locked_i
        .RoraLink_8B10B_Top_user_tx_data_i(RoraLink_8B10B_Top_user_tx_data_i), //input [31:0] RoraLink_8B10B_Top_user_tx_data_i
        .RoraLink_8B10B_Top_user_tx_valid_i(RoraLink_8B10B_Top_user_tx_valid_i), //input RoraLink_8B10B_Top_user_tx_valid_i
        .RoraLink_8B10B_Top_gt_reset_i(RoraLink_8B10B_Top_gt_reset_i), //input RoraLink_8B10B_Top_gt_reset_i
        .RoraLink_8B10B_Top_gt_pcs_tx_reset_i(RoraLink_8B10B_Top_gt_pcs_tx_reset_i), //input RoraLink_8B10B_Top_gt_pcs_tx_reset_i
        .RoraLink_8B10B_Top_gt_pcs_rx_reset_i(RoraLink_8B10B_Top_gt_pcs_rx_reset_i) //input RoraLink_8B10B_Top_gt_pcs_rx_reset_i
    );

//--------Copy end-------------------
