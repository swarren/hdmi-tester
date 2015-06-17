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

`define DIVISOR 9'h1b2

module uart(
    input wire clk,
    input wire rxd,
    output wire txd,
    input wire tx_load,
    input wire [7:0] tx_data,
    output reg tx_idle,
    output reg rx_strobe,
    output wire [7:0] rx_data,
    output reg rx_break
);
`define SYNC_BITS 2
    reg [`SYNC_BITS-1:0] rxd_r;
    wire rxd_sync = rxd_r[`SYNC_BITS-1];

    always @(posedge clk) begin
        rxd_r <= {rxd_r[`SYNC_BITS-2:0], rxd};
    end

    reg [7:0] rx_div;
    wire rx_tick = ~|rx_div;
    reg rx_div_is_middle;
    reg [3:0] rx_ctr;
    reg rx_in_char;
    reg rx_in_break;
    reg [8:0] rx_shifter;
    wire [8:0] rx_shifter_next = {rxd_sync, rx_shifter[8:1]};
    assign rx_data = rx_shifter[7:0];

    always @(posedge clk) begin
        rx_strobe <= 1'b0;
        rx_break <= 1'b0;

        if (~rx_in_char && ~rx_in_break && ~rx_div_is_middle) begin
            if (~rxd_sync) begin
                rx_div <= (`DIVISOR / 2) - 1;
                rx_div_is_middle <= 1'b1;
                rx_ctr <= 4'hE;
                rx_in_char <= 1'b1;
                rx_in_break <= 1'b1;
            end
        end else begin
            if (rx_tick) begin
                rx_div <= (`DIVISOR / 2) - 1;
                rx_div_is_middle <= ~rx_div_is_middle;
                if (rx_div_is_middle) begin
                    rx_shifter <= rx_shifter_next;
                    if (|rx_ctr) begin
                        rx_ctr <= rx_ctr - 4'h1;
                    end
                    if (rxd_sync) begin
                        rx_in_break <= 1'b0;
                    end
                    if (rx_ctr == 4'hE) begin
                        // Start bit still set in middle of bit?
                        if (rxd_sync) begin
                            rx_in_char <= 1'b0;
                        end
                    end
                    if (rx_ctr == 4'h5) begin
                        // Stop bit set? If so, valid RX char.
                        if (rx_in_char && rxd_sync) begin
                            rx_strobe <= 1'b1;
                        end
                        rx_in_char <= 1'b0;
                    end
                    if (rx_ctr == 4'h1) begin
                        if (rx_in_break && ~rxd_sync) begin
                            rx_break <= 1'b1;
                            // Don't clear rx_in_break; leave that set until
                            // we see the RX line set high
                        end
                    end
                end
            end else begin
                rx_div <= rx_div - 8'h1;
            end
        end
    end

    reg [8:0] tx_div = 9'h0;
    wire tx_tick = ~|tx_div;
    reg tx_buf = 1'b1;
    assign txd = tx_buf;
    reg [8:0] tx_shifter = 9'h1ff;
    reg [3:0] tx_ctr = 4'h0;
    wire tx_is_idle = ~|tx_ctr;

    always @(posedge clk) begin
        if (tx_is_idle) begin
            tx_idle <= 1'b1; // FIXME: Make this the initialization value somehow
            if (tx_load) begin
                tx_div <= 9'h0;
                tx_shifter <= {tx_data, 1'b0};
                tx_ctr <= 4'hb;
                tx_idle <= 1'b0;
            end
        end else begin
            if (tx_div == 1 && tx_ctr == 1) begin
                tx_idle <= 1'b1;
            end
            if (tx_tick) begin
                tx_div <= `DIVISOR - 1;
                tx_buf <= tx_shifter[0];
                tx_shifter <= {1'b1, tx_shifter[8:1]};
                tx_ctr <= tx_ctr - 4'h1;
            end else begin
                tx_div <= tx_div - 9'h1;
            end
        end
    end
endmodule
