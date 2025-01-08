/*
 * This file is a part of: https://github.com/brilliantlabsAR/frame-codebase
 *
 * Authored by: Rohit Rathnam / Silicon Witchery AB (rohit@siliconwitchery.com)
 *              Raj Nakarja / Brilliant Labs Limited (raj@brilliant.xyz)
 *              Robert Metchev / Raumzeit Technologies (robert@raumzeit.co)
 *
 * CERN Open Hardware Licence Version 2 - Permissive
 *
 * Copyright © 2024 Brilliant Labs Limited
 */
 
 module spi_registers (
    input logic clock_in,
    input logic reset_n_in,

    // SPI interface
    input logic [7:0] opcode_in,
    input logic opcode_valid_in,
    input logic [7:0] operand_in,
    input logic operand_read,
    input logic operand_valid_in,
    input logic [31:0] rd_operand_count_in,
    input logic [31:0] wr_operand_count_in,
    output logic [7:0] response_out,

    output logic start_capture_out,
    output logic [9:0] resolution_out,
    output logic [2:0] compression_factor_out,
    output logic power_save_enable_out,
    output logic gamma_bypass_out,

    input logic image_ready_in,
    input logic [15:0] final_image_address, // image_total_size_in - 4
    input logic [7:0] image_data_in,
    output logic [15:0] image_address_out,
    output logic image_address_valid,

    input logic [7:0] red_center_metering_in,
    input logic [7:0] green_center_metering_in,
    input logic [7:0] blue_center_metering_in,
    input logic [7:0] red_average_metering_in,
    input logic [7:0] green_average_metering_in,
    input logic [7:0] blue_average_metering_in
);

// register addresses
parameter START_CAPTURE     = 'h20; // WO + reset
parameter BYTES_REMAINING   = 'h21; // RO
parameter IMAGE_DATA        = 'h22; // RO + increment
parameter RESOLUTION        = 'h23; // WO
parameter METERING          = 'h25; // RO
parameter QUALITY_FACTOR    = 'h26; // WO
parameter POWER_SAVE_ENABLE = 'h28; // WO

parameter IMAGE_READY_FLAG  = 'h30; // RO
parameter COMPRESSED_BYTES  = 'h31; // RO 2x
parameter GAMMA_BYPASS      = 'h32; // WO

logic [15:0] image_buffer_total_size;   // final address + 4, sames as bytes available
logic [15:0] bytes_remaining;

always_comb image_buffer_total_size = final_image_address + 4;
assign bytes_remaining = image_buffer_total_size - image_address_out;

always_comb
     case (opcode_in)
         // Bytes available
         BYTES_REMAINING:
         case (rd_operand_count_in)
             0: response_out = bytes_remaining[15:8];
             default: response_out = bytes_remaining[7:0];
         endcase

         // Read data
         IMAGE_DATA: response_out = image_data_in;

         // Metering
         METERING:
         case (rd_operand_count_in)
             0: response_out = red_center_metering_in;
             1: response_out = green_center_metering_in;
             2: response_out = blue_center_metering_in;
             3: response_out = red_average_metering_in;
             4: response_out = green_average_metering_in;
             default: response_out = blue_average_metering_in;
         endcase

         // Image ready flag
         IMAGE_READY_FLAG: response_out = image_ready_in;

         // Image size
         COMPRESSED_BYTES:
         case (rd_operand_count_in)
             0: response_out = final_image_address[7:0];
             1: response_out = final_image_address[15:8];
             default: response_out = 0;
         endcase

         default: response_out = 0;
     endcase


// combinatorial!
always_comb start_capture_out = opcode_valid_in & opcode_in == START_CAPTURE;

// RM - Being extra careful here and putting POWER_SAVE_ENABLE on async reset
always_ff @(negedge clock_in or negedge reset_n_in)
if (reset_n_in == 0)
    power_save_enable_out <= 0; // D-PHY is per default powered up
else if (operand_valid_in & opcode_in==POWER_SAVE_ENABLE)
    power_save_enable_out <= operand_in[0];

always_ff @(negedge clock_in) begin
    
    if (reset_n_in == 0) begin
        resolution_out <= 512;
        compression_factor_out <= 0;
        image_address_valid <= 0;
        gamma_bypass_out <= 0;
    end

    else begin
        image_address_valid <= operand_read & (opcode_in==IMAGE_DATA | opcode_in==COMPRESSED_BYTES | opcode_in==BYTES_REMAINING);

        if (start_capture_out) // Capture command
            image_address_out <= 0;
        else if (operand_read & opcode_in == IMAGE_DATA & image_address_out < image_buffer_total_size)
            // Read data
            // 
            // Note: When operand_read==1, last bit of image buffer data has been put
            // on the SPI bus with the FALLING edge of SPI clock, so now we can update
            // the address, also FALLING edge of SPI clock, and read out the next 
            // image buffer data. 
            // When reading out image buffer data with jpeg clock, the read will take
            // place over floor((jpeg clock freq.)/(spi clock freq.)) cycles, eg. 36MHz/8MHz
            // -> 4 cycles. If there are at least 2 cycles, the timing violation for address 
            // which occurs during SDF simulation can be ignored, since is will occur only 
            // during the fist cycle, and the address shoould be stable in subsequent cycles.
            image_address_out <= image_address_out + 1;

        if (operand_valid_in) begin

            case (opcode_in)

                // Resolution
                RESOLUTION: begin
                    case (wr_operand_count_in)
                        0: resolution_out <= {operand_in[1:0], 8'b0};
                        default: resolution_out <= {resolution_out[9:8], operand_in};
                    endcase
                end

                // Compression factor
                QUALITY_FACTOR: begin
                    compression_factor_out[2:0] <= operand_in[2:0];
                end

                // Bypass Gamma for debug
                GAMMA_BYPASS: begin
                    gamma_bypass_out <= operand_in[0];
                end

            endcase

        end

    end

end

endmodule

