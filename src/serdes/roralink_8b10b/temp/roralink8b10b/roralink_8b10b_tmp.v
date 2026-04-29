//Copyright (C)2014-2026 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: Template file for instantiation
//Tool Version: V1.9.12.02_SP2 (64-bit)
//Part Number: GW5AST-LV138FPG676AC2/I1
//Device: GW5AST-138
//Device Version: B
//Created Time: Wed Apr 29 10:00:05 2026

//Change the instance name and port connections to the signal names
//--------Copy here to design--------

	RoraLink_8B10B_Top your_instance_name(
		.user_clk_i(user_clk_i), //input user_clk_i
		.init_clk_i(init_clk_i), //input init_clk_i
		.reset_i(reset_i), //input reset_i
		.user_pll_locked_i(user_pll_locked_i), //input user_pll_locked_i
		.sys_reset_o(sys_reset_o), //output sys_reset_o
		.user_tx_data_i(user_tx_data_i), //input [31:0] user_tx_data_i
		.user_tx_strb_i(user_tx_strb_i), //input [3:0] user_tx_strb_i
		.user_tx_valid_i(user_tx_valid_i), //input user_tx_valid_i
		.user_tx_last_i(user_tx_last_i), //input user_tx_last_i
		.user_tx_ready_o(user_tx_ready_o), //output user_tx_ready_o
		.hard_err_o(hard_err_o), //output hard_err_o
		.channel_up_o(channel_up_o), //output channel_up_o
		.lane_up_o(lane_up_o), //output [0:0] lane_up_o
		.gt_reset_i(gt_reset_i), //input gt_reset_i
		.gt_pcs_tx_reset_i(gt_pcs_tx_reset_i), //input gt_pcs_tx_reset_i
		.gt_pcs_tx_clk_o(gt_pcs_tx_clk_o), //output [0:0] gt_pcs_tx_clk_o
		.gt_pll_lock_o(gt_pll_lock_o), //output gt_pll_lock_o
		.serdes_pcs_tx_rst_o(serdes_pcs_tx_rst_o), //output [0:0] serdes_pcs_tx_rst_o
		.serdes_lanex_fabric_tx_clk_o(serdes_lanex_fabric_tx_clk_o), //output [0:0] serdes_lanex_fabric_tx_clk_o
		.serdes_lanex_tx_if_fifo_afull_i(serdes_lanex_tx_if_fifo_afull_i), //input [0:0] serdes_lanex_tx_if_fifo_afull_i
		.serdes_lnx_tx_vld_o(serdes_lnx_tx_vld_o), //output [0:0] serdes_lnx_tx_vld_o
		.serdes_lnx_txdata_o(serdes_lnx_txdata_o), //output [79:0] serdes_lnx_txdata_o
		.serdes_tx_if_fifo_wrusewd_i(serdes_tx_if_fifo_wrusewd_i), //input [4:0] serdes_tx_if_fifo_wrusewd_i
		.serdes_lnx_rstn_o(serdes_lnx_rstn_o), //output [0:0] serdes_lnx_rstn_o
		.serdes_lanex_pcs_tx_fabric_clk_i(serdes_lanex_pcs_tx_fabric_clk_i), //input [0:0] serdes_lanex_pcs_tx_fabric_clk_i
		.serdes_lanex_pcs_rx_fabric_clk_i(serdes_lanex_pcs_rx_fabric_clk_i), //input [0:0] serdes_lanex_pcs_rx_fabric_clk_i
		.serdes_q0_cmu1_ok_i(serdes_q0_cmu1_ok_i), //input serdes_q0_cmu1_ok_i
		.serdes_q0_cmu0_ok_i(serdes_q0_cmu0_ok_i), //input serdes_q0_cmu0_ok_i
		.serdes_q1_cmu1_ok_i(serdes_q1_cmu1_ok_i), //input serdes_q1_cmu1_ok_i
		.serdes_q1_cmu0_ok_i(serdes_q1_cmu0_ok_i), //input serdes_q1_cmu0_ok_i
		.serdes_lanex_cmu_ok_i(serdes_lanex_cmu_ok_i) //input [0:0] serdes_lanex_cmu_ok_i
	);

//--------Copy end-------------------
