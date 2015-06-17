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

module hdmi_tester_sim;
    // Inputs
    reg clk50;
    // Outputs
    wire [7:0] leds;
    wire txd;
    // Bidirs
    wire hdmi_scl;
    wire hdmi_sda;

    reg hdmi_sda_out;
    reg hdmi_scl_out;
    buf(weak1, strong0) buf_scl(hdmi_scl, hdmi_scl_out);
    buf(weak1, strong0) buf_sda(hdmi_sda, hdmi_sda_out);

    reg tb_ack;
    reg [7:0] tb_val;

    // Instantiate the Unit Under Test (UUT)
    hdmi_tester uut(
        .clk50(clk50), 
        .hdmi_scl_bus(hdmi_scl), 
        .hdmi_sda_bus(hdmi_sda), 
        .leds(leds),
        // FIXME: We need to inject some stimulus here, not loop it back.
        .rxd(txd),
        .txd(txd)
    );

`define I2C_DELAY 2000

    task i2c_start;
        begin
            // Following is for repeated start,
            // but doesn't harm first start except for a delay
            #`I2C_DELAY;
            hdmi_sda_out = 1;
            #`I2C_DELAY;
            hdmi_scl_out = 1;
            #`I2C_DELAY;

            hdmi_sda_out = 0;
            #`I2C_DELAY;
            hdmi_scl_out = 0;
            #`I2C_DELAY;
        end
    endtask

    task i2c_stop;
        begin
            hdmi_sda_out = 0;
            #`I2C_DELAY;
            hdmi_scl_out = 1;
            #`I2C_DELAY;
            #`I2C_DELAY;
            hdmi_sda_out = 1;
            #`I2C_DELAY;
        end
    endtask

    task i2c_bit_out(input val);
        begin
            hdmi_sda_out = val;
            #`I2C_DELAY;
            hdmi_scl_out = 1;
            #`I2C_DELAY;
            #`I2C_DELAY;
            hdmi_scl_out = 0;
            #`I2C_DELAY;
        end
    endtask

    task i2c_bit_in(output val);
        begin
            hdmi_sda_out = 1;
            #`I2C_DELAY;
            hdmi_scl_out = 1;
            val = hdmi_sda;
            #`I2C_DELAY;
            #`I2C_DELAY;
            hdmi_scl_out = 0;
            #`I2C_DELAY;
        end
    endtask

    task i2c_byte_out(input [7:0] val, output ack);
        reg [3:0] i;
        begin
            for (i = 0; i < 8; i = i +1) begin
                i2c_bit_out(val[7]);
                val = {val[6:0], 1'b1};
            end
            i2c_bit_in(ack);
        end
    endtask

    task i2c_byte_in(output [7:0] val, input ack);
        reg [3:0] i;
        reg bval;
        begin
            for (i = 0; i < 8; i = i +1) begin
                i2c_bit_in(bval);
                val = {val[6:0], bval};
            end
            i2c_bit_out(ack);
        end
    endtask

    reg [4:0] i;
    initial begin
        // Initialize Inputs
        clk50 = 0;
        hdmi_scl_out = 1;
        hdmi_sda_out = 1;

        // Wait 100 ns for global reset to finish
        #100;

        i2c_start();
        i2c_byte_out(8'hA0, tb_ack);
        i2c_byte_out(8'h00, tb_ack);
        i2c_start();
        i2c_byte_out(8'hA1, tb_ack);
        for (i = 0; i < 16; i = i +1) begin
            i2c_byte_in(tb_val, 1'b0);
            $display("EEPROM byte %2d 0x%02x\n", i, tb_val);
        end
        i2c_stop();

        $finish;
    end
    
    always begin
        #20;
        clk50 = 1;
        #20;
        clk50 = 0;
    end
endmodule
