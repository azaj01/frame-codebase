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

`ifndef RADIANT
`include "modules/camera/crop.sv"
`include "modules/camera/debayer.sv"
`include "modules/camera/gamma_correction.sv"
`include "modules/camera/image_buffer.sv"
`include "modules/camera/jpeg/jpeg.sv"
`include "modules/camera/metering.sv"
`include "modules/camera/spi_registers.sv"
`endif

module camera (
    input logic global_reset_n_in,
    
    input logic spi_clock_in, // 72MHz
    input logic spi_reset_n_in,

    input logic pixel_clock_in, // 36MHz
    input logic pixel_reset_n_in,

    input logic jpeg_buffer_clock_in, // 78MHz
    input logic jpeg_buffer_reset_n_in,

    input logic jpeg_slow_clock_in, // 18MHz or 12 MHz
    input logic jpeg_slow_reset_n_in,

`ifndef NO_MIPI_IP_SIM
    inout wire mipi_clock_p_in,
    inout wire mipi_clock_n_in,
    inout wire mipi_data_p_in,
    inout wire mipi_data_n_in,
`else
    input logic byte_to_pixel_frame_valid,
    input logic byte_to_pixel_line_valid,
    input logic [9:0] byte_to_pixel_data,
`endif // NO_MIPI_IP_SIM

    // SPI interface
    input logic [7:0] opcode_in,
    input logic opcode_valid_in,
    input logic [7:0] operand_in,
    input logic operand_read,
    input logic operand_valid_in,
    input logic [31:0] rd_operand_count_in,
    input logic [31:0] wr_operand_count_in,
    output logic [7:0] response_out
);

logic start_capture_spi_clock_domain;
logic start_capture_pixel_clock_domain;

logic [9:0] resolution;
logic [2:0] compression_factor;
logic power_save_enable;
logic gamma_bypass;

logic image_buffer_ready;               // Ready bit, high when compression finished
logic [7:0] image_buffer_data;          // Read out data
logic [15:0] image_buffer_address;      // Read address
logic image_buffer_address_valid;       // qualifier
logic [15:0] final_image_address;       // image address JPEG -> Image buffer
logic [7:0] red_center_metering;
logic [7:0] green_center_metering;
logic [7:0] blue_center_metering;
logic [7:0] red_average_metering;
logic [7:0] green_average_metering;
logic [7:0] blue_average_metering;

spi_registers spi_registers (
    .clock_in(spi_clock_in),
    .reset_n_in(spi_reset_n_in),

    // SPI interface
    .opcode_in(opcode_in),
    .opcode_valid_in(opcode_valid_in),
    .operand_in(operand_in),
    .rd_operand_count_in(rd_operand_count_in),
    .wr_operand_count_in(wr_operand_count_in),
    .operand_read(operand_read),
    .operand_valid_in(operand_valid_in),
    .response_out(response_out),

    .start_capture_out(start_capture_spi_clock_domain),
    .resolution_out(resolution),
    .compression_factor_out(compression_factor),
    .power_save_enable_out(power_save_enable),
    .gamma_bypass_out(gamma_bypass),

    .image_ready_in(image_buffer_ready),
    .final_image_address(final_image_address),
    .image_data_in(image_buffer_data),
    .image_address_out(image_buffer_address),
    .image_address_valid(image_buffer_address_valid),

    .red_center_metering_in(red_center_metering),
    .green_center_metering_in(green_center_metering),
    .blue_center_metering_in(blue_center_metering),
    .red_average_metering_in(red_average_metering),
    .green_average_metering_in(green_average_metering),
    .blue_average_metering_in(blue_average_metering)
);

// SPI to display pulse sync
psync1 psync1_operand_valid_in (
        .in             (start_capture_spi_clock_domain),
        .in_clk         (~spi_clock_in),
        .in_reset_n     (spi_reset_n_in),
        .out            (start_capture_pixel_clock_domain),
        .out_clk        (pixel_clock_in),
        .out_reset_n    (pixel_reset_n_in)
);

