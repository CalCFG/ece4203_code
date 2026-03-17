#!/usr/bin/env python3
"""
sdf_inject.py - Inject SDF delays into a gate-level Verilog netlist.

Reads a synthesis-level SDF file and a mapped Verilog netlist, then
produces a new Verilog file where each cell instantiation is replaced
by a uniquified wrapper module containing a specify block with the
back-annotated IOPATH delays.

The result is a self-contained timed netlist that iverilog can simulate
with -g specify, without needing $sdf_annotate or power-port machinery.

Usage:
    python3 sdf_inject.py \
        --sdf     results/netlist_8.sdf \
        --netlist results/netlist_8.v \
        --cells   /path/to/sky130_fd_sc_hd.v \
        --out     results/netlist_8_timed.v

Compile the output:
    iverilog -g2012 -g specify -o sim_exe tb_gl.v results/netlist_8_timed.v
"""

import re
import sys
import argparse
from collections import defaultdict


# ---------------------------------------------------------------------------
# SDF parser
# ---------------------------------------------------------------------------

def parse_value_max(triple_str):
    """
    Extract the max delay from an SDF delay triple string.
    Handles: (v)  (min:typ:max)  (min::max)  (::max)
    Returns float in ns, or 0.0 if unparseable.
    The max slot is chosen to be consistent with STA -path_delay max.
    """
    s = triple_str.strip().strip('()')
    parts = s.split(':')
    if len(parts) == 1:
        try:
            return float(parts[0])
        except ValueError:
            return 0.0
    elif len(parts) == 3:
        # Try max first (index 2), then min (index 0), then typ (index 1)
        for idx in [2, 0, 1]:
            v = parts[idx].strip()
            if v:
                try:
                    return float(v)
                except ValueError:
                    continue
        return 0.0
    return 0.0


def parse_sdf(sdf_path):
    """
    Parse SDF IOPATH entries.
    Returns dict: delays[instance_name][(port_in, port_out)] = (rise, fall)
    rise and fall are the max-slot values from the SDF triples.
    TIMINGCHECK blocks (setup/hold) are skipped.
    """
    delays = defaultdict(dict)

    with open(sdf_path) as f:
        text = f.read()

    # Tokenize into parentheses and words
    tokens = re.findall(r'\(|\)|[^\s()]+', text)
    n = len(tokens)
    i = 0

    def consume_until_close():
        """Skip tokens until the matching close paren, return."""
        depth = 1
        nonlocal i
        while i < n and depth > 0:
            if tokens[i] == '(':
                depth += 1
            elif tokens[i] == ')':
                depth -= 1
            i += 1

    while i < n:
        if tokens[i] == '(' and i + 1 < n and tokens[i+1].upper() == 'CELL':
            i += 2  # consume '(' 'CELL'
            instance_name = None
            depth = 1

            while i < n and depth > 0:
                if tokens[i] == '(':
                    kw = tokens[i+1].upper() if i+1 < n else ''

                    if kw == 'CELLTYPE':
                        # (CELLTYPE "name") - skip
                        i += 1
                        consume_until_close()

                    elif kw == 'INSTANCE':
                        i += 2  # '(' 'INSTANCE'
                        if i < n and tokens[i] != ')':
                            instance_name = tokens[i]
                            i += 1
                        # consume closing ')'
                        while i < n and tokens[i] != ')':
                            i += 1
                        if i < n:
                            i += 1  # consume ')'

                    elif kw == 'TIMINGCHECK':
                        # Skip setup/hold checks entirely
                        i += 1
                        consume_until_close()

                    elif kw == 'DELAY':
                        i += 2  # '(' 'DELAY'
                        delay_depth = 1
                        while i < n and delay_depth > 0:
                            if tokens[i] == '(':
                                sub = tokens[i+1].upper() if i+1 < n else ''
                                if sub == 'IOPATH':
                                    # (IOPATH port_in port_out (rise_triple) (fall_triple))
                                    i += 2  # '(' 'IOPATH'
                                    port_in  = tokens[i]; i += 1
                                    port_out = tokens[i]; i += 1
                                    rise_str = tokens[i]; i += 1
                                    fall_str = tokens[i]; i += 1
                                    # consume closing ')'
                                    while i < n and tokens[i] != ')':
                                        i += 1
                                    if i < n:
                                        i += 1

                                    rise = parse_value_max(rise_str)
                                    fall = parse_value_max(fall_str)

                                    if instance_name and instance_name != '*':
                                        delays[instance_name][(port_in, port_out)] = (rise, fall)
                                else:
                                    i += 1
                                    delay_depth += 1
                            elif tokens[i] == ')':
                                delay_depth -= 1
                                i += 1
                            else:
                                i += 1

                    else:
                        i += 1
                        depth += 1

                elif tokens[i] == ')':
                    depth -= 1
                    i += 1
                else:
                    i += 1
        else:
            i += 1

    return delays


# ---------------------------------------------------------------------------
# Netlist parser
# ---------------------------------------------------------------------------

INST_RE = re.compile(
    r'[ \t]*(sky130_\w+)\s+(\w+)\s*\(([^;]+)\)\s*;',
    re.MULTILINE | re.DOTALL
)

def parse_netlist(netlist_path):
    with open(netlist_path) as f:
        text = f.read()
    instances = []
    for m in INST_RE.finditer(text):
        instances.append((m.group(1), m.group(2), m.group(3), m.group(0)))
    return instances, text


# ---------------------------------------------------------------------------
# Cell port parser
# ---------------------------------------------------------------------------

POWER_PORTS = {'VPWR', 'VGND', 'VPB', 'VNB', 'VDD', 'VSS'}
CLOCK_PORTS = {'CLK', 'clk', 'CK', 'ck', 'GCLK', 'CLK_N'}

