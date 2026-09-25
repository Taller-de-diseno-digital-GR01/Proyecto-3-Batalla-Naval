# pone el nombre de la señal que maneja cada celda en attributes.senal y limpia nombres $paramod
import json, re, sys
p = sys.argv[1]; d = json.load(open(p))
fix = lambda s: re.sub(r"^\$paramod\\([^\\]+)\\.*$", r"\1", s)
d['modules'] = {fix(k): v for k, v in d['modules'].items()}
for m in d['modules'].values():
    nombres = {}
    for n, info in m.get('netnames', {}).items():
        if info.get('hide_name'): continue
        bits = info['bits']
        for i, b in enumerate(bits):
            if isinstance(b, int): nombres.setdefault(b, n if len(bits) == 1 else f"{n}[{i}]")
    puertos = {b for pt in m.get('ports', {}).values() for b in pt['bits'] if isinstance(b, int)}
    for c in m.get('cells', {}).values():
        c['type'] = fix(c['type'])
        for pn, dirn in list(c.get('port_directions', {}).items()):
            if dirn != 'output': continue
            bits = c['connections'][pn]
            completo = [n for n, info in m['netnames'].items() if not info.get('hide_name') and info['bits'] == bits]
            if completo and not set(bits) & puertos:
                if c['type'].startswith('$'):
                    c.setdefault('attributes', {})['senal'] = completo[0]
                else:
                    # en las cajas de submódulo el nombre va pegado al puerto de salida
                    nuevo = f"{pn} ({completo[0]})"
                    c['connections'][nuevo] = c['connections'].pop(pn)
                    c['port_directions'][nuevo] = c['port_directions'].pop(pn)
            elif len(bits) == 1 and bits[0] in nombres and (bits[0] not in puertos or c['type'] == '$_DFF_P_'):
                c.setdefault('attributes', {})['senal'] = nombres[bits[0]]
for m in d['modules'].values():
    # netlistsvg parte el id de la etiqueta por puntos y los nombres de abc traen puntos
    m['cells'] = {(k if re.fullmatch(r'\w+', k) else f'c{i}'): v for i, (k, v) in enumerate(m.get('cells', {}).items())}
json.dump(d, open(p, 'w'))
