" vim-vinst -- Verilog interface yank/paste plugin
" Requires Vim with +python3
" Place in ~/.vim/plugin/vim-vinst.vim
"
" Commands:
"   :VlogYank       -- parse module under cursor, save to /tmp/vlog_yank.json
"   :VlogPasteInst  -- paste instantiation below cursor
"   :VlogPasteSigs  -- paste signal declarations below cursor
"   :VlogPasteTB    -- paste testbench skeleton below cursor
"
" Keybindings (set maplocalleader in .vimrc, e.g. let maplocalleader=','):
"   <localleader>vy  -- VlogYank
"   <localleader>vi  -- VlogPasteInst
"   <localleader>vs  -- VlogPasteSigs
"   <localleader>vt  -- VlogPasteTB

if exists('g:loaded_vlog')
    finish
endif
let g:loaded_vim_vinst = 1

if !has('python3')
    echohl WarningMsg
    echom 'vlog: requires Vim compiled with +python3'
    echohl None
    finish
endif

python3 << EOF
import re, json

YANK_FILE = '/tmp/vlog_yank.json'

class ParseError(Exception):
    pass

# ---------------------------------------------------------------------------
# Comment stripping (preserves preprocessor directives)
# ---------------------------------------------------------------------------

_BLOCK_COMMENT  = re.compile(r'/\*.*?\*/', re.DOTALL)
_INLINE_COMMENT = re.compile(r'//[^\n]*')

def _strip_comments(text):
    text = _BLOCK_COMMENT.sub(lambda m: '\n' * m.group().count('\n'), text)
    out  = []
    for line in text.split('\n'):
        if line.lstrip().startswith('`'):
            out.append(line)
        else:
            out.append(_INLINE_COMMENT.sub('', line))
    return '\n'.join(out)

# ---------------------------------------------------------------------------
# Preprocessor splitter
# ---------------------------------------------------------------------------

_IFDEF_RE = re.compile(
    r'`(ifdef|ifndef)\b\s*(\w+)|`(else|endif)\b',
    re.MULTILINE)

def _split_ifdefs(text):
    pos = 0
    for m in _IFDEF_RE.finditer(text):
        yield text[pos:m.start()], None
        if m.group(1):
            yield '', {'kind': 'ifdef', 'directive': m.group(1), 'symbol': m.group(2)}
        else:
            yield '', {'kind': 'ifdef', 'directive': m.group(3), 'symbol': ''}
        pos = m.end()
    yield text[pos:], None

# ---------------------------------------------------------------------------
# Header extraction
# ---------------------------------------------------------------------------

_MODULE_RE = re.compile(r'\bmodule\b')

def _extract_header(text):
    m = _MODULE_RE.search(text)
    if not m:
        raise ParseError("No 'module' keyword found")
    i, depth = m.start(), 0
    while i < len(text):
        c = text[i]
        if   c == '(': depth += 1
        elif c == ')': depth -= 1
        elif c == ';' and depth == 0:
            return text[m.start():i+1]
        i += 1
    raise ParseError("Unterminated module header")

def _split_header(header):
    m = re.match(r'\s*module\s+(\w+)\s*', header)
    if not m:
        raise ParseError("Cannot extract module name")
    name, rest = m.group(1), header[m.end():]

    param_text = None
    if rest.startswith('#'):
        depth = 0
        for i, c in enumerate(rest[1:], 1):
            if c == '(':  depth += 1
            elif c == ')':
                depth -= 1
                if depth == 0:
                    param_text = rest[2:i]
                    rest = rest[i+1:].lstrip()
                    break
        else:
            raise ParseError("Unterminated parameter list")

    m2 = re.match(r'\s*\(\s*(.*)\s*\)\s*;?\s*$', rest, re.DOTALL)
    if not m2:
        raise ParseError("Cannot locate port list")
    return name, param_text, m2.group(1)

# ---------------------------------------------------------------------------
# Parameter and port parsers
# ---------------------------------------------------------------------------

_PARAM_RE = re.compile(
    r'\bparameter\b'
    r'(?:\s+(integer|real|string|signed|unsigned))?'
    r'\s+(\w+)\s*=\s*'
    r'([^,`\n]+?)\s*(?=,|$)',
    re.DOTALL)

_PORT_RE = re.compile(
    r'\b(input|output|inout)\b'
    r'(?:\s+\b(wire|reg|logic|tri)\b)?'
    r'(?:\s+\bsigned\b)?'
    r'((?:\s*\[[^\]]+\])+)?'
    r'\s+(\w+)'
    r'\s*(?=,|\n\s*[)`]|$)',
    re.DOTALL)

