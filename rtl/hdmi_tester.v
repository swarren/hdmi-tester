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

`timescale 1ns / 1ps

module hdmi_tester(
    input wire clk50,
    inout wire hdmi_scl,
    inout wire hdmi_sda,
    output reg hpd,
    input wire hdmi_clk_p,
    input wire hdmi_clk_n,
    input wire hdmi_in_0_p,
    input wire hdmi_in_0_n,
    input wire hdmi_in_1_p,
    input wire hdmi_in_1_n,
    input wire hdmi_in_2_p,
    input wire hdmi_in_2_n,
    input wire rxd,
    output wire txd,
    // Debug:
    output wire portd2,
    output wire portd0,
    output wire [7:0] leds
);
    parameter CLK_CTR_MAX = 27;

    assign portd2 = hdmi_scl;
    assign portd0 = hdmi_sda;

    reg edid_we;
    reg [14:0] edid_waddr;
    reg [7:0] edid_wdata;
    wire [14:0] edid_raddr;
    wire [7:0] edid_rdata;
    edidram edidram(
        .clk(clk50),
        .we(edid_we),
        .waddr(edid_waddr),
        .wdata(edid_wdata),
        .raddr(edid_raddr),
        .rdata(edid_rdata)
    );

    i2c_eeprom i2c_eeprom(
        .clk(clk50),
        .enable(hpd),
        .scl_wire(hdmi_scl),
        .sda_wire(hdmi_sda),
        .edid_addr(edid_raddr),
        .edid_data(edid_rdata)
    );

    wire pll_locked;
    reg clk_ctr_reset_req;
    wire clk_ctr_reset_ack;
    wire [CLK_CTR_MAX:0] clk_ctr_at_reset;
    hdmi_rx #(
        .CLK_CTR_MAX(CLK_CTR_MAX)
    ) hdmi_rx (
        .clk(clk50),
        .hdmi_clk_p(hdmi_clk_p),
        .hdmi_clk_n(hdmi_clk_n),
        .hdmi_in_0_p(hdmi_in_0_p),
        .hdmi_in_0_n(hdmi_in_0_n),
        .hdmi_in_1_p(hdmi_in_1_p),
        .hdmi_in_1_n(hdmi_in_1_n),
        .hdmi_in_2_p(hdmi_in_2_p),
        .hdmi_in_2_n(hdmi_in_2_n),
        .pll_locked__clk(pll_locked),
        .clk_ctr_reset_req__clk(clk_ctr_reset_req),
        .clk_ctr_reset_ack__clk(clk_ctr_reset_ack),
        .clk_ctr_at_reset__clk(clk_ctr_at_reset),
        .dbg(leds)
    );

`define UART_STATE_WAIT_BREAK              0
`define UART_STATE_WAIT_CMD                1
`define UART_STATE_EDID                    2
`define UART_STATE_HPD                     3
`define UART_STATE_CLK_MEASURE_WAIT_TIME   4
`define UART_STATE_CLK_MEASURE_WAIT_RESULT 5
`define UART_STATE_SEND_VAL                6
`define UART_STATE_SEND_CR                 7
`define UART_STATE_SEND_LF                 8

    reg [3:0] uart_state = `UART_STATE_WAIT_BREAK;
    reg uart_tx_load;
    reg [7:0] uart_tx_data;
    wire uart_tx_idle;
    wire uart_rx_strobe;
    wire [7:0] uart_rx_data;
    wire uart_rx_break;

    reg [25:0] timer;
    reg [3:0] send_nibbles;
    reg [31:0] send_val;

    always @(posedge clk50) begin
        edid_we <= 1'b0;
        uart_tx_load <= 1'b0;

        case (uart_state)
            `UART_STATE_WAIT_BREAK: begin
            end
            `UART_STATE_WAIT_CMD: begin
                if (uart_rx_strobe) begin
                    case (uart_rx_data)
                        "C": begin
                            uart_state <= `UART_STATE_CLK_MEASURE_WAIT_TIME;
                            clk_ctr_reset_req <= ~clk_ctr_reset_req;
                            timer <= 26'd50000000;
                        end
                        "E": begin
                            uart_state <= `UART_STATE_EDID;
                            edid_waddr <= 15'h0;
                        end
                        "H": begin
                            uart_state <= `UART_STATE_HPD;
                        end
                        default: begin
                            uart_state <= `UART_STATE_WAIT_BREAK;
                        end
                    endcase
                end
            end
            `UART_STATE_EDID: begin
                if (uart_rx_strobe) begin
                    edid_wdata <= uart_rx_data;
                    edid_we <= 1'b1;
                end
                if (edid_we) begin
                    edid_waddr <= edid_waddr + 15'h1;
                    if (&edid_waddr) begin
                        send_val <= 0;
                        send_nibbles <= 1;
                        uart_state <= `UART_STATE_SEND_VAL;
                    end
                end
            end
            `UART_STATE_HPD: begin
                if (uart_rx_strobe) begin
                    hpd <= uart_rx_data[0];
                    send_val <= 0;
                    send_nibbles <= 1;
                    uart_state <= `UART_STATE_SEND_VAL;
                end
            end
            `UART_STATE_CLK_MEASURE_WAIT_TIME: begin
                if (~pll_locked) begin
                    send_val <= 32'hFFFFFFFF;
                    send_nibbles <= 8;
                    uart_state <= `UART_STATE_SEND_VAL;
                end else if (timer) begin
                    timer <= timer - 26'h1;
                end else begin
                    uart_state <= `UART_STATE_CLK_MEASURE_WAIT_RESULT;
                    clk_ctr_reset_req <= ~clk_ctr_reset_req;
                end
            end
            `UART_STATE_CLK_MEASURE_WAIT_RESULT: begin
                if (~pll_locked) begin
                    send_val <= 32'hFFFFFFFF;
                    send_nibbles <= 8;
                    uart_state <= `UART_STATE_SEND_VAL;
                end else begin
                    if (~(clk_ctr_reset_req ^ clk_ctr_reset_ack)) begin
                        send_val <= {{(32-(CLK_CTR_MAX+1)){1'b0}}, clk_ctr_at_reset};
                        send_nibbles <= 8;
                        uart_state <= `UART_STATE_SEND_VAL;
                    end
                end
            end
            `UART_STATE_SEND_VAL: begin
                if (uart_tx_idle & ~uart_tx_load) begin
                    uart_tx_load <= 1'b1;
                    if (send_val[31-:4] > 9) begin
                        // FIXME: Char constants need width to force this to 8-bit math
                        uart_tx_data <= send_val[31-:4] + "A" - 8'd10;
                    end else begin
                        uart_tx_data <= send_val[31-:4] + "0";
                    end
                    send_val <= {send_val[27:0], 4'h0};
                    send_nibbles <= send_nibbles - 4'h1;
                    if (send_nibbles == 1) begin
                        uart_state <= `UART_STATE_SEND_CR;
                    end
                end
            end
            `UART_STATE_SEND_CR: begin
                if (uart_tx_idle & ~uart_tx_load) begin
                    uart_tx_load <= 1'b1;
                    uart_tx_data <= 8'd13;
                    uart_state <= `UART_STATE_SEND_LF;
                end
            end
            `UART_STATE_SEND_LF: begin
                if (uart_tx_idle & ~uart_tx_load) begin
                    uart_tx_load <= 1'b1;
                    uart_tx_data <= 8'd10;
                    uart_state <= `UART_STATE_WAIT_CMD;
                end
            end
        endcase
        if (uart_rx_break) begin
            uart_state <= `UART_STATE_WAIT_CMD;
        end
    end

    uart uart(
        .clk(clk50),
        .rxd(rxd),
        .txd(txd),
        .tx_load(uart_tx_load),
        .tx_data(uart_tx_data),
        .tx_idle(uart_tx_idle),
        .rx_strobe(uart_rx_strobe),
        .rx_data(uart_rx_data),
        .rx_break(uart_rx_break)
    );
endmodule
