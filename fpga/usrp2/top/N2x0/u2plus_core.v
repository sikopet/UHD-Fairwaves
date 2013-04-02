//
// Copyright 2011 Ettus Research LLC
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

// ////////////////////////////////////////////////////////////////////////////////
// Module Name:    u2_core
// ////////////////////////////////////////////////////////////////////////////////

module u2plus_core
  (// Clocks
   input dsp_clk,
`ifdef LMS602D_FRONTEND
   input lms_clk,
`endif // !`ifdef LMS602D_FRONTEND
   input wb_clk,
   input clk_icap, //ICAP timing fixes for UmTRX Spartan-6 FPGA.
   output clock_ready,
   input clk_to_mac,
   input pps_in,
   
   // Misc, debug
   output [7:0] leds,
   output [31:0] debug,
   output [1:0] debug_clk,

   // Expansion
   input exp_time_in,
   output exp_time_out,
   
   // GMII
   //   GMII-CTRL
   input GMII_COL,
   input GMII_CRS,

   //   GMII-TX
   output [7:0] GMII_TXD,
   output GMII_TX_EN,
   output GMII_TX_ER,
   output GMII_GTX_CLK,
   input GMII_TX_CLK,  // 100mbps clk

   //   GMII-RX
   input [7:0] GMII_RXD,
   input GMII_RX_CLK,
   input GMII_RX_DV,
   input GMII_RX_ER,

   //   GMII-Management
   inout MDIO,
   output MDC,
   input PHY_INTn,   // open drain
   output PHY_RESETn,

   // SERDES
   output ser_enable,
   output ser_prbsen,
   output ser_loopen,
   output ser_rx_en,
   
   output ser_tx_clk,
   output [15:0] ser_t,
   output ser_tklsb,
   output ser_tkmsb,

   input ser_rx_clk,
   input [15:0] ser_r,
   input ser_rklsb,
   input ser_rkmsb,
   
   input por,
   output config_success,
   
`ifndef LMS602D_FRONTEND
   // ADC
   input [13:0] adc_a,
   input adc_ovf_a,
   output adc_on_a,
   output adc_oe_a,
   
   input [13:0] adc_b,
   input adc_ovf_b,
   output adc_on_b,
   output adc_oe_b,
`else
   // ADC 0
   input [13:0] adc_a_0,
   input adc_ovf_a_0,
   output adc_on_a_0,
   output adc_oe_a_0,

   input [13:0] adc_b_0,
   input adc_ovf_b_0,
   output adc_on_b_0,
   output adc_oe_b_0,
   // ADC 1
   input [13:0] adc_a_1,
   input adc_ovf_a_1,
   output adc_on_a_1,
   output adc_oe_a_1,

   input [13:0] adc_b_1,
   input adc_ovf_b_1,
   output adc_on_b_1,
   output adc_oe_b_1,
   output [1:0] lms_res,
`endif // !`ifndef LMS602D_FRONTEND
   
   // DAC
   output [15:0] dac_a,
   output [15:0] dac_b,
`ifdef LMS602D_FRONTEND
   output [11:0] dac1_a,
   output [11:0] dac1_b,
`endif // !`ifdef LMS602D_FRONTEND


   // I2C
   input scl_pad_i,
   output scl_pad_o,
   output scl_pad_oen_o,
   input sda_pad_i,
   output sda_pad_o,
   output sda_pad_oen_o,
   
   // Clock Gen Control
   output [1:0] clk_en,
   output [1:0] clk_sel,
   input clk_func,        // FIXME is an input to control the 9510
   input clk_status,

   // Generic SPI
   output sclk,
   output mosi,
   input miso,
`ifndef UMTRX
   output sen_clk,
   output sen_dac,
   output sen_adc,
   output sen_tx_db,
   output sen_tx_adc,
   output sen_tx_dac,
   output sen_rx_db,
   output sen_rx_adc,
   output sen_rx_dac,
`else
   output sen_dac,
   output sen_lms1,
   output sen_lms2,
   //Diversity switches
   output DivSw1,
   output DivSw2,
   input aux_scl_pad_i,
   output aux_scl_pad_o,
   output aux_scl_pad_oen_o,
   input aux_sda_pad_i,
   output aux_sda_pad_o,
   output aux_sda_pad_oen_o,
   //AUX SPI
   output aux_sdat,
   output aux_sclk,
   output aux_sen1,
   output aux_sen2,
   input aux_ld1,
   input aux_ld2, 
`endif // !`ifndef UMTRX
   
   // GPIO to DBoards
   inout [15:0] io_tx,
   inout [15:0] io_rx,

`ifndef NO_EXT_FIFO
   // External RAM
   input [35:0] RAM_D_pi,
   output [35:0] RAM_D_po,
   output RAM_D_poe,
   output [20:0] RAM_A,
   output RAM_CE1n,
   output RAM_CENn,
   output RAM_WEn,
   output RAM_OEn,
   output RAM_LDn,
`endif // !`ifndef NO_EXT_FIFO
   
   // Debug stuff
   output [3:0] uart_tx_o, 
   input [3:0] uart_rx_i,
   output [3:0] uart_baud_o,
   input sim_mode,
   input [3:0] clock_divider,
   input button,
   
   output spiflash_cs, output spiflash_clk, input spiflash_miso, output spiflash_mosi
   );

   localparam SR_MISC     =   0;   // 7 regs
   localparam SR_SIMTIMER =   8;   // 2
   localparam SR_TIME64   =  10;   // 6
   localparam SR_BUF_POOL =  16;   // 4

`ifndef LMS602D_FRONTEND
   localparam SR_RX_FRONT =  24;   // 5
`else
   localparam SR_RX_FRONT0 =  20;   // 5
   localparam SR_RX_FRONT1 =  25;   // 5
`endif // !`ifndef LMS602D_FRONTEND
   localparam SR_RX_CTRL0 =  32;   // 9
   localparam SR_RX_DSP0  =  48;   // 7
   localparam SR_RX_CTRL1 =  80;   // 9
   localparam SR_RX_DSP1  =  96;   // 7

`ifndef LMS602D_FRONTEND
   localparam SR_TX_FRONT = 128;   // ?
   localparam SR_TX_CTRL  = 144;   // 6
   localparam SR_TX_DSP   = 160;   // 5
`else
   localparam SR_TX_FRONT = 110;   // ?
   localparam SR_TX_CTRL  = 126;   // 6
   localparam SR_TX_DSP   = 135;   // 5
   localparam SR_TX1_FRONT = 145;   // ?
   localparam SR_TX1_CTRL  = 161;   // 6
   localparam SR_TX1_DSP   = 170;   // 5
   localparam SR_RX_FRONT_SW = 176;
   localparam SR_TX_FRONT_SW = 177;
`endif // !`ifndef LMS602D_FRONTEND

   localparam SR_DIVSW    = 180;   // 2
   localparam SR_GPIO     = 184;   // 5   
   localparam SR_UDP_SM   = 192;   // 64
   
   // FIFO Sizes, 9 = 512 lines, 10 = 1024, 11 = 2048
   // all (most?) are 36 bits wide, so 9 is 1 BRAM, 10 is 2, 11 is 4 BRAMs
   // localparam DSP_TX_FIFOSIZE = 9;  unused -- DSPTX uses extram fifo
   localparam DSP_RX_FIFOSIZE = 10;
   localparam ETH_TX_FIFOSIZE = 9;
   localparam ETH_RX_FIFOSIZE = 11;
   localparam SERDES_TX_FIFOSIZE = 9;
   localparam SERDES_RX_FIFOSIZE = 9;  // RX currently doesn't use a fifo?
   
   wire [7:0] 	set_addr, set_addr_dsp;
   wire [31:0] 	set_data, set_data_dsp;
   wire 	set_stb, set_stb_dsp;
   
   reg 		wb_rst; 
   wire 	dsp_rst = wb_rst;
   
   wire [31:0] 	status;
   wire 	bus_error, spi_int, i2c_int, aux_i2c_int, pps_int, onetime_int, periodic_int, buffer_int;
   wire 	proc_int, overrun0, overrun1, underrun;
