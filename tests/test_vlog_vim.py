"""
tests/test_vlog_vim.py  --  test the pure-Python logic in vlog.vim

We exec the python3 heredoc section directly so there is no separate module
to import -- the plugin is a single file.
"""

import sys, os, re, json, textwrap, tempfile, pytest

# ---------------------------------------------------------------------------
# Bootstrap: exec the Python block out of vlog.vim into our namespace
# ---------------------------------------------------------------------------

_PLUGIN = os.path.join(os.path.dirname(__file__), '..', 'plugin', 'vim-vinst.vim')

def _load_plugin():
    with open(_PLUGIN) as f:
        src = f.read()
    m = re.search(r'python3 << EOF\n(.*?)\nEOF', src, re.DOTALL)
    assert m, "Could not find python3 heredoc in vlog.vim"
    ns = {}
    exec(m.group(1), ns)
    return ns

_ns = _load_plugin()

# pull names into module scope for convenience
parse_module      = _ns['parse_module']
find_module_text  = _ns['find_module_text']
format_inst       = _ns['format_inst']
format_sigs       = _ns['format_sigs']
format_tb         = _ns['format_tb']
ParseError        = _ns['ParseError']

VERILOG_DIR = os.path.join(os.path.dirname(__file__), 'verilog')
def vfile(n): return os.path.join(VERILOG_DIR, n)

def load(name):
    with open(vfile(name)) as f:
        return f.read()

def buf(text):
    return text.splitlines()

# ---------------------------------------------------------------------------
# parse_module
# ---------------------------------------------------------------------------

class TestParseSimple:
    def setup_method(self):
        self.mi = parse_module(load('simple.v'))

    def test_name(self):          assert self.mi['name'] == 'simple'
    def test_no_params(self):     assert not any(p['kind']=='param' for p in self.mi['params'])
    def test_port_count(self):    assert sum(1 for p in self.mi['ports'] if p['kind']=='port') == 5
    def test_port_names(self):
        names = [p['name'] for p in self.mi['ports'] if p['kind']=='port']
        assert names == ['clk','rst_n','data_in','data_out','valid']
    def test_packed_dim(self):
        din = next(p for p in self.mi['ports'] if p.get('name')=='data_in')
        assert '[7:0]' in din['packed']

class TestParseParameterized:
    def setup_method(self):
        self.mi = parse_module(load('parameterized.v'))

    def test_param_count(self):
        assert sum(1 for p in self.mi['params'] if p['kind']=='param') == 3
    def test_defaults(self):
        ps = [p for p in self.mi['params'] if p['kind']=='param']
        assert ps[0]['default'] == '8'
        assert ps[1]['default'] == '16'

class TestParseConditional:
    def setup_method(self):
        self.mi = parse_module(load('conditional.v'))

    def test_all_ports_present(self):
        names = [p['name'] for p in self.mi['ports'] if p['kind']=='port']
        assert 'dbg_valid' in names

    def test_ifdef_markers(self):
        directives = [p['directive'] for p in self.mi['ports'] if p['kind']=='ifdef']
        assert 'ifdef' in directives
        assert 'endif' in directives

    def test_ifdef_symbol(self):
        m = next(p for p in self.mi['ports'] if p['kind']=='ifdef' and p['directive']=='ifdef')
        assert m['symbol'] == 'DEBUG'

    def test_order(self):
        items = self.mi['ports']
        idx_if  = next(i for i,x in enumerate(items) if x['kind']=='ifdef' and x['directive']=='ifdef')
        idx_dbg = next(i for i,x in enumerate(items) if x.get('name')=='dbg_valid')
        idx_ei  = next(i for i,x in enumerate(items) if x['kind']=='ifdef' and x['directive']=='endif')
        assert idx_if < idx_dbg < idx_ei

class TestParseCompact:
    def test_single_line(self):
        mi = parse_module(load('compact.v'))
        names = [p['name'] for p in mi['ports'] if p['kind']=='port']
        assert names == ['clk','rst_n','q']

class TestParseErrors:
    def test_no_module(self):
        with pytest.raises(ParseError):
            parse_module("assign a = b;")
    def test_unterminated(self):
        with pytest.raises(ParseError):
            parse_module("module foo (input wire clk")

# ---------------------------------------------------------------------------
# find_module_text
# ---------------------------------------------------------------------------

SIMPLE_BUF = buf("""
module simple (
    input  wire clk,
    input  wire rst_n,
    output wire q
);

    always @(posedge clk) q <= 0;
endmodule
""")

