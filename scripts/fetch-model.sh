#!/bin/bash
# Baixa UMA VEZ um modelo do WhisperKit (Core ML) + tokenizer, fora do app.
# Depois, no Gravador: Preferências › Transcrição › Importar modelo… e escolha a pasta criada.
#
# Uso: scripts/fetch-model.sh [destino] [variante]
#   destino  (padrão: ./models)
#   variante (padrão: openai_whisper-large-v3-v20240930_turbo)
#            alternativas menores: openai_whisper-large-v3-v20240930_turbo_632MB, openai_whisper-small
set -euo pipefail

DEST="${1:-$(cd "$(dirname "$0")/.." && pwd)/models}"
VARIANT="${2:-openai_whisper-large-v3-v20240930_turbo}"
REPO="argmaxinc/whisperkit-coreml"
HF="https://huggingface.co"

case "$VARIANT" in
  *large-v3*) TOKENIZER_REPO="openai/whisper-large-v3" ;;
  *large-v2*) TOKENIZER_REPO="openai/whisper-large-v2" ;;
  *medium*)   TOKENIZER_REPO="openai/whisper-medium" ;;
  *small*)    TOKENIZER_REPO="openai/whisper-small" ;;
  *base*)     TOKENIZER_REPO="openai/whisper-base" ;;
  *tiny*)     TOKENIZER_REPO="openai/whisper-tiny" ;;
  *) echo "Variante desconhecida: $VARIANT" >&2; exit 1 ;;
esac

OUT="$DEST/$VARIANT"
mkdir -p "$OUT"
echo "Baixando $REPO/$VARIANT para $OUT"

# Lista os arquivos da variante pela API pública do Hugging Face.
FILES=$(curl -fsSL "$HF/api/models/$REPO/tree/main/$VARIANT?recursive=true" |
  /usr/bin/python3 -c 'import json,sys; [print(f["path"]) for f in json.load(sys.stdin) if f["type"]=="file"]')

for path in $FILES; do
  rel="${path#"$VARIANT"/}"
  target="$OUT/$rel"
  mkdir -p "$(dirname "$target")"
  if [ -s "$target" ]; then
    echo "  ok   $rel"
    continue
  fi
  echo "  ↓    $rel"
  curl -fL --retry 3 --progress-bar -o "$target.part" "$HF/$REPO/resolve/main/$path"
  mv "$target.part" "$target"
done

for f in tokenizer.json tokenizer_config.json; do
  if [ ! -s "$OUT/$f" ]; then
    echo "  ↓    $f ($TOKENIZER_REPO)"
    curl -fsSL --retry 3 -o "$OUT/$f" "$HF/$TOKENIZER_REPO/resolve/main/$f"
  fi
done

for required in AudioEncoder.mlmodelc TextDecoder.mlmodelc MelSpectrogram.mlmodelc tokenizer.json; do
  [ -e "$OUT/$required" ] || { echo "Faltando $required em $OUT" >&2; exit 1; }
done

du -sh "$OUT"
echo
echo "Pronto. No Gravador: Preferências › Transcrição › Importar modelo… → $OUT"
