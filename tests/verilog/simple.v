// Simple module - basic ANSI style
module simple (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  data_in,
    output reg  [7:0]  data_out,
    output wire        valid
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out <= 8'h00;
        end else begin
            data_out <= data_in;
        end
    end

endmodule