TWO_BUF = buf("""
module first (input wire a, output wire b);
endmodule

module second (input wire clk, output wire q);
endmodule
""")

class TestFindModuleText:
    def test_cursor_on_module_line(self):
        t = find_module_text(SIMPLE_BUF, 1)
        assert 'module simple' in t

    def test_cursor_in_port_list(self):
        t = find_module_text(SIMPLE_BUF, 3)
        assert 'module simple' in t

    def test_cursor_in_body(self):
        t = find_module_text(SIMPLE_BUF, 8)
        assert 'module simple' in t

    def test_two_modules_first(self):
        t = find_module_text(TWO_BUF, 1)
        assert 'first' in t and 'second' not in t

    def test_two_modules_second(self):
        t = find_module_text(TWO_BUF, 4)
        assert 'second' in t

    def test_no_module_above(self):
        with pytest.raises(ParseError):
            find_module_text(buf("wire x;\nassign x=1;"), 1)

    def test_roundtrip(self):
        t  = find_module_text(SIMPLE_BUF, 3)
        mi = parse_module(t)
        assert mi['name'] == 'simple'

# ---------------------------------------------------------------------------
# format_inst
# ---------------------------------------------------------------------------

class TestFormatInstSimple:
    def setup_method(self):
        self.mi    = parse_module(load('simple.v'))
        self.lines = format_inst(self.mi)
        self.text  = '\n'.join(self.lines)

    def test_first_line(self):   assert self.lines[0]  == 'simple u_simple ('
    def test_last_line(self):    assert self.lines[-1] == ');'
    def test_all_ports(self):
        for n in ('clk','rst_n','data_in','data_out','valid'):
            assert f'.{n}' in self.text
    def test_self_connect(self):
        assert '.clk' in self.text and '(clk)' in self.text
    def test_last_no_comma(self):
        vline = next(l for l in self.lines if '.valid' in l)
        assert not vline.rstrip().endswith(',')
    def test_others_have_comma(self):
        cline = next(l for l in self.lines if '.clk' in l)
        assert cline.rstrip().endswith(',')
    def test_no_param_block(self):
        assert '#(' not in self.text

class TestFormatInstParameterized:
    def setup_method(self):
        self.mi    = parse_module(load('parameterized.v'))
        self.lines = format_inst(self.mi)
        self.text  = '\n'.join(self.lines)

    def test_param_block(self):      assert '#(' in self.text
    def test_defaults(self):
        assert '.WIDTH' in self.text and '(8)'  in self.text
        assert '.DEPTH' in self.text and '(16)' in self.text
    def test_last_param_no_comma(self):
        sline = next(l for l in self.lines if '.SIGNED' in l)
        assert not sline.rstrip().endswith(',')

class TestFormatInstConditional:
    def setup_method(self):
        self.mi    = parse_module(load('conditional.v'))
        self.lines = format_inst(self.mi)
        self.text  = '\n'.join(self.lines)

    def test_ifdef_preserved(self):   assert '`ifdef DEBUG' in self.text
    def test_endif_preserved(self):   assert '`endif'       in self.text
    def test_ifdef_port_present(self): assert '.dbg_valid'  in self.text
    def test_order(self):
        ii = next(i for i,l in enumerate(self.lines) if '`ifdef' in l)
        id = next(i for i,l in enumerate(self.lines) if '.dbg_valid' in l)
        ie = next(i for i,l in enumerate(self.lines) if '`endif' in l)
        assert ii < id < ie

# ---------------------------------------------------------------------------
# JSON round-trip (yank file serialisation)
# ---------------------------------------------------------------------------

class TestJSONRoundtrip:
    def test_simple(self):
        mi  = parse_module(load('simple.v'))
        txt = json.dumps(mi)
        mi2 = json.loads(txt)
        assert mi2['name'] == 'simple'
        assert mi2['ports'] == mi['ports']

    def test_conditional(self):
        mi  = parse_module(load('conditional.v'))
        mi2 = json.loads(json.dumps(mi))
        inst1 = format_inst(mi)
        inst2 = format_inst(mi2)
        assert inst1 == inst2

# ---------------------------------------------------------------------------
# format_sigs
# ---------------------------------------------------------------------------

