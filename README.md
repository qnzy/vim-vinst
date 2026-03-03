# vim-vinst

Verilog interface yank and paste for Vim — inspired by the instantiation
and testbench features of Emacs VHDL-mode.

Navigate to any module definition, yank its interface, then paste it as an
instantiation, a signal declaration block, or a full testbench skeleton —
anywhere in any buffer.

## Requirements

- Vim compiled with `+python3`  
  Check with `:echo has('python3')`. If it returns `0`, install `vim-nox` or
  `vim-gtk3` instead of the default `vim` package.
- Python 3.9+

No other dependencies. No external tools required.

## Installation

**vim-plug**
```vim
Plug 'yourname/vim-vinst'
```

**Vundle**
```vim
Plugin 'yourname/vim-vinst'
```

**Pathogen**
```bash
cd ~/.vim/bundle && git clone https://github.com/yourname/vim-vinst
```

**Vim 8+ native packages**
```bash
cd ~/.vim/pack/plugins/start && git clone https://github.com/yourname/vim-vinst
```

**Manual**
```bash
cp plugin/vim-vinst.vim ~/.vim/plugin/
```

## Usage

### Typical workflow

**1. Yank a module interface**

Open any `.v` file containing a module definition. Place the cursor anywhere
inside or above the module — on the `module` line, inside the port list, or
even in the module body. Run:

```
:VlogYank
```

The interface is parsed and saved to `/tmp/vlog_yank.json`. A status message
confirms the module name and port count. The yank persists across buffers and
Vim sessions until overwritten.

**2. Paste in another file**

Open or switch to the file where you want to use the module. Position the
cursor on the line *above* where you want the output inserted, then run one
of:

```
:VlogPasteInst   -- module instantiation
:VlogPasteSigs   -- signal declarations
:VlogPasteTB     -- full testbench skeleton
```

### Example

Given this module:

```verilog
module fifo #(
    parameter WIDTH = 8,
    parameter DEPTH = 16
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire [WIDTH-1:0]  din,
    input  wire              wr_en,
    output wire [WIDTH-1:0]  dout,
    output wire              full,
    output wire              empty
);
```

`:VlogPasteInst` produces:

```verilog
fifo #(
    .WIDTH  (8),
    .DEPTH  (16)
) u_fifo (
    .clk    (clk),
    .rst_n  (rst_n),
    .din    (din),
    .wr_en  (wr_en),
    .dout   (dout),
    .full   (full),
    .empty  (empty)
);
```

`:VlogPasteSigs` produces:

```verilog
wire              clk;
wire              rst_n;
wire [WIDTH-1:0]  din;
wire              wr_en;
wire [WIDTH-1:0]  dout;
wire              full;
wire              empty;
```

`:VlogPasteTB` produces:

```verilog
`timescale 1ns/1ps

module tb_fifo;

    reg  clk;
    reg  rst_n;

    wire [WIDTH-1:0]  din;
    wire              wr_en;
    wire [WIDTH-1:0]  dout;
    wire              full;
    wire              empty;

    // 100 MHz clock
    localparam CLK_PERIOD = 10;
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

fifo #(
    .WIDTH  (8),
    .DEPTH  (16)
) u_fifo (
    ...
);

    initial begin
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // TODO: add stimulus here

        $finish;
    end

endmodule
```

## Commands

| Command          | Description                                         |
|------------------|-----------------------------------------------------|
| `:VlogYank`      | Parse module under cursor, store interface          |
| `:VlogPasteInst` | Paste instantiation below cursor                    |
| `:VlogPasteSigs` | Paste `wire` signal declarations below cursor       |
| `:VlogPasteTB`   | Paste testbench skeleton below cursor               |

## Keybindings

Default bindings are under `<localleader>v`, active only in `.v` files.
Set your local leader in `.vimrc` if you haven't already:

```vim
let maplocalleader = ','
```

| Mapping             | Command           |
|---------------------|-------------------|
| `<localleader>vy`   | `:VlogYank`       |
| `<localleader>vi`   | `:VlogPasteInst`  |
| `<localleader>vs`   | `:VlogPasteSigs`  |
| `<localleader>vt`   | `:VlogPasteTB`    |

Disable all bindings:
```vim
let g:vim_vinst_no_mappings = 1
```

## Behaviour notes

**Cursor position for VlogYank**  
The plugin searches backwards from the cursor for the nearest `module`
keyword. You can be anywhere inside the module — on the header, in the port
list, or deep in the body.

**Multiple modules in one file**  
Supported. The search finds the module that contains the cursor, not the
first one in the file.

**`ifdef` / `endif` blocks in port lists**  
Preserved verbatim in all paste outputs. The preprocessor state is mirrored
exactly, so the instantiation and the definition go through the same
conditionals.

**Parameters**  
Included in the instantiation `#(...)` block with their default values.
Edit the values after pasting as needed.

**Testbench clock and reset**  
`clk` and `rst_n` are always declared as `reg` and driven procedurally.
If the module exposes a port named `clk` or `rst_n`, the corresponding
`wire` declaration is suppressed to avoid a collision. The reset cycle is
always active-low. For modules with a differently named clock, add a
one-line alias after pasting:

```verilog
assign sys_clk = clk;
```

**Yank persistence**  
Stored in `/tmp/vlog_yank.json`. Survives buffer switches and Vim restarts.
Overwritten each time `:VlogYank` runs.

## Supported Verilog / SystemVerilog

- Verilog-2001/2005 ANSI port style
- SystemVerilog modules using `logic` ports (the common case)
- Multi-dimensional packed types: `logic [3:0][7:0]`
- Parameters with `integer`, `real`, `string` type keywords
- Inline `ifdef` / `ifndef` / `else` / `endif` blocks, including nested

Not supported:
- Non-ANSI (pre-2001) port declarations
- SystemVerilog interfaces and modports (`axi_if.master axi`)
- Package imports in the module header (`import pkg::*;`)
- Parameterised types (`parameter type T = logic [7:0]`)

## Running tests

```bash
pip install pytest
python -m pytest tests/ -v
```
