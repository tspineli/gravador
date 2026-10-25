#!/bin/bash
# Gera o projeto, compila em Release e instala o Gravador em /Applications.
#
# Uso: scripts/install.sh
# Variáveis opcionais:
#   TEAM=XXXXXXXXXX   Team ID da sua conta Apple Developer (padrão: o do project.yml)
#   ADHOC=1           assina "para rodar localmente", sem conta Apple Developer
#                     (o macOS pede as permissões de novo a cada recompilação)
#   DEST=/Applications  pasta de destino
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${DEST:-/Applications}"
cd "$ROOT"

command -v xcodegen >/dev/null || { echo "Instale o XcodeGen: brew install xcodegen" >&2; exit 1; }
xcode-select -p | grep -q Xcode.app || { echo "Precisa do Xcode completo (não só Command Line Tools)." >&2; exit 1; }

SIGNING=()
if [ "${ADHOC:-0}" = "1" ]; then
  SIGNING=(CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= CODE_SIGN_STYLE=Manual)
elif [ -n "${TEAM:-}" ]; then
  SIGNING=(DEVELOPMENT_TEAM="$TEAM")
fi

echo "→ Gerando o projeto"
xcodegen generate -q

echo "→ Compilando (Release)"
xcodebuild -project Gravador.xcodeproj -scheme Gravador -configuration Release \
  -derivedDataPath build ${SIGNING[@]+"${SIGNING[@]}"} build -quiet

APP="build/Build/Products/Release/Gravador.app"
echo "→ Verificando que o app não tem acesso à rede"
scripts/verify-no-network.sh "$APP" | tail -1

echo "→ Instalando em $DEST"
pkill -x Gravador 2>/dev/null || true
rm -rf "$DEST/Gravador.app"
cp -R "$APP" "$DEST/"
echo
echo "Pronto: open \"$DEST/Gravador.app\""