`ifdef LMS602D_FRONTEND
   wire 	 underrun1;
`endif // !`ifdef LMS602D_FRONTEND
   wire [3:0] 	uart_tx_int, uart_rx_int;

   wire [31:0] 	debug_gpio_0, debug_gpio_1;

   wire [31:0] 	debug_rx, debug_mac, debug_mac0, debug_mac1, debug_tx_dsp, debug_txc,
		debug_serdes0, debug_serdes1, debug_serdes2, debug_rx_dsp, debug_udp, debug_extfifo, debug_extfifo2;

   wire [15:0] 	ser_rx_occ, ser_tx_occ, dsp_rx_occ, dsp_tx_occ, eth_rx_occ, eth_tx_occ, eth_rx_occ2;
   wire 	ser_rx_full, ser_tx_full, dsp_rx_full, dsp_tx_full, eth_rx_full, eth_tx_full, eth_rx_full2;
   wire 	ser_rx_empty, ser_tx_empty, dsp_rx_empty, dsp_tx_empty, eth_rx_empty, eth_tx_empty, eth_rx_empty2;
	
   wire 	serdes_link_up, good_sync;
   wire 	epoch;
   wire [31:0] 	irq;
   wire [63:0] 	vita_time, vita_time_pps;
   
   wire 	 run_rx0, run_rx1, run_tx;
