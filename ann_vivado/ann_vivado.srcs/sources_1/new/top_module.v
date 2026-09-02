module top_module (
    input wire clk,
    input wire rst,
    output wire signed [15:0] ch1_result,
    output wire signed [15:0] ch2_result,
    output wire pool_valid
);
    wire signed [15:0] stream_data;
    reg [9:0] rom_addr;
    reg frame_start;
    reg [1:0] state; // 0: Idle, 1: Frame Start, 2: Streaming

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rom_addr <= 10'd0;
            frame_start <= 1'b0;
            state <= 2'd0;
        end else begin
            case (state)
                2'd0: begin
                    // Prime the ROM with address 0 first
                    rom_addr <= 10'd0;
                    state <= 2'd1;
                end
                2'd1: begin
                    // Pulse frame_start precisely as ROM[0] is being fetched
                    frame_start <= 1'b1;
                    rom_addr <= 10'd1; // Setup the next address
                    state <= 2'd2;
                end
                2'd2: begin
                    frame_start <= 1'b0;
                    if (rom_addr < 1023) 
                        rom_addr <= rom_addr + 1;
                end
            endcase
        end
    end

    input_rom u_rom (
        .clk(clk),
        .addr(rom_addr),
        .pixel_out(stream_data)
    );

    compute_engine u_core (
        .clk(clk),
        .rst(rst),
        .frame_start(frame_start),
        .pixel_in(stream_data),
        .pool_out_ch1(ch1_result),
        .pool_out_ch2(ch2_result),
        .pool_valid(pool_valid)
    );
endmodule