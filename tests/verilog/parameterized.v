// Module with parameters
module parameterized #(
    parameter WIDTH  = 8,
    parameter DEPTH  = 16,
    parameter SIGNED = 0
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire [WIDTH-1:0]  din,
    output reg  [WIDTH-1:0]  dout,
    output wire              full,
    output wire              empty
);

endmodule