def _parse_params(text):
    items = []
    for chunk, marker in _split_ifdefs(text):
        if marker is not None:
            items.append(marker)
            continue
        for m in _PARAM_RE.finditer(chunk):
            items.append({'kind': 'param',
                          'ptype':   (m.group(1) or '').strip(),
                          'name':    m.group(2).strip(),
                          'default': m.group(3).strip().rstrip(',').strip()})
    return items

def _parse_ports(text):
    items = []
    for chunk, marker in _split_ifdefs(text):
        if marker is not None:
            items.append(marker)
            continue
        for m in _PORT_RE.finditer(chunk):
            items.append({'kind':      'port',
                          'direction': m.group(1).strip(),
                          'net_type':  (m.group(2) or '').strip(),
                          'packed':    (m.group(3) or '').strip(),
                          'name':      m.group(4).strip()})
    return items

# ---------------------------------------------------------------------------
# Top-level parse
# ---------------------------------------------------------------------------

def parse_module(text):
    clean  = _strip_comments(text)
    header = _extract_header(clean)
    name, param_text, port_text = _split_header(header)
    params = _parse_params(param_text) if param_text else []
    ports  = _parse_ports(port_text)
    if not any(p['kind'] == 'port' for p in ports):
        raise ParseError(f"No ports found in module '{name}'")
    return {'name': name, 'params': params, 'ports': ports}

# ---------------------------------------------------------------------------
# Cursor-aware buffer search
# ---------------------------------------------------------------------------

def find_module_text(lines, cursor_row):
    start = None
    for row in range(cursor_row, -1, -1):
        if _MODULE_RE.search(lines[row]):
            start = row
            break
    if start is None:
        raise ParseError("No 'module' keyword found above cursor")
    depth = 0
    for row in range(start, len(lines)):
        for ch in lines[row]:
            if   ch == '(': depth += 1
            elif ch == ')': depth -= 1
            elif ch == ';' and depth == 0:
                return '\n'.join(lines[start:row+1])
    raise ParseError("Unterminated module header")

# ---------------------------------------------------------------------------
# Instantiation formatter
# ---------------------------------------------------------------------------

def format_inst(mi):
    lines = []
    i4    = '    '

    real_params = [p for p in mi['params'] if p['kind'] == 'param']
    if real_params:
        nw = max(len(p['name']) for p in real_params)
        lines.append(f"{mi['name']} #(")
        for idx, item in enumerate(mi['params']):
            if item['kind'] == 'ifdef':
                lines.append('`' + item['directive'] + (' ' + item['symbol'] if item['symbol'] else ''))
                continue
            has_more = any(x['kind'] == 'param' for x in mi['params'][idx+1:])
            lines.append(f"{i4}.{item['name']:<{nw}}  ({item['default']})" + (',' if has_more else ''))
        lines.append(f") u_{mi['name']} (")
    else:
        lines.append(f"{mi['name']} u_{mi['name']} (")

    real_ports = [p for p in mi['ports'] if p['kind'] == 'port']
    nw = max((len(p['name']) for p in real_ports), default=0)
    for idx, item in enumerate(mi['ports']):
        if item['kind'] == 'ifdef':
            lines.append('`' + item['directive'] + (' ' + item['symbol'] if item['symbol'] else ''))
            continue
        has_more = any(x['kind'] == 'port' for x in mi['ports'][idx+1:])
        lines.append(f"{i4}.{item['name']:<{nw}}  ({item['name']})" + (',' if has_more else ''))

    lines.append(');')
    return lines

# ---------------------------------------------------------------------------
# Signal list formatter
# ---------------------------------------------------------------------------

_RST_NAMES = {'rst', 'rst_n', 'reset', 'reset_n'}
_CLK_NAMES = {'clk', 'clock'}

def _is_rst(name): return name.lower() in _RST_NAMES
def _is_clk(name): return name.lower() in _CLK_NAMES

def format_sigs(mi, suppress=None):
    """One 'wire [packed] name;' per port, ifdef blocks preserved.
    Names in suppress set are omitted (used by format_tb to avoid
    duplicating clk/rst_n which are always declared as reg there).
    """
    suppress = suppress or set()
    lines = []
    for item in mi['ports']:
        if item['kind'] == 'ifdef':
            lines.append('`' + item['directive'] + (' ' + item['symbol'] if item['symbol'] else ''))
            continue
        if item['name'] in suppress:
            continue
        packed = (item['packed'] + ' ') if item['packed'] else ''
        lines.append(f"wire {packed}{item['name']};")
    return lines

