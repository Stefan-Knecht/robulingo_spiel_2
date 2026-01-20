#!/usr/bin/env zsh
set -euo pipefail

# Ordner mit den Original-WebPs
SRC_DIR="/Users/knecht/Knecht x/_P_Kopie/__Meerbusch/_Projects/_RobuLingo/Clipart/transparent background/rival transparent"
# Ausgabeordner (Originale bleiben unangetastet)
OUT_DIR="${SRC_DIR}/transparent_out"

mkdir -p "$OUT_DIR"

# Alle WebP/PNG/JPG rekursiv anfassen, Ausgabe immer als WebP
find "$SRC_DIR" -type f \( -iname '*.webp' -o -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) | while IFS= read -r img; do
  rel="${img#${SRC_DIR}/}"             # Pfad relativ zum SRC_DIR
  base_no_ext="${rel%.*}"
  out_path="${OUT_DIR}/${base_no_ext}.webp"
  mkdir -p "$(dirname "$out_path")"

  magick "$img" \
    -alpha set \
    -bordercolor white -border 1 \
    -fill none -floodfill +0+0 white \
    -shave 1 \
    -define webp:lossless=true \
    "$out_path"
  echo "Fertig: $out_path"
done

echo "Alle Bilder verarbeitet."
