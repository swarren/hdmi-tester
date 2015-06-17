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

`define I2C_STATE_IDLE                  0
`define I2C_STATE_I2C_ADDR_RX           1
`define I2C_STATE_I2C_ADDR_TX_ACK       2
`define I2C_STATE_RDATA_TX              3
`define I2C_STATE_RDATA_RX_ACK          4
`define I2C_STATE_REG_ADDR_RX           5
`define I2C_STATE_REG_ADDR_TX_ACK       6
//`define I2C_STATE_WDATA_RX
//`define I2C_STATE_WDATA_TX_ACK
`define I2C_STATE_SEGMENT_RX            7
`define I2C_STATE_SEGMENT_TX_ACK        8
`define I2C_STATE_BITS                  4

module i2c_eeprom(
    input wire clk,
    input wire enable,
    inout wire scl_wire,
    inout wire sda_wire,
    output wire [14:0] edid_addr,
    input wire [7:0] edid_data
);
`define SYNC_BITS 2
    reg [`SYNC_BITS:0] scl_r;
    reg [`SYNC_BITS:0] sda_r;

    wire scl = scl_r[`SYNC_BITS - 1];
    wire sda = sda_r[`SYNC_BITS - 1];

    wire sda_prev = sda_r[`SYNC_BITS];
    wire scl_prev = scl_r[`SYNC_BITS];

    always @(posedge clk) begin
        scl_r <= {scl_r[`SYNC_BITS-1:0], scl_wire};
        sda_r <= {sda_r[`SYNC_BITS-1:0], sda_wire};
    end

    wire scl_rising = (scl == 1) && (scl_prev == 0);
    wire sda_rising = (sda == 1) && (sda_prev == 0);

    wire scl_falling = (scl == 0) && (scl_prev == 1);
    wire sda_falling = (sda == 0) && (sda_prev == 1);

    wire start_detected = (scl == 1) && sda_falling;
    wire stop_detected = (scl == 1) && sda_rising;

    reg [8:0] i2c_tx_data = 9'h1FF;
    assign sda_wire = i2c_tx_data[8] ? 1'bZ : 1'b0;

    reg [7:0] i2c_rx_data;
    wire [7:0] i2c_rx_data_next = {i2c_rx_data[6:0], sda};

    reg [`I2C_STATE_BITS - 1:0] i2c_state = `I2C_STATE_IDLE;
    reg [3:0] i2c_state_ctr;

    reg [7:0] edid_addr_lsb;
    reg [6:0] edid_addr_segment;
    assign edid_addr = {edid_addr_segment, edid_addr_lsb};

    always @(posedge clk) begin
        if (scl_falling) begin
            i2c_tx_data <= {i2c_tx_data[7:0], 1'b1};
        end

        if (scl_rising) begin
            i2c_rx_data <= i2c_rx_data_next;

            case (i2c_state)
                `I2C_STATE_IDLE: begin
                end
                `I2C_STATE_I2C_ADDR_RX: begin
                    if (i2c_state_ctr == 4'h7) begin
                        case (i2c_rx_data_next)
                            8'ha1, 8'ha0, 8'h60: begin
                                i2c_state <= `I2C_STATE_I2C_ADDR_TX_ACK;
                                i2c_tx_data[7:0] <= 8'h7F;
                            end
                            default: begin
                                i2c_state <= `I2C_STATE_IDLE;
                                i2c_tx_data[7:0] <= 8'hFF;
                                edid_addr_segment <= 7'h00;
                            end
                        endcase
                    end
                end
                `I2C_STATE_I2C_ADDR_TX_ACK: begin
                    case (i2c_rx_data)
                        8'ha1: begin
                            i2c_state <= `I2C_STATE_RDATA_TX;
                            i2c_tx_data[7:0] <= edid_data;
                            edid_addr_lsb <= edid_addr_lsb + 8'h1;
                        end
                        8'ha0: begin
                            i2c_state <= `I2C_STATE_REG_ADDR_RX;
                        end
                        8'h60: begin
                            i2c_state <= `I2C_STATE_SEGMENT_RX;
                        end
                    endcase
                end
                `I2C_STATE_RDATA_TX: begin
                    if (i2c_state_ctr == 4'h7) begin
                        i2c_state <= `I2C_STATE_RDATA_RX_ACK;
                    end
                end
                `I2C_STATE_RDATA_RX_ACK: begin
                    if (sda == 0) begin
                        i2c_state <= `I2C_STATE_RDATA_TX;
                        i2c_tx_data[7:0] <= edid_data;
                        edid_addr_lsb <= edid_addr_lsb + 8'h1;
                    end else begin
                        i2c_state <= `I2C_STATE_IDLE;
                        i2c_tx_data[7:0] <= 8'hFF;
                    end
                end
                `I2C_STATE_REG_ADDR_RX: begin
                    if (i2c_state_ctr == 4'h7) begin
                        edid_addr_lsb <= i2c_rx_data_next;
                        i2c_state <= `I2C_STATE_REG_ADDR_TX_ACK;
                        i2c_tx_data[7:0] <= 8'h7F;
                    end
                end
                `I2C_STATE_REG_ADDR_TX_ACK: begin
                    // FIXME: This should go to I2C_STATE_WDATA_RX for a real EEPROM.
                    // This should be good enough to implement an EEPROM that
                    // refuses (and NAKs) writes.
                    i2c_state <= `I2C_STATE_IDLE;
                    i2c_tx_data[7:0] <= 8'hFF;
                end
                `I2C_STATE_SEGMENT_RX: begin
                    if (i2c_state_ctr == 4'h7) begin
                        edid_addr_segment <= i2c_rx_data_next[6:0];
                        i2c_state <= `I2C_STATE_SEGMENT_TX_ACK;
                        i2c_tx_data[7:0] <= 8'h7F;
                    end
                end
                `I2C_STATE_SEGMENT_TX_ACK: begin
                    i2c_state <= `I2C_STATE_IDLE;
                    i2c_tx_data[7:0] <= 8'hFF;
                end
            endcase
        end

        if (start_detected && enable) begin
            i2c_state <= `I2C_STATE_I2C_ADDR_RX;
            i2c_state_ctr <= 0;
        end else if (scl_rising) begin
            if (i2c_state_ctr == 4'h8) begin
                i2c_state_ctr <= 4'h0;
            end else begin
                i2c_state_ctr <= i2c_state_ctr + 4'h1;
            end
        end

        if (stop_detected) begin
            i2c_state <= `I2C_STATE_IDLE;
            i2c_tx_data[7:0] <= 8'hFF;
            edid_addr_segment <= 7'h00;
        end
    end
endmodule
