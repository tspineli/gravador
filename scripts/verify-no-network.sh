#!/bin/bash
# Verifica que o Gravador não tem como acessar a rede.
#  1. Assinatura: sandbox ligado e SEM os entitlements network.client / network.server.
#  2. Código: nenhuma API de rede no código do app (Gravador/ e Packages/GravadorCore).
#  3. Execução (se o app estiver aberto): nenhum socket de rede aberto pelo processo.
#
# Uso: scripts/verify-no-network.sh [caminho/Gravador.app]
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/build/Build/Products/Debug/Gravador.app}"
FAIL=0

ok()   { echo "  ✅ $*"; }
fail() { echo "  ❌ $*"; FAIL=1; }

echo "1) Entitlements de $APP"
if [ ! -d "$APP" ]; then
  fail "app não encontrado (rode o build antes)"
else
  ENT=$(codesign -d --entitlements - --xml "$APP" 2>/dev/null)
  if echo "$ENT" | grep -q "com.apple.security.app-sandbox"; then ok "App Sandbox ligado"; else fail "App Sandbox DESLIGADO"; fi
  if echo "$ENT" | grep -q "com.apple.security.network"; then
    fail "possui entitlement de rede: $(echo "$ENT" | grep -o 'com.apple.security.network[a-z.]*' | sort -u | tr '\n' ' ')"
  else
    ok "nenhum entitlement de rede (o macOS bloqueia qualquer conexão)"
  fi
fi

echo "2) APIs de rede no código do app"
PATTERN='URLSession|URLRequest|NWConnection|NWListener|NWBrowser|import Network|CFSocket|CFStream|getaddrinfo|WKWebView|NSURLConnection'
HITS=$(grep -rnE "$PATTERN" "$ROOT/Gravador" "$ROOT/Packages/GravadorCore/Sources" 2>/dev/null)
if [ -n "$HITS" ]; then fail "encontrado:"; echo "$HITS" | sed 's/^/       /'; else ok "nenhuma ocorrência de: ${PATTERN//|/, }"; fi

echo "3) Sockets do processo em execução"
PID=$(pgrep -x Gravador | head -1)
if [ -z "$PID" ]; then
  echo "  ⏭  app não está aberto; pulei"
else
  SOCKETS=$(lsof -nP -a -p "$PID" -i 2>/dev/null | tail -n +2)
  if [ -n "$SOCKETS" ]; then fail "sockets abertos:"; echo "$SOCKETS" | sed 's/^/       /'; else ok "PID $PID sem nenhum socket de rede"; fi
fi

echo
if [ $FAIL -eq 0 ]; then echo "OK: o Gravador não acessa a rede."; else echo "FALHOU: revise os itens acima."; fi
exit $FAIL
