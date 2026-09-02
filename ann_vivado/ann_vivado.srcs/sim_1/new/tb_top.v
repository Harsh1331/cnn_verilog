module tb_top;
    reg clk;
    reg rst;
    wire signed [15:0] ch1_result;
    wire signed [15:0] ch2_result;
    wire pool_valid;

    // File handles for export
    integer file_ch1, file_ch2;
    integer valid_count;

    // Instantiate Top Module
    top_module uut (
        .clk(clk),
        .rst(rst),
        .ch1_result(ch1_result),
        .ch2_result(ch2_result),
        .pool_valid(pool_valid)
    );

    // 100MHz Clock Generation (10ns period)
    always #5 clk = ~clk;

    initial begin
        // Open local text files for writing
        file_ch1 = $fopen("hw_output_ch1.txt", "w");
        file_ch2 = $fopen("hw_output_ch2.txt", "w");
        
        // Strict 0-indexed tracker for the expected 15x15 pooled frame
        valid_count = 0; 

        // Reset sequence
        clk = 0;
        rst = 1;
        #20;
        rst = 0;

        // Wait until exactly 225 pooled pixels are exported
        wait(valid_count == 225);
        
        // Brief buffer cycle before termination
        #100;
        $fclose(file_ch1);
        $fclose(file_ch2);
        $display("Simulation Complete: All valid pixels exported successfully.");
        $finish;
    end

    // File writing triggered ONLY by the pool_valid flag
    always @(posedge clk) begin
        if (pool_valid && !rst) begin
            // Format output as 4-character uppercase Hex for Q8.8 data
            $fdisplay(file_ch1, "%04X", ch1_result & 16'hFFFF);
            $fdisplay(file_ch2, "%04X", ch2_result & 16'hFFFF);
            valid_count = valid_count + 1;
        end
    end
endmodule