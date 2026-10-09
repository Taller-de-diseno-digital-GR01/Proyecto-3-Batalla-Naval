# componer.sh all.json top salida.png, dibuja top y cada submódulo y los apila con su título
D=$(dirname "$(readlink -f "$0")")
all=$1; top=$2; out="$3"
F=$(fc-match -f '%{file}' 'sans:bold')
mods=$(python3 -c "import json;d=json.load(open('$all'));print(' '.join(sorted(k[len('$top')+1:] for k in d['modules'] if k.startswith('${top}_'))))")
bash "$D/dibujar.sh" $all $top $top
args=( \( -font "$F" -pointsize 30 label:"$top" $top.png -gravity west -append \) )
for m in $mods; do bash "$D/dibujar.sh" $all $top $m; args+=( \( -font "$F" -pointsize 26 label:"$m" $m.png -gravity west -append \) ); done
magick -background white "${args[@]}" -gravity north -splice 0x50 -gravity west -append -bordercolor white -border 30 "$out"
