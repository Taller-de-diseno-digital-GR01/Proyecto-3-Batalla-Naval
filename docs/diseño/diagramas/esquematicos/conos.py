# conos.py pre.json modulo GRUPO  parte las celdas del GRUPO según el registro al que alimentan, las compartidas van a GRUPO_COMUN
import json, sys
p, mod, g = sys.argv[1:]
d = json.load(open(p)); m = d['modules'][mod]
cells = {k: c for k, c in m['cells'].items() if c.get('attributes', {}).get('submod') == g}
nombre = {}
for n, info in m['netnames'].items():
    if n.startswith('$'): continue
    for b in info['bits']:
        if isinstance(b, int): nombre.setdefault(b, n)
driver = {}
for k, c in cells.items():
    for pn, dirn in c['port_directions'].items():
        if dirn == 'output':
            for b in c['connections'][pn]:
                if isinstance(b, int): driver[b] = k
dueno = {}
for k, c in cells.items():
    if c['type'] not in ('$dff', '$adff', '$sdff', '$dffe', '$sdffe'): continue
    q = c['connections']['Q']
    # con nombre exacto primero, si no un alias como mascara_ext = {0, pend_mascara_val} se lleva el registro
    reg = next((n for n, info in m['netnames'].items() if info['bits'] == q and not n.startswith('$')), nombre.get(q[0], k)).upper()
    pila, vistos = [k], set()
    while pila:
        x = pila.pop()
        if x in vistos: continue
        vistos.add(x); dueno.setdefault(x, set()).add(reg)
        for pn, dirn in cells[x]['port_directions'].items():
            if dirn != 'input': continue
            for b in cells[x]['connections'][pn]:
                y = driver.get(b)
                if y and cells[y]['type'] not in ('$dff', '$adff', '$sdff', '$dffe', '$sdffe'): pila.append(y)
for k, c in cells.items():
    regs = dueno.get(k, {'COMUN'})
    c['attributes']['submod'] = f"{g}_{next(iter(regs))}" if len(regs) == 1 else f"{g}_COMUN"
# las salidas sin nombre de lo común se bautizan con el texto de la expresión del .sv, si no quedan como n1, n2
import re
sv = open(m['cells'][next(iter(cells))]['attributes']['src'].split(':')[0]).read().split('\n') if cells else []
usados = {b for info in m['netnames'].values() if not info.get('hide_name') for b in info['bits']}
for k, c in cells.items():
    if not c['attributes']['submod'].endswith('_COMUN'): continue
    r = re.match(r'[^:|]+:(\d+)\.(\d+)-(\d+)\.(\d+)', c['attributes'].get('src', ''))
    if not r or r[1] != r[3]: continue
    texto = re.sub(r'\s+', '', sv[int(r[1]) - 1][int(r[2]) - 1:int(r[4]) - 1])
    if c['type'] in ('$eq', '$logic_not') and not re.search(r'==|!', texto):
        # comparación de un case, se arma como senal==CONSTANTE usando los localparam del .sv, contra cero yosys la deja como $logic_not
        a, b = c['connections']['A'], c['connections'].get('B', ['0'])
        if all(isinstance(x, str) for x in b):
            senal = next((n for n, info in m['netnames'].items() if info['bits'] == a and not n.startswith('$')), None)
            val = int(''.join(reversed(b)), 2)
            consts = {int(v): n for n, v in re.findall(r"localparam[^=]*\b(\w+)\s*=\s*\d*'d(\d+)", '\n'.join(sv))}
            texto = f"{senal}=={consts.get(val, val)}" if senal else ''
    if not texto or texto in m['netnames']: continue
    for pn, dirn in c['port_directions'].items():
        bits = c['connections'][pn]
        if dirn == 'output' and not set(bits) & usados:
            m['netnames'][texto] = {'hide_name': 0, 'bits': bits, 'attributes': {}}
json.dump(d, open(p, 'w'))