`ifndef NO_MIPI_IP_SIM
logic [9:0] byte_to_pixel_data;
logic byte_to_pixel_line_valid;
logic byte_to_pixel_frame_valid;

logic mipi_byte_clock;
logic mipi_byte_reset_n;

logic mipi_payload_enable_metastable /* synthesis syn_keep=1 nomerge=""*/;
logic mipi_payload_enable /* synthesis syn_keep=1 nomerge=""*/;

logic [7:0] mipi_payload_metastable /* synthesis syn_keep=1 nomerge=""*/;
logic [7:0] mipi_payload /* synthesis syn_keep=1 nomerge=""*/;

logic mipi_sp_enable_metastable /* synthesis syn_keep=1 nomerge=""*/;
logic mipi_sp_enable /* synthesis syn_keep=1 nomerge=""*/;

logic mipi_lp_av_enable_metastable /* synthesis syn_keep=1 nomerge=""*/;
logic mipi_lp_av_enable /* synthesis syn_keep=1 nomerge=""*/;

logic [15:0] mipi_word_count /* synthesis syn_keep=1 nomerge=""*/;
logic [5:0] mipi_datatype;

reset_sync mipi_byte_clock_reset_sync (
    .clock_in(mipi_byte_clock),
    .async_reset_n_in(global_reset_n_in),
    .sync_reset_n_out(mipi_byte_reset_n)
);

csi2_receiver_ip csi2_receiver_ip (
    .clk_byte_o(),
    .clk_byte_hs_o(mipi_byte_clock),
    .clk_byte_fr_i(mipi_byte_clock),
    .reset_n_i(global_reset_n_in),
    .reset_byte_fr_n_i(mipi_byte_reset_n),
    .clk_p_io(mipi_clock_p_in),
    .clk_n_io(mipi_clock_n_in),
    .d_p_io(mipi_data_p_in),
    .d_n_io(mipi_data_n_in),
    .payload_en_o(mipi_payload_enable_metastable),
    .payload_o(mipi_payload_metastable),
    .tx_rdy_i(1'b1),
    .pd_dphy_i(~global_reset_n_in | power_save_enable),
    .dt_o(mipi_datatype),
    .wc_o(mipi_word_count),
    .ref_dt_i(6'h2B),
    .sp_en_o(mipi_sp_enable_metastable),
    .lp_en_o(),
    .lp_av_en_o(mipi_lp_av_enable_metastable)
);

always @(posedge mipi_byte_clock or negedge mipi_byte_reset_n) begin
    if (!mipi_byte_reset_n) begin
        mipi_payload_enable <= 0;
        mipi_payload <= 0;
        mipi_sp_enable <= 0;
        mipi_lp_av_enable <= 0;
    end

    else begin
        mipi_payload_enable <= mipi_payload_enable_metastable;
        mipi_payload <= mipi_payload_metastable;
        mipi_sp_enable <= mipi_sp_enable_metastable;
        mipi_lp_av_enable <= mipi_lp_av_enable_metastable;
    end
end

byte_to_pixel_ip byte_to_pixel_ip (
    .reset_byte_n_i(mipi_byte_reset_n),
    .clk_byte_i(mipi_byte_clock),
    .sp_en_i(mipi_sp_enable),
    .dt_i(mipi_datatype),
    .lp_av_en_i(mipi_lp_av_enable),
    .payload_en_i(mipi_payload_enable),
    .payload_i(mipi_payload),
    .wc_i(mipi_word_count),
    .reset_pixel_n_i(pixel_reset_n_in),
    .clk_pixel_i(pixel_clock_in),
    .fv_o(byte_to_pixel_frame_valid),
    .lv_o(byte_to_pixel_line_valid),
    .pd_o(byte_to_pixel_data)
);
`endif // NO_MIPI_IP_SIM

logic [9:0] cropped_pixel_data;
logic cropped_line_valid;
logic cropped_frame_valid;

logic [9:0] resolution_crop_start;
logic [9:0] resolution_crop_end;

`ifndef SENSOR_X_SIZE
`define SENSOR_X_SIZE 722
`endif

always_comb resolution_crop_start = (`SENSOR_X_SIZE - resolution - 2) >> 1;
always_comb resolution_crop_end = resolution_crop_start + resolution + 2;

