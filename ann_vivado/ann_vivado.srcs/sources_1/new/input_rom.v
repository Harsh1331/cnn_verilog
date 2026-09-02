module input_rom (
    input wire clk,
    input wire [9:0] addr, // 0 to 1023 for a 32x32 image stream
    output reg signed [15:0] pixel_out
);
    // Strict 0-indexed 1024-word ROM array
    reg signed [15:0] rom [0:1023];

    initial begin
        $readmemh("rom.mem", rom);
    end

    always @(posedge clk) begin
        pixel_out <= rom[addr];
    end
endmodule