// Complex module - stress test
module complex #(
    parameter integer WIDTH    = 16,
    parameter         DEPTH    = 256,
    parameter real    FREQ     = 100.0,
    parameter         STR_PARAM = "hello"
) (
    // Clock and reset
    input  wire                  clk,
    input  wire                  rst_n,

    // Data interface
    input  wire [WIDTH-1:0]      data_in,
    input  wire                  data_valid,
    output wire [WIDTH-1:0]      data_out,
    output wire                  data_ready,

`ifdef FEATURE_A
    // Feature A ports
    input  wire                  feat_a_en,
    output wire [3:0]            feat_a_status,
`ifdef FEATURE_A_EXT
    output wire                  feat_a_ext_out,
`endif
`endif

    // AXI-lite subordinate
    input  wire [31:0]           axil_awaddr,
    input  wire                  axil_awvalid,
    output wire                  axil_awready,
    input  wire [31:0]           axil_wdata,
    input  wire [3:0]            axil_wstrb,
    input  wire                  axil_wvalid,
    output wire                  axil_wready,
    output wire [1:0]            axil_bresp,
    output wire                  axil_bvalid,
    input  wire                  axil_bready
);

endmodule