`ifdef LMS602D_FRONTEND
   wire 	 run_tx1;
   wire   run_tx0_mux, run_tx1_mux;
`endif // !`ifdef LMS602D_FRONTEND
   reg 		 run_rx0_d1, run_rx1_d1;
   
   // ///////////////////////////////////////////////////////////////////////////////////////////////
   // Wishbone Single Master INTERCON
   localparam 	dw = 32;  // Data bus width
   localparam 	aw = 16;  // Address bus width, for byte addressibility, 16 = 64K byte memory space
   localparam	sw = 4;   // Select width -- 32-bit data bus with 8-bit granularity.  
   
   wire [dw-1:0] m0_dat_o, m0_dat_i;
   wire [dw-1:0] s0_dat_o, s1_dat_o, s0_dat_i, s1_dat_i, s2_dat_o, s3_dat_o, s2_dat_i, s3_dat_i,
		 s4_dat_o, s5_dat_o, s4_dat_i, s5_dat_i, s6_dat_o, s7_dat_o, s6_dat_i, s7_dat_i,
		 s8_dat_o, s9_dat_o, s8_dat_i, s9_dat_i, sa_dat_o, sa_dat_i, sb_dat_i, sb_dat_o,
		 sc_dat_i, sc_dat_o, sd_dat_i, sd_dat_o, se_dat_i, se_dat_o, sf_dat_i, sf_dat_o;
   wire [aw-1:0] m0_adr,s0_adr,s1_adr,s2_adr,s3_adr,s4_adr,s5_adr,s6_adr,s7_adr,s8_adr,s9_adr,sa_adr,sb_adr,sc_adr, sd_adr, se_adr, sf_adr;
   wire [sw-1:0] m0_sel,s0_sel,s1_sel,s2_sel,s3_sel,s4_sel,s5_sel,s6_sel,s7_sel,s8_sel,s9_sel,sa_sel,sb_sel,sc_sel, sd_sel, se_sel, sf_sel;
   wire 	 m0_ack,s0_ack,s1_ack,s2_ack,s3_ack,s4_ack,s5_ack,s6_ack,s7_ack,s8_ack,s9_ack,sa_ack,sb_ack,sc_ack, sd_ack, se_ack, sf_ack;
   wire 	 m0_stb,s0_stb,s1_stb,s2_stb,s3_stb,s4_stb,s5_stb,s6_stb,s7_stb,s8_stb,s9_stb,sa_stb,sb_stb,sc_stb, sd_stb, se_stb, sf_stb;
   wire 	 m0_cyc,s0_cyc,s1_cyc,s2_cyc,s3_cyc,s4_cyc,s5_cyc,s6_cyc,s7_cyc,s8_cyc,s9_cyc,sa_cyc,sb_cyc,sc_cyc, sd_cyc, se_cyc, sf_cyc;
   wire 	 m0_err, m0_rty;
   wire 	 m0_we,s0_we,s1_we,s2_we,s3_we,s4_we,s5_we,s6_we,s7_we,s8_we,s9_we,sa_we,sb_we,sc_we,sd_we,se_we,sf_we;
   
   wb_1master #(.decode_w(8),
		.s0_addr(8'b0000_0000),.s0_mask(8'b1100_0000),  // Main RAM (0-16K)
		.s1_addr(8'b0100_0000),.s1_mask(8'b1111_0000),  // Packet Router (16-20K)
 		.s2_addr(8'b0101_0000),.s2_mask(8'b1111_1100),  // SPI
		.s3_addr(8'b0101_0100),.s3_mask(8'b1111_1100),  // I2C
		.s4_addr(8'b0101_1000),.s4_mask(8'b1111_1100),  // GPSDO
		.s5_addr(8'b0101_1100),.s5_mask(8'b1111_1100),  // Readback
		.s6_addr(8'b0110_0000),.s6_mask(8'b1111_0000),  // Ethernet MAC
		.s7_addr(8'b0111_0000),.s7_mask(8'b1111_0000),  // Settings Bus (only uses 1K)
		.s8_addr(8'b1000_0000),.s8_mask(8'b1111_1100),  // PIC
		.s9_addr(8'b1000_0100),.s9_mask(8'b1111_1100),  // I2C AUX
		.sa_addr(8'b1000_1000),.sa_mask(8'b1111_1100),  // UART
		.sb_addr(8'b1000_1100),.sb_mask(8'b1111_1100),  // Unused
		.sc_addr(8'b1001_0000),.sc_mask(8'b1111_0000),  // Unused
		.sd_addr(8'b1010_0000),.sd_mask(8'b1111_0000),  // ICAP
		.se_addr(8'b1011_0000),.se_mask(8'b1111_0000),  // SPI Flash
		.sf_addr(8'b1100_0000),.sf_mask(8'b1100_0000),  // 48K-64K, Boot RAM
		.dw(dw),.aw(aw),.sw(sw)) wb_1master
     (.clk_i(wb_clk),.rst_i(wb_rst),       
      .m0_dat_o(m0_dat_o),.m0_ack_o(m0_ack),.m0_err_o(m0_err),.m0_rty_o(m0_rty),.m0_dat_i(m0_dat_i),
      .m0_adr_i(m0_adr),.m0_sel_i(m0_sel),.m0_we_i(m0_we),.m0_cyc_i(m0_cyc),.m0_stb_i(m0_stb),
      .s0_dat_o(s0_dat_o),.s0_adr_o(s0_adr),.s0_sel_o(s0_sel),.s0_we_o	(s0_we),.s0_cyc_o(s0_cyc),.s0_stb_o(s0_stb),
      .s0_dat_i(s0_dat_i),.s0_ack_i(s0_ack),.s0_err_i(0),.s0_rty_i(0),
      .s1_dat_o(s1_dat_o),.s1_adr_o(s1_adr),.s1_sel_o(s1_sel),.s1_we_o	(s1_we),.s1_cyc_o(s1_cyc),.s1_stb_o(s1_stb),
      .s1_dat_i(s1_dat_i),.s1_ack_i(s1_ack),.s1_err_i(0),.s1_rty_i(0),
      .s2_dat_o(s2_dat_o),.s2_adr_o(s2_adr),.s2_sel_o(s2_sel),.s2_we_o	(s2_we),.s2_cyc_o(s2_cyc),.s2_stb_o(s2_stb),
      .s2_dat_i(s2_dat_i),.s2_ack_i(s2_ack),.s2_err_i(0),.s2_rty_i(0),
      .s3_dat_o(s3_dat_o),.s3_adr_o(s3_adr),.s3_sel_o(s3_sel),.s3_we_o	(s3_we),.s3_cyc_o(s3_cyc),.s3_stb_o(s3_stb),
      .s3_dat_i(s3_dat_i),.s3_ack_i(s3_ack),.s3_err_i(0),.s3_rty_i(0),
      .s4_dat_o(s4_dat_o),.s4_adr_o(s4_adr),.s4_sel_o(s4_sel),.s4_we_o	(s4_we),.s4_cyc_o(s4_cyc),.s4_stb_o(s4_stb),
      .s4_dat_i(s4_dat_i),.s4_ack_i(s4_ack),.s4_err_i(0),.s4_rty_i(0),
      .s5_dat_o(s5_dat_o),.s5_adr_o(s5_adr),.s5_sel_o(s5_sel),.s5_we_o	(s5_we),.s5_cyc_o(s5_cyc),.s5_stb_o(s5_stb),
      .s5_dat_i(s5_dat_i),.s5_ack_i(s5_ack),.s5_err_i(0),.s5_rty_i(0),
      .s6_dat_o(s6_dat_o),.s6_adr_o(s6_adr),.s6_sel_o(s6_sel),.s6_we_o	(s6_we),.s6_cyc_o(s6_cyc),.s6_stb_o(s6_stb),
      .s6_dat_i(s6_dat_i),.s6_ack_i(s6_ack),.s6_err_i(0),.s6_rty_i(0),
      .s7_dat_o(s7_dat_o),.s7_adr_o(s7_adr),.s7_sel_o(s7_sel),.s7_we_o	(s7_we),.s7_cyc_o(s7_cyc),.s7_stb_o(s7_stb),
      .s7_dat_i(s7_dat_i),.s7_ack_i(s7_ack),.s7_err_i(0),.s7_rty_i(0),
      .s8_dat_o(s8_dat_o),.s8_adr_o(s8_adr),.s8_sel_o(s8_sel),.s8_we_o	(s8_we),.s8_cyc_o(s8_cyc),.s8_stb_o(s8_stb),
      .s8_dat_i(s8_dat_i),.s8_ack_i(s8_ack),.s8_err_i(0),.s8_rty_i(0),
      .s9_dat_o(s9_dat_o),.s9_adr_o(s9_adr),.s9_sel_o(s9_sel),.s9_we_o	(s9_we),.s9_cyc_o(s9_cyc),.s9_stb_o(s9_stb),
      .s9_dat_i(s9_dat_i),.s9_ack_i(s9_ack),.s9_err_i(0),.s9_rty_i(0),
      .sa_dat_o(sa_dat_o),.sa_adr_o(sa_adr),.sa_sel_o(sa_sel),.sa_we_o(sa_we),.sa_cyc_o(sa_cyc),.sa_stb_o(sa_stb),
      .sa_dat_i(sa_dat_i),.sa_ack_i(sa_ack),.sa_err_i(0),.sa_rty_i(0),
      .sb_dat_o(sb_dat_o),.sb_adr_o(sb_adr),.sb_sel_o(sb_sel),.sb_we_o(sb_we),.sb_cyc_o(sb_cyc),.sb_stb_o(sb_stb),
      .sb_dat_i(sb_dat_i),.sb_ack_i(sb_ack),.sb_err_i(0),.sb_rty_i(0),
      .sc_dat_o(sc_dat_o),.sc_adr_o(sc_adr),.sc_sel_o(sc_sel),.sc_we_o(sc_we),.sc_cyc_o(sc_cyc),.sc_stb_o(sc_stb),
      .sc_dat_i(sc_dat_i),.sc_ack_i(sc_ack),.sc_err_i(0),.sc_rty_i(0),
      .sd_dat_o(sd_dat_o),.sd_adr_o(sd_adr),.sd_sel_o(sd_sel),.sd_we_o(sd_we),.sd_cyc_o(sd_cyc),.sd_stb_o(sd_stb),
      .sd_dat_i(sd_dat_i),.sd_ack_i(sd_ack),.sd_err_i(0),.sd_rty_i(0),
      .se_dat_o(se_dat_o),.se_adr_o(se_adr),.se_sel_o(se_sel),.se_we_o(se_we),.se_cyc_o(se_cyc),.se_stb_o(se_stb),
      .se_dat_i(se_dat_i),.se_ack_i(se_ack),.se_err_i(0),.se_rty_i(0),
      .sf_dat_o(sf_dat_o),.sf_adr_o(sf_adr),.sf_sel_o(sf_sel),.sf_we_o(sf_we),.sf_cyc_o(sf_cyc),.sf_stb_o(sf_stb),
      .sf_dat_i(sf_dat_i),.sf_ack_i(sf_ack),.sf_err_i(0),.sf_rty_i(0));

   // Unused Slaves b, c
   assign sb_ack = 0;   assign sc_ack = 0;
   
   // ////////////////////////////////////////////////////////////////////////////////////////
   // Reset Controller

   reg 		 cpu_bldr_ctrl_state;
   localparam CPU_BLDR_CTRL_WAIT = 0;
   localparam CPU_BLDR_CTRL_DONE = 1;
   
   wire 	 bldr_done;
   wire 	 por_rst;
   wire [aw-1:0] cpu_adr;

   // Swap boot ram and main ram when in bootloader mode
   assign m0_adr = (^cpu_adr[15:14] | (cpu_bldr_ctrl_state == CPU_BLDR_CTRL_DONE)) ? cpu_adr :
		   cpu_adr ^ 16'hC000;
   
   system_control sysctrl 
     (.wb_clk_i(wb_clk), .wb_rst_o(por_rst), .ram_loader_done_i(1'b1) );
   
   always @(posedge wb_clk)
     if(por_rst) begin
        cpu_bldr_ctrl_state <= CPU_BLDR_CTRL_WAIT;
        wb_rst <= 1'b1;
     end
     else begin
        case(cpu_bldr_ctrl_state)
	  
          CPU_BLDR_CTRL_WAIT: begin
             wb_rst <= 1'b0;
             if (bldr_done == 1'b1) begin //set by the bootloader
                cpu_bldr_ctrl_state <= CPU_BLDR_CTRL_DONE;
                wb_rst <= 1'b1;
             end
          end
	  
          CPU_BLDR_CTRL_DONE: begin //stay here forever
             wb_rst <= 1'b0;
          end
	  
        endcase //cpu_bldr_ctrl_state
     end
   
   // /////////////////////////////////////////////////////////////////////////
   // Processor

   assign 	 bus_error = m0_err | m0_rty;

   wire [63:0] zpu_status;
   zpu_wb_top #(.dat_w(dw), .adr_w(aw), .sel_w(sw))
     zpu_top0 (.clk(wb_clk), .rst(wb_rst), .enb(~wb_rst),
	   // Data Wishbone bus to system bus fabric
	   .we_o(m0_we),.stb_o(m0_stb),.dat_o(m0_dat_i),.adr_o(cpu_adr),
	   .dat_i(m0_dat_o),.ack_i(m0_ack),.sel_o(m0_sel),.cyc_o(m0_cyc),
	   // Interrupts and exceptions
	   .zpu_status(zpu_status), .interrupt(proc_int & 1'b0));
   
   // /////////////////////////////////////////////////////////////////////////
   // Dual Ported Boot RAM -- D-Port is Slave #0 on main Wishbone
   // Dual Ported Main RAM -- D-Port is Slave #F on main Wishbone
   // I-port connects directly to processor

   bootram bootram(.clk(wb_clk), .reset(wb_rst),
		   .if_adr(14'b0), .if_data(),
		   .dwb_adr_i(sf_adr[13:0]), .dwb_dat_i(sf_dat_o), .dwb_dat_o(sf_dat_i),
		   .dwb_we_i(sf_we), .dwb_ack_o(sf_ack), .dwb_stb_i(sf_stb), .dwb_sel_i(sf_sel));

////blinkenlights v0.1
//defparam bootram.RAM0.INIT_00=256'hbc32fff0_aa43502b_b00000fe_30630001_80000000_10600000_a48500ff_10a00000;
//defparam bootram.RAM0.INIT_01=256'ha48500ff_b810ffd0_f880200c_30a50001_10830000_308000ff_be23000c_a4640001;

`ifndef UMTRX
`include "bootloader.rmi"
`else
`include "bootloader_umtrx.rmi"
`endif // !`ifndef UMTRX

   ram_harvard2 #(.AWIDTH(14),.RAM_SIZE(16384))
   sys_ram(.wb_clk_i(wb_clk),.wb_rst_i(wb_rst),	     
	   .if_adr(14'b0), .if_data(),
	   .dwb_adr_i(s0_adr[13:0]), .dwb_dat_i(s0_dat_o), .dwb_dat_o(s0_dat_i),
	   .dwb_we_i(s0_we), .dwb_ack_o(s0_ack), .dwb_stb_i(s0_stb), .dwb_sel_i(s0_sel));
   
   // /////////////////////////////////////////////////////////////////////////
   // Buffer Pool, slave #1
   wire 	 rd0_ready_i, rd0_ready_o;
   wire 	 rd1_ready_i, rd1_ready_o;
`ifdef LMS602D_FRONTEND
   wire 	 rd1_ready_i_1, rd1_ready_o_1;
`endif // !`ifdef LMS602D_FRONTEND
   wire 	 rd2_ready_i, rd2_ready_o;
   wire 	 rd3_ready_i, rd3_ready_o;
   wire [35:0] 	 rd0_dat, rd1_dat, rd2_dat, rd3_dat;

   wire 	 wr0_ready_i, wr0_ready_o;
   wire 	 wr1_ready_i, wr1_ready_o;
   wire 	 wr2_ready_i, wr2_ready_o;
   wire 	 wr3_ready_i, wr3_ready_o;
   wire [35:0] 	 wr0_dat, wr1_dat, wr2_dat, wr3_dat;

   wire [35:0] 	 tx_err_data;
   wire 	 tx_err_src_rdy, tx_err_dst_rdy;
`ifdef LMS602D_FRONTEND
   wire [35:0] 	 tx1_err_data;
   wire 	 tx1_err_src_rdy, tx1_err_dst_rdy;
`endif // !`ifdef LMS602D_FRONTEND

   wire [31:0] router_debug;

   packet_router #(.BUF_SIZE(9), .UDP_BASE(SR_UDP_SM), .CTRL_BASE(SR_BUF_POOL)) packet_router
     (.wb_clk_i(wb_clk),.wb_rst_i(wb_rst),
      .wb_we_i(s1_we),.wb_stb_i(s1_stb),.wb_adr_i(s1_adr),.wb_dat_i(s1_dat_o),
      .wb_dat_o(s1_dat_i),.wb_ack_o(s1_ack),.wb_err_o(),.wb_rty_o(),

      .set_stb(set_stb_dsp), .set_addr(set_addr_dsp), .set_data(set_data_dsp),

      .stream_clk(dsp_clk), .stream_rst(dsp_rst), .stream_clr(1'b0),

      .status(status), .sys_int_o(buffer_int), .debug(router_debug),

      .ser_inp_data(wr0_dat), .ser_inp_valid(wr0_ready_i), .ser_inp_ready(wr0_ready_o),
      .dsp0_inp_data(wr1_dat), .dsp0_inp_valid(wr1_ready_i), .dsp0_inp_ready(wr1_ready_o),
      .dsp1_inp_data(wr3_dat), .dsp1_inp_valid(wr3_ready_i), .dsp1_inp_ready(wr3_ready_o),
      .eth_inp_data(wr2_dat), .eth_inp_valid(wr2_ready_i), .eth_inp_ready(wr2_ready_o),
      .err_inp_data(tx_err_data), .err_inp_ready(tx_err_dst_rdy), .err_inp_valid(tx_err_src_rdy),

      .ser_out_data(rd0_dat), .ser_out_valid(rd0_ready_o), .ser_out_ready(rd0_ready_i),
      .dsp_out_data(rd1_dat), .dsp_out_valid(rd1_ready_o), .dsp_out_ready(rd1_ready_i),
`ifdef LMS602D_FRONTEND
      .dsp1_out_valid(rd1_ready_o_1), .dsp1_out_ready(rd1_ready_i_1),
      .err_inp1_data(tx1_err_data), .err_inp1_ready(tx1_err_dst_rdy), .err_inp1_valid(tx1_err_src_rdy),
`endif // !`ifdef LMS602D_FRONTEND
      .eth_out_data(rd2_dat), .eth_out_valid(rd2_ready_o), .eth_out_ready(rd2_ready_i)
      );

   // /////////////////////////////////////////////////////////////////////////
   // SPI -- Slave #2
   spi_top shared_spi
     (.wb_clk_i(wb_clk),.wb_rst_i(wb_rst),.wb_adr_i(s2_adr[4:0]),.wb_dat_i(s2_dat_o),
      .wb_dat_o(s2_dat_i),.wb_sel_i(s2_sel),.wb_we_i(s2_we),.wb_stb_i(s2_stb),
      .wb_cyc_i(s2_cyc),.wb_ack_o(s2_ack),.wb_err_o(),.wb_int_o(spi_int),
`ifndef UMTRX
      .ss_pad_o({sen_adc, sen_tx_db,sen_tx_adc,sen_tx_dac,sen_rx_db,sen_rx_adc,sen_rx_dac,sen_dac,sen_clk}),
`else
      .ss_pad_o({aux_sen2,aux_sen1,sen_dac,sen_lms2,sen_lms1}),
`endif // !`ifndef UMTRX
      .sclk_pad_o(sclk),.mosi_pad_o(mosi),.miso_pad_i(miso) );

   // /////////////////////////////////////////////////////////////////////////
   // I2C -- Slave #3
   i2c_master_top #(.ARST_LVL(1)) 
     i2c (.wb_clk_i(wb_clk),.wb_rst_i(wb_rst),.arst_i(1'b0), 
	  .wb_adr_i(s3_adr[4:2]),.wb_dat_i(s3_dat_o[7:0]),.wb_dat_o(s3_dat_i[7:0]),
	  .wb_we_i(s3_we),.wb_stb_i(s3_stb),.wb_cyc_i(s3_cyc),
	  .wb_ack_o(s3_ack),.wb_inta_o(i2c_int),
	  .scl_pad_i(scl_pad_i),.scl_pad_o(scl_pad_o),.scl_padoen_o(scl_pad_oen_o),
	  .sda_pad_i(sda_pad_i),.sda_pad_o(sda_pad_o),.sda_padoen_o(sda_pad_oen_o) );
     
   i2c_master_top #(.ARST_LVL(1)) 
     aux_i2c (.wb_clk_i(wb_clk),.wb_rst_i(wb_rst),.arst_i(1'b0), 
	  .wb_adr_i(s9_adr[4:2]),.wb_dat_i(s9_dat_o[7:0]),.wb_dat_o(s9_dat_i[7:0]),
	  .wb_we_i(s9_we),.wb_stb_i(s9_stb),.wb_cyc_i(s9_cyc),
	  .wb_ack_o(s9_ack),.wb_inta_o(aux_i2c_int),
	  .scl_pad_i(aux_scl_pad_i),.scl_pad_o(aux_scl_pad_o),.scl_padoen_o(aux_scl_pad_oen_o),
	  .sda_pad_i(aux_sda_pad_i),.sda_pad_o(aux_sda_pad_o),.sda_padoen_o(aux_sda_pad_oen_o) );

   assign 	 s3_dat_i[31:8] = 24'd0;
   assign 	 s9_dat_i[31:8] = 24'd0;
   
   // /////////////////////////////////////////////////////////////////////////
   // GPIOs

   wire [31:0] gpio_readback;
   
   gpio_atr #(.BASE(SR_GPIO), .WIDTH(32)) 
   gpio_atr(.clk(dsp_clk),.reset(dsp_rst),
	    .set_stb(set_stb_dsp),.set_addr(set_addr_dsp),.set_data(set_data_dsp),
`ifndef LMS602D_FRONTEND
	    .rx(run_rx0_d1 | run_rx1_d1), .tx(run_tx),
`else
	    .rx(run_rx0_d1 | run_rx1_d1), .tx(run_tx | run_tx1),
`endif // !`ifndef LMS602D_FRONTEND
	    .gpio({io_tx,io_rx}), .gpio_readback(gpio_readback) );

   // /////////////////////////////////////////////////////////////////////////
   // Buffer Pool Status -- Slave #5   
   
   //compatibility number -> increment when the fpga has been sufficiently altered
   localparam compat_num = {16'd8, 16'd2}; //major, minor

   wb_readback_mux buff_pool_status
     (.wb_clk_i(wb_clk), .wb_rst_i(wb_rst), .wb_stb_i(s5_stb),
      .wb_adr_i(s5_adr), .wb_dat_o(s5_dat_i), .wb_ack_o(s5_ack),

      .word00(32'b0),.word01(32'b0),.word02(32'b0),.word03(32'b0),
      .word04(32'b0),.word05(32'b0),.word06(32'b0),.word07({32'b0}),
      .word08(status),.word09(gpio_readback),.word10(vita_time[63:32]),
      .word11(vita_time[31:0]),.word12(compat_num),.word13({16'b0, aux_ld2, aux_ld1, button, 1'b0, clk_status, serdes_link_up, 10'b0}),
      .word14(vita_time_pps[63:32]),.word15(vita_time_pps[31:0])
      );

   // /////////////////////////////////////////////////////////////////////////
   // Ethernet MAC  Slave #6

   simple_gemac_wrapper #(.RXFIFOSIZE(ETH_RX_FIFOSIZE), 
			  .TXFIFOSIZE(ETH_TX_FIFOSIZE)) simple_gemac_wrapper
     (.clk125(clk_to_mac),  .reset(wb_rst),
      .GMII_GTX_CLK(GMII_GTX_CLK), .GMII_TX_EN(GMII_TX_EN),  
      .GMII_TX_ER(GMII_TX_ER), .GMII_TXD(GMII_TXD),
      .GMII_RX_CLK(GMII_RX_CLK), .GMII_RX_DV(GMII_RX_DV),  
      .GMII_RX_ER(GMII_RX_ER), .GMII_RXD(GMII_RXD),
      .sys_clk(dsp_clk),
      .rx_f36_data(wr2_dat), .rx_f36_src_rdy(wr2_ready_i), .rx_f36_dst_rdy(wr2_ready_o),
      .tx_f36_data(rd2_dat), .tx_f36_src_rdy(rd2_ready_o), .tx_f36_dst_rdy(rd2_ready_i),
      .wb_clk(wb_clk), .wb_rst(wb_rst), .wb_stb(s6_stb), .wb_cyc(s6_cyc), .wb_ack(s6_ack),
      .wb_we(s6_we), .wb_adr(s6_adr), .wb_dat_i(s6_dat_o), .wb_dat_o(s6_dat_i),
      .mdio(MDIO), .mdc(MDC),
      .debug(debug_mac));

   // /////////////////////////////////////////////////////////////////////////
   // Settings Bus -- Slave #7
   settings_bus settings_bus
     (.wb_clk(wb_clk),.wb_rst(wb_rst),.wb_adr_i(s7_adr),.wb_dat_i(s7_dat_o),
      .wb_stb_i(s7_stb),.wb_we_i(s7_we),.wb_ack_o(s7_ack),
      .strobe(set_stb),.addr(set_addr),.data(set_data));
   
   assign 	 s7_dat_i = 32'd0;

   settings_bus_crossclock settings_bus_crossclock
     (.clk_i(wb_clk), .rst_i(wb_rst), .set_stb_i(set_stb), .set_addr_i(set_addr), .set_data_i(set_data),
      .clk_o(dsp_clk), .rst_o(dsp_rst), .set_stb_o(set_stb_dsp), .set_addr_o(set_addr_dsp), .set_data_o(set_data_dsp));
`ifdef LMS_DSP
   wire [7:0] 	set_addr_dsp_low;
   wire [31:0] set_data_dsp_low;
   wire set_stb_dsp_low;
   settings_bus_crossclock settings_bus_dsp_crossclock
     (.clk_i(wb_clk), .rst_i(wb_rst), .set_stb_i(set_stb), .set_addr_i(set_addr), .set_data_i(set_data),
      .clk_o(lms_clk), .rst_o(), .set_stb_o(set_stb_dsp_low), .set_addr_o(set_addr_dsp_low), .set_data_o(set_data_dsp_low));
`endif // !`ifdef LMS_DSP
   
   // Output control lines
   wire [7:0] 	 clock_outs, serdes_outs, adc_outs;
   assign 	 {clock_ready, clk_en[1:0], clk_sel[1:0]} = clock_outs[4:0];
`ifdef LMS602D_FRONTEND
   assign lms_res = clock_outs[6:5];
`endif // !`ifdef LMS602D_FRONTEND
   assign 	 {ser_enable, ser_prbsen, ser_loopen, ser_rx_en} = serdes_outs[3:0];
   assign 	 {adc_oe_a, adc_on_a, adc_oe_b, adc_on_b } = adc_outs[3:0];

   wire 	 phy_reset;
   assign 	 PHY_RESETn = ~phy_reset;
   
   setting_reg #(.my_addr(SR_MISC+0),.width(8)) sr_clk
     (.clk(wb_clk),.rst(wb_rst),.strobe(s7_ack),.addr(set_addr),.in(set_data),.out(clock_outs),.changed());

   setting_reg #(.my_addr(SR_MISC+1),.width(8)) sr_ser
     (.clk(dsp_clk),.rst(dsp_rst),.strobe(set_stb_dsp),.addr(set_addr_dsp),.in(set_data_dsp),.out(serdes_outs),.changed());

   setting_reg #(.my_addr(SR_MISC+2),.width(8)) sr_adc
     (.clk(dsp_clk),.rst(dsp_rst),.strobe(set_stb_dsp),.addr(set_addr_dsp),.in(set_data_dsp),.out(adc_outs),.changed());

   setting_reg #(.my_addr(SR_MISC+4),.width(1)) sr_phy
     (.clk(dsp_clk),.rst(dsp_rst),.strobe(set_stb_dsp),.addr(set_addr_dsp),.in(set_data_dsp),.out(phy_reset),.changed());

   setting_reg #(.my_addr(SR_MISC+5),.width(1)) sr_bld
     (.clk(wb_clk),.rst(wb_rst),.strobe(set_stb),.addr(set_addr),.in(set_data),.out(bldr_done),.changed());

   // Diversity switches
   setting_reg #(.my_addr(SR_DIVSW+0),.width(1), .at_reset(32'd1)) sr_divsw1
     (.clk(wb_clk),.rst(wb_rst),.strobe(set_stb),.addr(set_addr),.in(set_data),.out(DivSw1),.changed());

   setting_reg #(.my_addr(SR_DIVSW+1),.width(1), .at_reset(32'd1)) sr_divsw2
     (.clk(wb_clk),.rst(wb_rst),.strobe(set_stb),.addr(set_addr),.in(set_data),.out(DivSw2),.changed());


   // /////////////////////////////////////////////////////////////////////////
   //  LEDS
   //    register 8 determines whether leds are controlled by SW or not
   //    1 = controlled by HW, 0 = by SW
   //    In Rev3 there are only 6 leds, and the highest one is on the ETH connector
   
   wire [7:0] 	 led_src, led_sw;
`ifndef LMS602D_FRONTEND
   wire [7:0] 	 led_hw = {run_tx, (run_rx0_d1 | run_rx1_d1), clk_status, serdes_link_up & good_sync, 1'b0};
`else
   wire [7:0] 	 led_hw = {run_tx0_mux, run_rx0_mux, run_tx1_mux, run_rx1_mux, 1'b0};
`endif // !`ifndef LMS602D_FRONTEND
   
   setting_reg #(.my_addr(SR_MISC+3),.width(8)) sr_led
     (.clk(dsp_clk),.rst(dsp_rst),.strobe(set_stb_dsp),.addr(set_addr_dsp),.in(set_data_dsp),.out(led_sw),.changed());

   setting_reg #(.my_addr(SR_MISC+6),.width(8), .at_reset(8'b0001_1110)) sr_led_src
     (.clk(dsp_clk),.rst(dsp_rst),.strobe(set_stb_dsp),.addr(set_addr_dsp), .in(set_data_dsp),.out(led_src),.changed());

   assign 	 leds = (led_src & led_hw) | (~led_src & led_sw);

   // /////////////////////////////////////////////////////////////////////////
   // GPSDO unit

   wire gpsdo_int;

   gpsdo gpsdo(
      .pps_in(pps_in),
      .clk_in(wb_clk),
      .wb_adr_i(s4_adr[4:2]),
      .wb_dat_i(s4_dat_o),
      .wb_dat_o(s4_dat_i),
      .wb_we_i(s4_we),
      .wb_stb_i(s4_stb),
      .wb_cyc_i(s4_cyc),
      .wb_ack_o(s4_ack),
      .wb_err_o(s4_err),
      .wb_int_o(gpsdo_int),
      .wb_clk_i(wb_clk),
      .wb_rst_i(wb_rst)
   );
 
   // /////////////////////////////////////////////////////////////////////////
   // Interrupt Controller, Slave #8

   assign irq= {{8'b0},
		{uart_tx_int[3:0], uart_rx_int[3:0]},
		{4'b0, clk_status, 3'b0},
		{2'b0,aux_i2c_int, PHY_INTn, i2c_int,spi_int,gpsdo_int,1'b0}};
   
   pic pic(.clk_i(wb_clk),.rst_i(wb_rst),.cyc_i(s8_cyc),.stb_i(s8_stb),.adr_i(s8_adr[4:2]),
	   .we_i(s8_we),.dat_i(s8_dat_o),.dat_o(s8_dat_i),.ack_o(s8_ack),.int_o(proc_int),
	   .irq(irq) );
 	 
   // /////////////////////////////////////////////////////////////////////////
   // UART, Slave #10

   quad_uart #(.TXDEPTH(3),.RXDEPTH(3)) uart  // depth of 3 is 128 entries
     (.clk_i(wb_clk),.rst_i(wb_rst),
      .we_i(sa_we),.stb_i(sa_stb),.cyc_i(sa_cyc),.ack_o(sa_ack),
      .adr_i(sa_adr[6:2]),.dat_i(sa_dat_o),.dat_o(sa_dat_i),
      .rx_int_o(uart_rx_int),.tx_int_o(uart_tx_int),
      .tx_o(uart_tx_o),.rx_i(uart_rx_i),.baud_o(uart_baud_o));
   // /////////////////////////////////////////////////////////////////////////
   // ICAP for reprogramming the FPGA, Slave #13 (D)

`ifndef UMTRX
   s3a_icap_wb s3a_icap_wb
     (.clk(wb_clk), .reset(wb_rst), .cyc_i(sd_cyc), .stb_i(sd_stb),
      .we_i(sd_we), .ack_o(sd_ack), .dat_i(sd_dat_o), .dat_o(sd_dat_i));
`else
   s6_icap_wb s6_icap_wb
     (.clk(wb_clk), .clk_icap(clk_icap),.reset(wb_rst), .cyc_i(sd_cyc), .stb_i(sd_stb),
      .we_i(sd_we), .ack_o(sd_ack), .dat_i(sd_dat_o), .dat_o(sd_dat_i));
`endif
   
   // /////////////////////////////////////////////////////////////////////////
   // SPI for Flash -- Slave #14 (E)
   spi_top flash_spi
     (.wb_clk_i(wb_clk),.wb_rst_i(wb_rst),.wb_adr_i(se_adr[4:0]),.wb_dat_i(se_dat_o),
      .wb_dat_o(se_dat_i),.wb_sel_i(se_sel),.wb_we_i(se_we),.wb_stb_i(se_stb),
      .wb_cyc_i(se_cyc),.wb_ack_o(se_ack),.wb_err_o(se_err),.wb_int_o(spiflash_int),
      .ss_pad_o(spiflash_cs),
      .sclk_pad_o(spiflash_clk),.mosi_pad_o(spiflash_mosi),.miso_pad_i(spiflash_miso) );

   // /////////////////////////////////////////////////////////////////////////
   // ADC Frontend
`ifndef LMS602D_FRONTEND
   wire [23:0] 	 adc_i, adc_q;
   
   rx_frontend #(.BASE(SR_RX_FRONT)) rx_frontend
     (.clk(dsp_clk),.rst(dsp_rst),
     .adc_clk(dsp_clk),
      .set_stb(set_stb_dsp),.set_addr(set_addr_dsp),.set_data(set_data_dsp),
      .adc_a({adc_a,2'b00}),.adc_ovf_a(adc_ovf_a),
      .adc_b({adc_b,2'b00}),.adc_ovf_b(adc_ovf_b),
      .i_out(adc_i), .q_out(adc_q), .run(run_rx0_d1 | run_rx1_d1), .debug());
`else
   wire [23:0] 	 adc_i_0, adc_q_0, adc_i_1, adc_q_1;
   wire [23:0] 	 i_0_mux, q_0_mux, i_1_mux, q_1_mux;
   wire run_rx0_mux, run_rx1_mux;
   wire adc_ovf_i_0_mux, adc_ovf_q_0_mux, adc_ovf_i_1_mux, adc_ovf_q_1_mux;
   
   rx_frontend #(.BASE(SR_RX_FRONT0)) rx_frontend0
     (.clk(dsp_clk),.rst(dsp_rst),
     .adc_clk(lms_clk),
      .set_stb(set_stb_dsp),.set_addr(set_addr_dsp),.set_data(set_data_dsp),
      .adc_a({adc_a_0,2'b00}),.adc_ovf_a(adc_ovf_i_0_mux),
      .adc_b({adc_b_0,2'b00}),.adc_ovf_b(adc_ovf_q_0_mux),
      .i_out(adc_i_0), .q_out(adc_q_0), .run(run_rx0_d1), .debug());

   rx_frontend #(.BASE(SR_RX_FRONT1)) rx_frontend1
     (.clk(dsp_clk),.rst(dsp_rst),
     .adc_clk(lms_clk),
      .set_stb(set_stb_dsp),.set_addr(set_addr_dsp),.set_data(set_data_dsp),
      .adc_a({adc_a_1,2'b00}),.adc_ovf_a(adc_ovf_i_1_mux),
      .adc_b({adc_b_1,2'b00}),.adc_ovf_b(adc_ovf_q_1_mux),
      .i_out(adc_i_1), .q_out(adc_q_1), .run(run_rx1_d1), .debug());

   frontend_sw #(.BASE(SR_RX_FRONT_SW)) rx_frontend_sw
     (
      .clk(lms_clk), .rst(dsp_rst),
      .set_stb(set_stb_dsp_low),.set_addr(set_addr_dsp_low),.set_data(set_data_dsp_low),
      .i_0_in(adc_i_0), .q_0_in(adc_q_0), 
      .i_1_in(adc_i_1), .q_1_in(adc_q_1), 
      .run_0_in(run_rx0_d1), .run_1_in(run_rx1_d1), 
      .adc_ovf_i_0_in(adc_ovf_a_0), .adc_ovf_q_0_in(adc_ovf_b_0), 
      .adc_ovf_i_1_in(adc_ovf_a_1), .adc_ovf_q_1_in(adc_ovf_b_1), 
      .i_0_mux(i_0_mux), .q_0_mux(q_0_mux), 
      .i_1_mux(i_1_mux), .q_1_mux(q_1_mux), 
      .run_0_mux(run_rx0_mux), .run_1_mux(run_rx1_mux), 
      .adc_ovf_i_0_mux(adc_ovf_i_0_mux), .adc_ovf_q_0_mux(adc_ovf_q_0_mux), 
      .adc_ovf_i_1_mux(adc_ovf_i_1_mux), .adc_ovf_q_1_mux(adc_ovf_q_1_mux));      
`endif // !`ifndef LMS602D_FRONTEND
   
   // /////////////////////////////////////////////////////////////////////////
   // DSP RX 0
   wire [31:0] 	 sample_rx0;
   wire 	 clear_rx0, strobe_rx0;

   always @(posedge dsp_clk)
     run_rx0_d1 <= run_rx0;
   
   dsp_core_rx #(.BASE(SR_RX_DSP0)) dsp_core_rx0
     (.clk(dsp_clk),.rst(dsp_rst),
`ifndef LMS_DSP
     .adc_clk(dsp_clk),
`else
     .adc_clk(lms_clk),
`endif // !`ifndef LMS_DSP
      .set_stb(set_stb_dsp),.set_addr(set_addr_dsp),.set_data(set_data_dsp),
`ifndef LMS602D_FRONTEND
      .adc_i(adc_i),.adc_ovf_i(adc_ovf_a),.adc_q(adc_q),.adc_ovf_q(adc_ovf_b),
`else
      .adc_i(i_0_mux),.adc_ovf_i(adc_ovf_i_0_mux),.adc_q(q_0_mux),.adc_ovf_q(adc_ovf_q_0_mux),
`endif // !`ifndef LMS602D_FRONTEND
      .sample(sample_rx0), .run(run_rx0_d1), .strobe(strobe_rx0),
      .debug() );

   setting_reg #(.my_addr(SR_RX_CTRL0+3)) sr_clear_rx0
     (.clk(dsp_clk),.rst(dsp_rst),
      .strobe(set_stb_dsp),.addr(set_addr_dsp),.in(set_data_dsp),
      .out(),.changed(clear_rx0));

   vita_rx_chain #(.BASE(SR_RX_CTRL0),.UNIT(0),.FIFOSIZE(DSP_RX_FIFOSIZE)) vita_rx_chain0
     (.clk(dsp_clk), .reset(dsp_rst), .clear(clear_rx0),
      .set_stb(set_stb_dsp),.set_addr(set_addr_dsp),.set_data(set_data_dsp),
      .vita_time(vita_time), .overrun(overrun0),
      .sample(sample_rx0), .run(run_rx0), .strobe(strobe_rx0),
      .rx_data_o(wr1_dat), .rx_src_rdy_o(wr1_ready_i), .rx_dst_rdy_i(wr1_ready_o),
      .debug() );

   // /////////////////////////////////////////////////////////////////////////
   // DSP RX 1
   wire [31:0] 	 sample_rx1;
   wire 	 clear_rx1, strobe_rx1;

   always @(posedge dsp_clk)
     run_rx1_d1 <= run_rx1;
   
   dsp_core_rx #(.BASE(SR_RX_DSP1)) dsp_core_rx1
     (.clk(dsp_clk),.rst(dsp_rst),
`ifndef LMS_DSP
     .adc_clk(dsp_clk),
`else
     .adc_clk(lms_clk),
`endif // !`ifndef LMS_DSP
      .set_stb(set_stb_dsp),.set_addr(set_addr_dsp),.set_data(set_data_dsp),
`ifndef LMS602D_FRONTEND
      .adc_i(adc_i),.adc_ovf_i(adc_ovf_a),.adc_q(adc_q),.adc_ovf_q(adc_ovf_b),
`else
      .adc_i(i_1_mux),.adc_ovf_i(adc_ovf_i_1_mux),.adc_q(q_1_mux),.adc_ovf_q(adc_ovf_q_1_mux),
`endif // !`ifndef LMS602D_FRONTEND
      .sample(sample_rx1), .run(run_rx1_d1), .strobe(strobe_rx1),
      .debug() );

   setting_reg #(.my_addr(SR_RX_CTRL1+3)) sr_clear_rx1
     (.clk(dsp_clk),.rst(dsp_rst),
      .strobe(set_stb_dsp),.addr(set_addr_dsp),.in(set_data_dsp),
      .out(),.changed(clear_rx1));

   vita_rx_chain #(.BASE(SR_RX_CTRL1),.UNIT(2),.FIFOSIZE(DSP_RX_FIFOSIZE)) vita_rx_chain1
     (.clk(dsp_clk), .reset(dsp_rst), .clear(clear_rx1),
      .set_stb(set_stb_dsp),.set_addr(set_addr_dsp),.set_data(set_data_dsp),
      .vita_time(vita_time), .overrun(overrun1),
      .sample(sample_rx1), .run(run_rx1), .strobe(strobe_rx1),
      .rx_data_o(wr3_dat), .rx_src_rdy_o(wr3_ready_i), .rx_dst_rdy_i(wr3_ready_o),
      .debug() );

   // ///////////////////////////////////////////////////////////////////////////////////
   // DSP TX

   wire [35:0] 	 tx_data;
   wire 	 tx_src_rdy, tx_dst_rdy;
`ifdef LMS602D_FRONTEND
   wire [35:0] 	 tx_data_1;
   wire 	 tx_src_rdy_1, tx_dst_rdy_1;
`endif // !`ifdef LMS602D_FRONTEND
   wire [31:0] 	 debug_vt;
   wire 	 clear_tx;

   setting_reg #(.my_addr(SR_TX_CTRL+1)) sr_clear_tx
     (.clk(dsp_clk),.rst(dsp_rst),.strobe(set_stb_dsp),.addr(set_addr_dsp),
      .in(set_data_dsp),.out(),.changed(clear_tx));

`ifndef NO_EXT_FIFO
   assign 	 RAM_A[20:19] = 2'b0;
`endif // !`ifndef NO_EXT_FIFO
   
   ext_fifo #(.EXT_WIDTH(36),.INT_WIDTH(36),.RAM_DEPTH(19),.FIFO_DEPTH(19)) 
     ext_fifo_i1
       (.int_clk(dsp_clk),
	.ext_clk(dsp_clk),
`ifndef LMS_DSP
     .dac_clk(dsp_clk),
`else
     .dac_clk(lms_clk),
`endif // !`ifndef LMS_DSP
	.rst(dsp_rst | clear_tx),
`ifndef NO_EXT_FIFO
	.RAM_D_pi(RAM_D_pi),
	.RAM_D_po(RAM_D_po),
	.RAM_D_poe(RAM_D_poe),
	.RAM_A(RAM_A[18:0]),
	.RAM_WEn(RAM_WEn),
	.RAM_CENn(RAM_CENn),
	.RAM_LDn(RAM_LDn),
	.RAM_OEn(RAM_OEn),
	.RAM_CE1n(RAM_CE1n),
`else
	.RAM_D_pi(),
	.RAM_D_po(),
	.RAM_D_poe(),
	.RAM_A(),
	.RAM_WEn(),
	.RAM_CENn(),
	.RAM_LDn(),
	.RAM_OEn(),
	.RAM_CE1n(),
`endif // !`ifndef NO_EXT_FIFO
	.datain(rd1_dat),
	.src_rdy_i(rd1_ready_o),
	.dst_rdy_o(rd1_ready_i),
	.dataout(tx_data),
	.src_rdy_o(tx_src_rdy),
	.dst_rdy_i(tx_dst_rdy),
`ifdef LMS602D_FRONTEND
	.src1_rdy_i(rd1_ready_o_1),
	.dst1_rdy_o(rd1_ready_i_1),
	.src1_rdy_o(tx_src_rdy_1),
	.dst1_rdy_i(tx_dst_rdy_1),
	.dataout_1(tx_data_1),
`endif // !`ifdef LMS602D_FRONTEND
	.debug(debug_extfifo),
	.debug2(debug_extfifo2) );

   // /////////////////////////////////////////////////////////////////////////
   // DSP TX 0
   wire [23:0] 	 tx_i, tx_q;
   wire [23:0] 	 tx1_i, tx1_q;
   wire [23:0] 	 front_i_0, front_q_0;
   wire [23:0] 	 front_i_1, front_q_1;
   
   vita_tx_chain #(.BASE_CTRL(SR_TX_CTRL), .BASE_DSP(SR_TX_DSP), 
		   .REPORT_ERROR(1), .DO_FLOW_CONTROL(1),
		   .PROT_ENG_FLAGS(1), .USE_TRANS_HEADER(1),
		   .DSP_NUMBER(0))
   vita_tx_chain
     (.clk(dsp_clk), .reset(dsp_rst),
`ifndef LMS_DSP
     .dac_clk(dsp_clk),
      .set_stb(set_stb_dsp),.set_addr(set_addr_dsp),.set_data(set_data_dsp),
`else
     .dac_clk(lms_clk),
      .set_stb(set_stb_dsp_low),.set_addr(set_addr_dsp_low),.set_data(set_data_dsp_low),
`endif // !`ifndef LMS_DSP
      .vita_time(vita_time),
      .tx_data_i(tx_data), .tx_src_rdy_i(tx_src_rdy), .tx_dst_rdy_o(tx_dst_rdy),
      .err_data_o(tx_err_data), .err_src_rdy_o(tx_err_src_rdy), .err_dst_rdy_i(tx_err_dst_rdy),
      .tx_i(tx_i),.tx_q(tx_q),
      .underrun(underrun), .run(run_tx),
      .debug(debug_vt));

`ifdef LMS602D_FRONTEND     
   frontend_sw #(.BASE(SR_TX_FRONT_SW)) tx_frontend_sw
     (
      .clk(lms_clk), .rst(dsp_rst),
      .set_stb(set_stb_dsp_low),.set_addr(set_addr_dsp_low),.set_data(set_data_dsp_low),
      .i_0_in(tx_i), .q_0_in(tx_q), 
      .i_1_in(tx1_i), .q_1_in(tx1_q),
      .i_0_mux(front_i_0), .q_0_mux(front_q_0), 
      .i_1_mux(front_i_1), .q_1_mux(front_q_1),
      .run_0_in(run_tx), .run_1_in(run_tx1),       
      .run_0_mux(run_tx0_mux), .run_1_mux(run_tx1_mux),      
      .adc_ovf_i_0_in(), .adc_ovf_q_0_in(), 
      .adc_ovf_i_1_in(), .adc_ovf_q_1_in(),  
      .adc_ovf_i_0_mux(), .adc_ovf_q_0_mux(), 
      .adc_ovf_i_1_mux(), .adc_ovf_q_1_mux());  
`endif // !`ifndef LMS602D_FRONTEND

   tx_frontend #(.BASE(SR_TX_FRONT)) tx_frontend
     (
`ifndef LMS_DSP
     .clk(dsp_clk), .rst(dsp_rst),
      .set_stb(set_stb_dsp),.set_addr(set_addr_dsp),.set_data(set_data_dsp),
`else
     .clk(lms_clk), .rst(dsp_rst),
      .set_stb(set_stb_dsp_low),.set_addr(set_addr_dsp_low),.set_data(set_data_dsp_low),
`endif // !`ifndef LMS_DSP
      .tx_i(front_i_0), .tx_q(front_q_0), .run(1'b1),
      .dac_a(dac_a), .dac_b(dac_b));

   // /////////////////////////////////////////////////////////////////////////
   // DSP TX 1
   
   vita_tx_chain #(.BASE_CTRL(SR_TX1_CTRL), .BASE_DSP(SR_TX1_DSP), 
		   .REPORT_ERROR(1), .DO_FLOW_CONTROL(1),
		   .PROT_ENG_FLAGS(1), .USE_TRANS_HEADER(1),
		   .DSP_NUMBER(1))
   vita_tx1_chain
     (.clk(dsp_clk), .reset(dsp_rst),
`ifndef LMS_DSP
     .dac_clk(dsp_clk),
      .set_stb(set_stb_dsp),.set_addr(set_addr_dsp),.set_data(set_data_dsp),
`else
     .dac_clk(lms_clk),
      .set_stb(set_stb_dsp_low),.set_addr(set_addr_dsp_low),.set_data(set_data_dsp_low),
`endif // !`ifndef LMS_DSP
      .vita_time(vita_time),
      .tx_data_i(tx_data_1), .tx_src_rdy_i(tx_src_rdy_1), .tx_dst_rdy_o(tx_dst_rdy_1),
      .err_data_o(tx1_err_data), .err_src_rdy_o(tx1_err_src_rdy), .err_dst_rdy_i(tx1_err_dst_rdy),
      .tx_i(tx1_i),.tx_q(tx1_q),
      .underrun(underrun1), .run(run_tx1),
      .debug());

   tx_frontend #(.BASE(SR_TX1_FRONT)) tx1_frontend
     (
`ifndef LMS_DSP
     .clk(dsp_clk), .rst(dsp_rst),
      .set_stb(set_stb_dsp),.set_addr(set_addr_dsp),.set_data(set_data_dsp),
`else
     .clk(lms_clk), .rst(dsp_rst),
      .set_stb(set_stb_dsp_low),.set_addr(set_addr_dsp_low),.set_data(set_data_dsp_low),
`endif // !`ifndef LMS_DSP
      .tx_i(front_i_1), .tx_q(front_q_1), .run(1'b1),
      .dac_a(dac1_a), .dac_b(dac1_b));

   // ///////////////////////////////////////////////////////////////////////////////////
   // SERDES

   serdes #(.TXFIFOSIZE(SERDES_TX_FIFOSIZE),.RXFIFOSIZE(SERDES_RX_FIFOSIZE)) serdes
     (.clk(dsp_clk),.rst(dsp_rst),
      .ser_tx_clk(ser_tx_clk),.ser_t(ser_t),.ser_tklsb(ser_tklsb),.ser_tkmsb(ser_tkmsb),
      .rd_dat_i(rd0_dat[31:0]),.rd_flags_i(rd0_dat[35:32]),.rd_ready_o(rd0_ready_i),.rd_ready_i(rd0_ready_o),
      .ser_rx_clk(ser_rx_clk),.ser_r(ser_r),.ser_rklsb(ser_rklsb),.ser_rkmsb(ser_rkmsb),
      .wr_dat_o(wr0_dat[31:0]),.wr_flags_o(wr0_dat[35:32]),.wr_ready_o(wr0_ready_i),.wr_ready_i(wr0_ready_o),
      .tx_occupied(ser_tx_occ),.tx_full(ser_tx_full),.tx_empty(ser_tx_empty),
      .rx_occupied(ser_rx_occ),.rx_full(ser_rx_full),.rx_empty(ser_rx_empty),
      .serdes_link_up(serdes_link_up),.debug0(debug_serdes0), .debug1(debug_serdes1) );

   // /////////////////////////////////////////////////////////////////////////
   // VITA Timing

   wire [31:0] 	 debug_sync;

   time_64bit #(.TICKS_PER_SEC(32'd13000000),.BASE(SR_TIME64)) time_64bit
     (.clk(lms_clk), .rst(dsp_rst), .set_stb(set_stb_dsp_low), .set_addr(set_addr_dsp_low), .set_data(set_data_dsp_low),
      .pps(pps_in), .vita_time(vita_time), .vita_time_pps(vita_time_pps), .pps_int(pps_int),
      .exp_time_in(exp_time_in), .exp_time_out(exp_time_out), .good_sync(good_sync), .debug(debug_sync));

   // /////////////////////////////////////////////////////////////////////////////////////////
   // Debug Pins
  
   assign debug_clk = 2'b00; // {dsp_clk, clk_to_mac};
   assign debug = 32'd0;
   assign debug_gpio_0 = 32'd0;
   assign debug_gpio_1 = 32'd0;
   
endmodule // u2_core
