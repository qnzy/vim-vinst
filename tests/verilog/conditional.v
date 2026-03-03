// Module with ifdef ports
module conditional #(
    parameter WIDTH = 8
) (
    input  wire              clk,
    input  wire              rst_n,
`ifdef DEBUG
    output wire              dbg_valid,
    output wire [7:0]        dbg_data,
`endif
    input  wire [WIDTH-1:0]  din,
    output reg  [WIDTH-1:0]  dout
);

endmodule
