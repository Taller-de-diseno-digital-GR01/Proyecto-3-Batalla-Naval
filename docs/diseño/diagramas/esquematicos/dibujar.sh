# dibujar.sh all.json prefijo modulo, deja modulo.png con modulo como top y sin el prefijo de submod
D=$(dirname "$(readlink -f "$0")")
python3 - "$1" "$2" "$3" <<'P'
import json, sys
p, pre, m = sys.argv[1:]
d = json.load(open(p))
ren = lambda s: s[len(pre)+1:] if s.startswith(pre + '_') else s
d['modules'] = {ren(k): v for k, v in d['modules'].items()}
for k, v in d['modules'].items():
    v.setdefault('attributes', {})['top'] = int(k == m)
    for c in v.get('cells', {}).values(): c['type'] = ren(c['type'])
json.dump(d, open(m + '.json', 'w'))
P
python3 "$D/etiquetar.py" $3.json
npx -y netlistsvg $3.json --skin "$D/skin.svg" -o $3.svg 2>&1 | grep -v notice
# netlistsvg recorta los nombres largos de las entradas contra el borde izquierdo
python3 - $3.svg <<'P'
import re, sys
p = sys.argv[1]; s = open(p).read()
w, h = (float(x) for x in re.search(r'<svg[^>]*?width="([\d.]+)" height="([\d.]+)"', s).groups())
s = re.sub(r'(<svg[^>]*?)width="[\d.]+" height="[\d.]+"', lambda m: f'{m[1]}width="{w+160}" height="{h+20}" viewBox="-150 -10 {w+160} {h+20}"', s, count=1)
open(p, 'w').write(s)
P
rsvg-convert -b white -z 2 $3.svg -o $3.png
