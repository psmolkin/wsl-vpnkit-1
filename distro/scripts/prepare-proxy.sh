#!/bin/sh
set -o errexit -o nounset

CMDSHELL="$(command -v cmd.exe || echo '/mnt/c/Windows/system32/cmd.exe')"
USERPROFILE=$(wslpath "$($CMDSHELL /V:OFF /C 'echo | set /p t=%USERPROFILE%' 2>/dev/null)")
CONF_PATH="$USERPROFILE/wsl-vpnkit/wsl-vpnkit.conf"
CNTLM_CONF_PATH="$USERPROFILE/wsl-vpnkit/cntlm.conf"
HTTP_PROXY_CONFIG_PATH="$USERPROFILE/wsl-vpnkit/http-proxy.json"

echo "starting wsl-vpnkit"
# Load defaults
if [ -f "/app/defaults.conf" ]; then
  . /app/defaults.conf
fi
#  Load user config if needed
if [ -f "$CONF_PATH" ]; then
  . "$CONF_PATH"
  echo "loaded config: $CONF_PATH"
fi

PROXY_HOST=${PROXY_HOST:?PROXY_HOST must be set!}
PROXY_PORT=${PROXY_PORT:-8080}
PROXY_LOCAL_PORT=${PROXY_LOCAL_PORT:-3128}

BASE_CONF="Listen\t\t${PROXY_LOCAL_PORT}\nProxy\t\t${PROXY_HOST}:${PROXY_PORT}"


ln -sf $CNTLM_CONF_PATH "/etc/cntlm.conf"

echo "Test proxy connection"
if ! nc -z "$(getent hosts "${PROXY_HOST}" | awk '{print $1}')" "${PROXY_PORT}"; then
  echo "Proxy '${PROXY_HOST}:${PROXY_PORT}' unreachable!"
  exit 1
fi
echo "Proxy available"

echo "Test proxy auth"
while ! ( cntlm -c "${CNTLM_CONF_PATH}" -M https://www.google.com "${PROXY_HOST}:${PROXY_PORT}" </dev/null |
      tail -1 |
      { read -r _m; echo "$_m"; echo "$_m" | grep -qE '\-+';}) do
  NTLM_USER=$(whoami.exe '/upn' | tr -d "\r")
  echo "Please, enter the password for ${NTLM_USER}"
  echo "(it will stored securely)"
  
  echo -e "$BASE_CONF" >"${CNTLM_CONF_PATH}"
  _passhashline=$(cntlm -u "${NTLM_USER}" -H | grep 'PassNTLMv2')
  echo $_passhashline |
    awk -F'[ ,]' '{printf("Domain\t\t%s\nUsername\t%s\nPassNTLMv2\t%s\n\n", $10, $7,$2)}' |
    tr -d \'\" >>"${CNTLM_CONF_PATH}"

  if grep -qE 'PassNTLMv2\s+F{32}' "${CNTLM_CONF_PATH}"; then
    echo >"${CNTLM_CONF_PATH}"
  fi
done

echo
echo "Your encrypted credentials stored in:"
echo "$(wslpath -m ${CNTLM_CONF_PATH})" 
echo


if [ -f $HTTP_PROXY_CONFIG_PATH ]; then
  cp $HTTP_PROXY_CONFIG_PATH /app/proxy.json
else
  cp /app/proxy.json.def /app/proxy.json
fi