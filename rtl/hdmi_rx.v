// Copyright (c) 2015 Stephen Warren
// 
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// 
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
// 
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

// Portions of this file were inspired by:
// http://hamsterworks.co.nz/mediawiki/index.php/HDMI_Input
// Copyright (c) 2014 Mike Field
// Distributed under the same license as above.

`timescale 1ns / 1ps

module hdmi_rx #(
    parameter CLK_CTR_MAX = 27,
    parameter SYNC_MAX = 2
) (
    input wire clk,
    input wire hdmi_clk_p,
    input wire hdmi_clk_n,
    input wire hdmi_in_0_p,
    input wire hdmi_in_0_n,
    input wire hdmi_in_1_p,
    input wire hdmi_in_1_n,
    input wire hdmi_in_2_p,
    input wire hdmi_in_2_n,
    output wire pll_locked__clk,
    input wire clk_ctr_reset_req__clk,
    output wire clk_ctr_reset_ack__clk,
    output wire [CLK_CTR_MAX:0] clk_ctr_at_reset__clk,
    output reg [7:0] dbg
);
    // HDMI clock extraction

    wire hdmi_clk_unbuf;
    IBUFDS #(
        .DIFF_TERM("FALSE"),
        .IBUF_LOW_PWR("TRUE"),
        .IOSTANDARD("TMDS_33")
    ) ibufds_hdmi_clk(
        .O(hdmi_clk_unbuf),
        .I(hdmi_clk_p),
        .IB(hdmi_clk_n)
    );

    wire hdmi_clk;
    BUFG bufg_hdmi_clk(
        .I(hdmi_clk_unbuf),
        .O(hdmi_clk)
    );

    wire clk_fb;
    wire clk_10x_unbuf;
    wire clk_2x_unbuf;
    wire clk_1x_unbuf;
    wire pll_locked;
    PLL_BASE #(
        .CLKFBOUT_MULT(10),
        .CLKOUT0_DIVIDE(1),
        .CLKOUT0_PHASE(0.0),
        .CLKOUT1_DIVIDE(5),
        .CLKOUT1_PHASE(0.0),
        .CLKOUT2_DIVIDE(10),
        .CLKOUT2_PHASE(0.0),
        .CLK_FEEDBACK("CLKFBOUT"),
        .CLKIN_PERIOD(25.0), // FIXME: This depends on the source! (40MHz for 800x600)
        .DIVCLK_DIVIDE(1)
    ) pll_base_hdmi_clk (
        .CLKFBOUT(clk_fb),
        .CLKOUT0(clk_10x_unbuf),
        .CLKOUT1(clk_2x_unbuf),
        .CLKOUT2(clk_1x_unbuf),
        .CLKOUT3(),
        .CLKOUT4(),
        .CLKOUT5(),
        .LOCKED(pll_locked),
        .CLKFBIN(clk_fb),
        .CLKIN(hdmi_clk),
        .RST(1'b0)
    );

    wire clk_10x;
    wire clk_2x;
    wire clk_1x;
    BUFG bufg_clk_10x(.I(clk_10x_unbuf), .O(clk_10x));
    BUFG bufg_clk_2x(.I(clk_2x_unbuf),  .O(clk_2x));
    BUFG bufg_clk_1x(.I(clk_1x_unbuf),  .O(clk_1x));

    // Differential -> single-ended
 
    // Lane 0 and 1 aren't used, but if we don't instantiate an IBUFDS on
    // them, ISE complains that the signals are marked differntial in the
    // UCF file, but are actually single-ended.

    wire hdmi_in_0;
    IBUFDS #(
        .DIFF_TERM("FALSE"),
        .IBUF_LOW_PWR("TRUE"),
        .IOSTANDARD("TMDS_33")
    ) ibufds0(
        .O(hdmi_in_0),
        .I(hdmi_in_0_p),
        .IB(hdmi_in_0_n)
    );

    wire hdmi_in_1;
    IBUFDS #(
        .DIFF_TERM("FALSE"),
        .IBUF_LOW_PWR("TRUE"),
        .IOSTANDARD("TMDS_33")
    ) ibufds1(
        .O(hdmi_in_1),
        .I(hdmi_in_1_p),
        .IB(hdmi_in_1_n)
    );

    wire hdmi_in_2;
    IBUFDS #(
        .DIFF_TERM("FALSE"),
        .IBUF_LOW_PWR("TRUE"),
        .IOSTANDARD("TMDS_33")
    ) ibufds2(
        .O(hdmi_in_2),
        .I(hdmi_in_2_p),
        .IB(hdmi_in_2_n)
    );

    // Import signals to HDMI clock domain

    reg [SYNC_MAX:0] clk_ctr_reset_req_r;
    wire clk_ctr_reset_req = clk_ctr_reset_req_r[SYNC_MAX];
    always @(posedge clk_1x) begin
        clk_ctr_reset_req_r <= {clk_ctr_reset_req_r[SYNC_MAX-1:0], clk_ctr_reset_req__clk};
    end

    // HDMI clock measurement

    reg [CLK_CTR_MAX:0] clk_ctr;
    reg [CLK_CTR_MAX:0] clk_ctr_at_reset;
    reg clk_ctr_reset_req_prev;
    reg clk_ctr_reset_ack;
    always @(posedge clk_1x) begin
        clk_ctr_reset_req_prev <= clk_ctr_reset_req;
        if (clk_ctr_reset_req ^ clk_ctr_reset_req_prev) begin
            clk_ctr_at_reset <= clk_ctr;
            clk_ctr <= 0;
            // Perhaps this should be delayed, to make sure the other clock
            // domain sees this after clk_ctr_at_reset has stabilized through
            // the synchronizer?
            clk_ctr_reset_ack <= clk_ctr_reset_req;
        end else begin
            if (~&clk_ctr) begin
                clk_ctr <= clk_ctr + {{CLK_CTR_MAX{1'b0}}, 1'b1};
            end
        end
    end

    // Export signals to client clock domain

    reg [SYNC_MAX:0] pll_locked_r;
    always @(posedge clk) begin
        pll_locked_r <= {pll_locked_r[SYNC_MAX-1:0], pll_locked};
    end
    assign pll_locked__clk = pll_locked_r[SYNC_MAX];

    reg [SYNC_MAX:0] clk_ctr_reset_ack_r;
    assign clk_ctr_reset_ack__clk = clk_ctr_reset_ack_r[SYNC_MAX];
    always @(posedge clk) begin
        clk_ctr_reset_ack_r <= {clk_ctr_reset_ack_r[SYNC_MAX-1:0], clk_ctr_reset_ack};
    end

    reg [CLK_CTR_MAX:0] clk_ctr_at_reset_r [SYNC_MAX:0];
    assign clk_ctr_at_reset__clk = clk_ctr_at_reset_r[SYNC_MAX];
    integer i;
    always @(posedge clk) begin
        clk_ctr_at_reset_r[0] <= clk_ctr_at_reset;
        for (i = 1; i <= SYNC_MAX; i = i + 1) begin
            clk_ctr_at_reset_r[i] <= clk_ctr_at_reset_r[i - 1];
        end
    end

    // Debug

    always @(posedge clk) begin
        dbg <= 8'h0;
    end
endmodule