always @(negedge spi_clock_in) if (start_capture_spi_clock_domain) 
    assert (resolution <= `SENSOR_X_SIZE - 2) else $fatal(1, "Incorrect sensor vs. image dimensions!");

crop crop (
    .clock_in(pixel_clock_in),
    .reset_n_in(pixel_reset_n_in),

    .pixel_data_in(byte_to_pixel_data),
    .line_valid_in(byte_to_pixel_line_valid),
    .frame_valid_in(byte_to_pixel_frame_valid),

    .x_crop_start(resolution_crop_start),
    .x_crop_end(resolution_crop_end),
    .y_crop_start(resolution_crop_start),
    .y_crop_end(resolution_crop_end),

    .pixel_data_out(cropped_pixel_data),
    .line_valid_out(cropped_line_valid),
    .frame_valid_out(cropped_frame_valid)
);

logic [9:0] debayered_red_data;
logic [9:0] debayered_green_data;
logic [9:0] debayered_blue_data;
logic debayered_line_valid;
logic debayered_frame_valid;

debayer debayer (
    .pixel_clock_in(pixel_clock_in),
    .pixel_reset_n_in(pixel_reset_n_in),

    .x_crop_start_lsb(resolution_crop_start[0]),
    .y_crop_start_lsb(resolution_crop_start[0]),

    .bayer_data_in(cropped_pixel_data),
    .line_valid_in(cropped_line_valid),
    .frame_valid_in(cropped_frame_valid),

    .red_data_out(debayered_red_data),
    .green_data_out(debayered_green_data),
    .blue_data_out(debayered_blue_data),
    .line_valid_out(debayered_line_valid),
    .frame_valid_out(debayered_frame_valid)
);

logic center_metering_ready_pixel_clock_domain;
logic center_metering_ready_metastable;
logic center_metering_ready_spi_clock_domain;
logic average_metering_ready_pixel_clock_domain;
logic average_metering_ready_metastable;
logic average_metering_ready_spi_clock_domain;

metering #(.SIZE(128)) center_metering (
    .clock_in(pixel_clock_in),
    .reset_n_in(pixel_reset_n_in),

    .red_data_in(debayered_red_data),
    .green_data_in(debayered_green_data),
    .blue_data_in(debayered_blue_data),
    .line_valid_in(debayered_line_valid),
    .frame_valid_in(debayered_frame_valid),

    .red_metering_out(red_center_metering),
    .green_metering_out(green_center_metering),
    .blue_metering_out(blue_center_metering),
    .metering_ready_out(center_metering_ready_pixel_clock_domain)
);

metering #(.SIZE(512)) average_metering (
    .clock_in(pixel_clock_in),
    .reset_n_in(pixel_reset_n_in),

    .red_data_in(debayered_red_data),
    .green_data_in(debayered_green_data),
    .blue_data_in(debayered_blue_data),
    .line_valid_in(debayered_line_valid),
    .frame_valid_in(debayered_frame_valid),

    .red_metering_out(red_average_metering),
    .green_metering_out(green_average_metering),
    .blue_metering_out(blue_average_metering),
    .metering_ready_out(average_metering_ready_pixel_clock_domain)
);

always @(posedge spi_clock_in) begin : metering_cdc
    center_metering_ready_metastable <= center_metering_ready_pixel_clock_domain;
    center_metering_ready_spi_clock_domain <= center_metering_ready_metastable;
    average_metering_ready_metastable <= average_metering_ready_pixel_clock_domain;
    average_metering_ready_spi_clock_domain <= average_metering_ready_metastable;
end


logic [7:0] gamma_corrected_red_data;
logic [7:0] gamma_corrected_green_data;
logic [7:0] gamma_corrected_blue_data;
logic gamma_corrected_line_valid;
logic gamma_corrected_frame_valid;

gamma_correction gamma_correction (
    .clock_in(pixel_clock_in),

    .red_data_in(debayered_red_data[9:2]),
    .green_data_in(debayered_green_data[9:2]),
    .blue_data_in(debayered_blue_data[9:2]),
    .line_valid_in(debayered_line_valid),
    .frame_valid_in(debayered_frame_valid),

    .red_data_out(gamma_corrected_red_data),
    .green_data_out(gamma_corrected_green_data),
    .blue_data_out(gamma_corrected_blue_data),
    .line_valid_out(gamma_corrected_line_valid),
    .frame_valid_out(gamma_corrected_frame_valid)
);

logic [31:0] final_image_data;          // image data JPEG -> Image buffer
logic final_image_data_valid;           // qualifier
logic final_image_ready;                // Ready bit, high when compression finished

jpeg_encoder jpeg_encoder (
    .pixel_clock_in(pixel_clock_in),
    .pixel_reset_n_in(pixel_reset_n_in),

    .jpeg_fast_clock_in(jpeg_buffer_clock_in),
    .jpeg_fast_reset_n_in(jpeg_buffer_reset_n_in),

    .jpeg_slow_clock_in(jpeg_slow_clock_in),
    .jpeg_slow_reset_n_in(jpeg_slow_reset_n_in),

    .red_data_in(gamma_bypass ? debayered_red_data : {gamma_corrected_red_data, 2'b0}),
    .green_data_in(gamma_bypass ? debayered_green_data : {gamma_corrected_green_data, 2'b0}),
    .blue_data_in(gamma_bypass ? debayered_blue_data : {gamma_corrected_blue_data, 2'b0}),
    .line_valid_in(gamma_bypass ? debayered_line_valid : gamma_corrected_line_valid),
    .frame_valid_in(gamma_bypass ? debayered_frame_valid : gamma_corrected_frame_valid),

    .start_capture_in(start_capture_pixel_clock_domain),
    .x_size_in(resolution),
    .y_size_in(resolution),
    .qf_select_in(compression_factor),

    .data_out(final_image_data),
    .data_valid_out(final_image_data_valid),
    .address_out(final_image_address),
    .image_valid_out(final_image_ready)
);

always_comb image_buffer_ready = final_image_ready;

image_buffer image_buffer (
    .clock_in(jpeg_slow_clock_in),

    .write_address_in(final_image_address),
    .read_address_in(image_buffer_address),
    .read_address_valid_in(image_buffer_address_valid),

    .write_data_in(final_image_data),
    .read_data_out(image_buffer_data),
    .write_read_n_in(final_image_data_valid)
);

endmodule