# ---------------------------------------------------------------------------
# Testbench formatter
# ---------------------------------------------------------------------------

def format_tb(mi):
    i4 = '    '
    i8 = '        '
    lines = []

    # Always declare clk and rst_n as reg (driven procedurally).
    # Suppress matching wire declarations in format_sigs to avoid collision.
    port_names = {p['name'] for p in mi['ports'] if p['kind'] == 'port'}
    suppress   = {'clk', 'rst_n'} & port_names

    # --- header ---
    lines += ['`timescale 1ns/1ps', '', f'module tb_{mi["name"]};', '']

    # --- clk and rst_n always as reg ---
    lines += [
        f'{i4}reg  clk;',
        f'{i4}reg  rst_n;',
        '',
    ]

    # --- signal declarations: all wires (clk/rst_n suppressed if ports) ---
    lines += [f'    {l}' if l and not l.startswith('`') else l for l in format_sigs(mi, suppress=suppress)]
    lines.append('')

    # --- clock generation ---
    lines += [
        f'{i4}// 100 MHz clock',
        f'{i4}localparam CLK_PERIOD = 10;',
        f"{i4}initial clk = 1'b0;",
        f'{i4}always #(CLK_PERIOD/2) clk = ~clk;',
        '',
    ]

    # --- DUT instantiation ---
    lines += format_inst(mi)
    lines.append('')

    # --- stimulus with active-low rst_n reset cycle ---
    lines += [
        f'{i4}initial begin',
        f"{i8}rst_n = 1'b0;",
        f'{i8}repeat (4) @(posedge clk);',
        f"{i8}rst_n = 1'b1;",
        f'{i8}@(posedge clk);',
        '',
        f'{i8}// TODO: add stimulus here',
        '',
        f'{i8}$finish;',
        f'{i4}end',
        '',
        'endmodule',
    ]
    return lines

# ---------------------------------------------------------------------------
# Vim-facing functions
# ---------------------------------------------------------------------------

def _msg(s, error=False):
    import vim
    hl = 'ErrorMsg' if error else 'None'
    vim.command(f'echohl {hl} | echom {s!r} | echohl None')

def vlog_yank():
    import vim
    try:
        buf_lines  = list(vim.current.buffer)
        cursor_row = vim.current.window.cursor[0] - 1
        text       = find_module_text(buf_lines, cursor_row)
        mi         = parse_module(text)
        with open(YANK_FILE, 'w') as f:
            json.dump(mi, f, indent=2)
        n = sum(1 for p in mi['ports'] if p['kind'] == 'port')
        _msg(f"vlog: yanked '{mi['name']}' ({n} ports) -> {YANK_FILE}")
    except ParseError as e:
        _msg(f"vlog yank: {e}", error=True)
    except OSError as e:
        _msg(f"vlog yank: cannot write {YANK_FILE}: {e}", error=True)

def _load_yank():
    try:
        with open(YANK_FILE) as f:
            return json.load(f), None
    except FileNotFoundError:
        return None, f"vlog: nothing yanked yet ({YANK_FILE} not found)"
    except OSError as e:
        return None, f"vlog paste: {e}"

def _insert_below(lines):
    import vim
    row, _ = vim.current.window.cursor
    vim.current.buffer.append(lines, row)
    vim.current.window.cursor = (row + 1, 0)

def vlog_paste_inst():
    import vim
    mi, err = _load_yank()
    if err:
        _msg(err, error=True)
        return
    _insert_below(format_inst(mi))

def vlog_paste_sigs():
    import vim
    mi, err = _load_yank()
    if err:
        _msg(err, error=True)
        return
    _insert_below(format_sigs(mi))

def vlog_paste_tb():
    import vim
    mi, err = _load_yank()
    if err:
        _msg(err, error=True)
        return
    _insert_below(format_tb(mi))

EOF

" -------------------------------------------------------------------------
" Commands and keybindings
" -------------------------------------------------------------------------

command! VlogYank      python3 vlog_yank()
command! VlogPasteInst python3 vlog_paste_inst()
command! VlogPasteSigs python3 vlog_paste_sigs()
command! VlogPasteTB   python3 vlog_paste_tb()

nnoremap <localleader>vy :VlogYank<CR>
nnoremap <localleader>vi :VlogPasteInst<CR>
nnoremap <localleader>vs :VlogPasteSigs<CR>
nnoremap <localleader>vt :VlogPasteTB<CR>