class TestFormatSigs:
    def test_all_wires(self):
        mi    = parse_module(load('simple.v'))
        lines = format_sigs(mi)
        assert all(l.startswith('wire') for l in lines if not l.startswith('`'))

    def test_port_names_present(self):
        mi    = parse_module(load('simple.v'))
        text  = '\n'.join(format_sigs(mi))
        for n in ('clk', 'rst_n', 'data_in', 'data_out', 'valid'):
            assert n in text

    def test_packed_dim_included(self):
        mi   = parse_module(load('simple.v'))
        text = '\n'.join(format_sigs(mi))
        assert '[7:0]' in text

    def test_semicolons(self):
        mi    = parse_module(load('simple.v'))
        lines = format_sigs(mi)
        for l in lines:
            if not l.startswith('`'):
                assert l.endswith(';')

    def test_ifdef_preserved(self):
        mi   = parse_module(load('conditional.v'))
        text = '\n'.join(format_sigs(mi))
        assert '`ifdef DEBUG' in text
        assert '`endif'       in text

    def test_ifdef_port_is_wire(self):
        mi    = parse_module(load('conditional.v'))
        lines = format_sigs(mi)
        dbg   = next(l for l in lines if 'dbg_valid' in l)
        assert dbg.startswith('wire')


# ---------------------------------------------------------------------------
# format_tb
# ---------------------------------------------------------------------------

class TestFormatTB:
    def setup_method(self):
        self.mi    = parse_module(load('simple.v'))
        self.lines = format_tb(self.mi)
        self.text  = '\n'.join(self.lines)

    def test_timescale(self):
        assert self.lines[0] == '`timescale 1ns/1ps'

    def test_module_name(self):
        assert 'module tb_simple' in self.text

    def test_endmodule(self):
        assert self.lines[-1] == 'endmodule'

    def test_non_clk_rst_ports_are_wire(self):
        sig_lines = [l for l in self.lines if ('wire' in l or 'reg' in l)
                     and any(n in l for n in ('data_in','data_out','valid'))]
        assert all('wire' in l for l in sig_lines)

    def test_clk_always_reg(self):
        reg_clk = [l for l in self.lines if 'reg' in l and 'clk' in l]
        assert len(reg_clk) == 1

    def test_rst_n_always_reg(self):
        reg_rst = [l for l in self.lines if 'reg' in l and 'rst_n' in l]
        assert len(reg_rst) == 1

    def test_no_wire_clk_when_port_exists(self):
        # simple.v has clk as a port -> wire clk should be suppressed
        wire_clk = [l for l in self.lines if 'wire' in l and l.strip() == 'wire clk;']
        assert wire_clk == []

    def test_no_wire_rst_n_when_port_exists(self):
        wire_rst = [l for l in self.lines if 'wire' in l and l.strip() == 'wire rst_n;']
        assert wire_rst == []

    def test_clock_gen(self):
        assert 'CLK_PERIOD' in self.text
        assert '~clk'       in self.text

    def test_reset_cycle_always_present(self):
        assert "rst_n = 1'b0" in self.text
        assert "rst_n = 1'b1" in self.text
        assert 'repeat' in self.text

    def test_dut_instantiated(self):
        assert 'u_simple' in self.text

    def test_finish(self):
        assert '$finish' in self.text

    def test_todo(self):
        assert 'TODO' in self.text


class TestFormatTBNoClkNoRst:
    """Module with neither clk nor rst_n port -> both regs, no suppression."""
    def setup_method(self):
        src = "module foo (input wire a, output wire b);"
        self.mi   = parse_module(src)
        self.text = '\n'.join(format_tb(self.mi))

    def test_reg_clk_present(self):
        assert 'reg  clk' in self.text

    def test_reg_rst_n_present(self):
        assert 'reg  rst_n' in self.text

    def test_reset_cycle_present(self):
        assert "rst_n = 1'b0" in self.text
        assert "rst_n = 1'b1" in self.text

    def test_wire_a_present(self):
        assert 'wire a;' in self.text

    def test_wire_b_present(self):
        assert 'wire b;' in self.text


class TestFormatTBOnlyClk:
    """Module has clk port -> reg clk still present, wire clk suppressed."""
    def setup_method(self):
        src = "module foo (input wire clk, output wire q);"
        self.mi   = parse_module(src)
        self.lines = format_tb(self.mi)
        self.text  = '\n'.join(self.lines)

    def test_reg_clk_present(self):
        assert 'reg  clk' in self.text

    def test_no_wire_clk(self):
        wire_clk = [l for l in self.lines if l.strip() == 'wire clk;']
        assert wire_clk == []

    def test_wire_q_present(self):
        assert 'wire q;' in self.text

    def test_reg_rst_n_present(self):
        assert 'reg  rst_n' in self.text


class TestFormatTBConditional:
    def test_ifdef_in_signals(self):
        mi   = parse_module(load('conditional.v'))
        text = '\n'.join(format_tb(mi))
        assert '`ifdef DEBUG' in text