def parse_cell_ports(cells_path, cell_types):
    """
    Returns dict: {cell_type: {'inputs': [...], 'outputs': [...]}}
    Power ports are excluded.
    """
    with open(cells_path) as f:
        text = f.read()

    port_info = {}
    for cell in cell_types:
        pat = re.compile(
            r'module\s+' + re.escape(cell) + r'\b\s*(?:#[^;]*)?\s*\(([^)]*)\)(.*?)endmodule',
            re.DOTALL
        )
        m = pat.search(text)
        if not m:
            continue
        body = m.group(2)
        inputs  = [p for p in re.findall(r'\binput\b\s+(?:wire\s+)?(?:\[\S+\]\s+)?(\w+)', body)
                   if p not in POWER_PORTS]
        outputs = [p for p in re.findall(r'\boutput\b\s+(?:wire\s+)?(?:\[\S+\]\s+)?(\w+)', body)
                   if p not in POWER_PORTS]
        port_info[cell] = {'inputs': inputs, 'outputs': outputs}

    return port_info


# ---------------------------------------------------------------------------
# Wrapper generator
# ---------------------------------------------------------------------------

def make_wrapper(cell_type, inst_name, port_conn_str, inst_delays, port_info):
    """
    Build a uniquified wrapper module with a specify block.
    Returns (wrapper_text, new_instantiation_line) or (None, None) on failure.
    """
    info = port_info.get(cell_type)
    if not info:
        return None, None

    inputs  = info['inputs']
    outputs = info['outputs']
    all_ports = inputs + outputs
    if not all_ports:
        return None, None

    wrapper_name = cell_type + '__' + inst_name

    # Port declarations
    decls = []
    for p in inputs:
        decls.append(f"    input  wire {p};")
    for p in outputs:
        decls.append(f"    output wire {p};")

    # Inner cell instantiation (no power ports)
    conns = ',\n        '.join(f'.{p}({p})' for p in all_ports)
    inner = f"    {cell_type} _inner_ (\n        {conns}\n    );"

    # Specify block
    # Key rule: use (posedge CLK => Q) for clock->output paths,
    # plain (A => X) for all combinational paths.
    # iverilog rejects posedge/negedge on non-clock combinational paths.
    spec_lines = []
    for (port_in, port_out), (rise, fall) in inst_delays.items():
        pin_in  = re.sub(r'\[\d+\]', '', port_in)
        pin_out = re.sub(r'\[\d+\]', '', port_out)
        if pin_in not in all_ports or pin_out not in all_ports:
            continue
        if pin_in in CLOCK_PORTS:
            spec_lines.append(f"        (posedge {pin_in} => {pin_out}) = ({rise:.4f}, {fall:.4f});")
        else:
            spec_lines.append(f"        ({pin_in} => {pin_out}) = ({rise:.4f}, {fall:.4f});")

    if spec_lines:
        specify = "    specify\n" + "\n".join(spec_lines) + "\n    endspecify"
    else:
        specify = "    // no IOPATH delays for this instance"

    port_list = ', '.join(all_ports)
    wrapper = "\n".join([
        f"// Timed wrapper: {inst_name} ({cell_type})",
        f"module {wrapper_name} ({port_list});",
        "\n".join(decls),
        "",
        inner,
        "",
        specify,
        "endmodule",
        ""
    ])

    new_inst = f"    {wrapper_name} {inst_name} ({port_conn_str.strip()});"
    return wrapper, new_inst


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--sdf',      required=True)
    ap.add_argument('--netlist',  required=True)
    ap.add_argument('--cells',    required=True)
    ap.add_argument('--out',      required=True)
    ap.add_argument('--timescale', default='1ns/1ps')
    ap.add_argument('--verbose',  action='store_true')
    args = ap.parse_args()

    print(f"Parsing SDF: {args.sdf}")
    delays = parse_sdf(args.sdf)
    print(f"  {len(delays)} instances with delay data")

    print(f"Parsing netlist: {args.netlist}")
    instances, netlist_text = parse_netlist(args.netlist)
    print(f"  {len(instances)} cell instances")

    cell_types = set(c for c, _, _, _ in instances)
    print(f"Parsing cell ports from: {args.cells}")
    port_info = parse_cell_ports(args.cells, cell_types)
    print(f"  Port info for {len(port_info)}/{len(cell_types)} cell types")

    wrappers = []
    patched = netlist_text
    matched = unmatched = 0

    for cell_type, inst_name, port_str, orig in instances:
        # OpenSTA sometimes wraps names in underscores: _170_ vs _170_
        # Try the name as-is and with surrounding underscores stripped
        inst_delays = {}
        for candidate in [inst_name, inst_name.strip('_'), f'_{inst_name}_']:
            if candidate in delays:
                inst_delays = delays[candidate]
                break

        if inst_delays:
            matched += 1
        else:
            unmatched += 1
            if args.verbose:
                print(f"  no SDF match: {inst_name} ({cell_type})")

        wrapper, new_inst = make_wrapper(cell_type, inst_name, port_str, inst_delays, port_info)
        if wrapper is None:
            if args.verbose:
                print(f"  skipping {inst_name}: no port info for {cell_type}")
            continue

        wrappers.append(wrapper)
        patched = patched.replace(orig.strip(), new_inst, 1)

    print(f"  Delay-matched: {matched}/{matched+unmatched} instances")

    with open(args.out, 'w') as f:
        f.write(f"`timescale {args.timescale}\n\n")
        f.write("// Generated by sdf_inject.py\n")
        f.write("// Timed wrappers with specify blocks from SDF\n\n")
        for w in wrappers:
            f.write(w + "\n")
        f.write("// Patched netlist\n\n")
        f.write(patched)

    print(f"Written: {args.out}")

if __name__ == '__main__':
    main()
