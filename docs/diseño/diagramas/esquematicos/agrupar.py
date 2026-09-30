# agrupar.py archivo.json modulo archivo.sv NOMBRE:ini-fin ...  marca cada celda con el bloque según la línea del .sv de donde sale
import json, re, sys
p, mod, sv, *rangos = sys.argv[1:]
rangos = [(n, int(a), int(b)) for n, ab in (r.split(':') for r in rangos) for a, b in [ab.split('-')]]
d = json.load(open(p))
for c in d['modules'][mod]['cells'].values():
    lineas = [int(x) for x in re.findall(re.escape(sv) + r':(\d+)\.', c.get('attributes', {}).get('src', ''))]
    for n, a, b in rangos:
        if any(a <= l <= b for l in lineas):
            c['attributes']['submod'] = n
            break
json.dump(d, open(p, 'w'))
