/*
 * This file is a part of: https://github.com/brilliantlabsAR/frame-codebase
 *
 * Authored by: Rohit Rathnam / Silicon Witchery AB (rohit@siliconwitchery.com)
 *              Raj Nakarja / Brilliant Labs Limited (raj@brilliant.xyz)
 *              Robert Metchev / Chips & Scripts (rmetchev@ieee.org) 
 *
 * CERN Open Hardware Licence Version 2 - Permissive
 *
 * Copyright © 2024 Brilliant Labs Limited
 */
 
 module crop (
    input logic clock_in,
    input logic reset_n_in,

    input logic [9:0] pixel_data_in,
    input logic line_valid_in,
    input logic frame_valid_in,

    input logic [9:0] x_crop_start,
    input logic [9:0] x_crop_end,
    input logic [9:0] y_crop_start,
    input logic [9:0] y_crop_end,

    output logic [9:0] pixel_data_out,
    output logic line_valid_out,
    output logic frame_valid_out
);

// Allows max 1024 x 1024 pixel input
logic [9:0] x_counter;
logic [9:0] y_counter;

logic previous_line_valid;

always_ff @(posedge clock_in) begin

    if(reset_n_in == 0 || frame_valid_in == 0) begin

        line_valid_out <= 0;
        frame_valid_out <= 0;

        x_counter <= 0;
        y_counter <= 0;
        
        previous_line_valid <= 0;

    end
    
    else begin
        
        previous_line_valid <= line_valid_in;

        // Increment counters
        if (line_valid_in) begin
            x_counter <= x_counter + 1;
        end

        else begin
            x_counter <= 0;

            if (previous_line_valid) begin
                y_counter <= y_counter + 1;
            end
        end

        // Output cropped version
        if(line_valid_in &&
           x_counter >= x_crop_start &&
           x_counter < x_crop_end &&
           y_counter >= y_crop_start &&
           y_counter < y_crop_end) begin

            line_valid_out <= 1;
            pixel_data_out <= pixel_data_in;

        end

        else begin
            
            line_valid_out <= 0;
            pixel_data_out <= 0;

        end

        frame_valid_out <= frame_valid_in;

    end
   
end
    
endmodule