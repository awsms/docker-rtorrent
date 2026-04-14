#!/bin/sh
set -eu

# WAN_IP_CMD=${WAN_IP_CMD:-"dig +short myip.opendns.com @resolver1.opendns.com"}

TZ=${TZ:-UTC}
PUID=${PUID:-1000}
PGID=${PGID:-1000}

RT_BASEDIR=${RT_BASEDIR:-/data/rtorrent}
RT_DOWNLOAD_DIR=${RT_DOWNLOAD_DIR:-/downloads}
RT_DOWNLOAD_COMPLETE_DIR=${RT_DOWNLOAD_COMPLETE_DIR:-${RT_DOWNLOAD_DIR}/complete}
RT_DOWNLOAD_TEMP_DIR=${RT_DOWNLOAD_TEMP_DIR:-${RT_DOWNLOAD_DIR}/temp}
RT_LOG_DIR=${RT_LOG_DIR:-${RT_BASEDIR}/log}
RT_SESSION_DIR=${RT_SESSION_DIR:-${RT_BASEDIR}/.session}
RT_WATCH_DIR=${RT_WATCH_DIR:-${RT_BASEDIR}/watch}
RT_RUNTIME_DIR=${RT_RUNTIME_DIR:-/var/run/rtorrent}

RT_LOG_LEVEL=${RT_LOG_LEVEL:-info}
RT_LOG_EXECUTE=${RT_LOG_EXECUTE:-false}
RT_LOG_XMLRPC=${RT_LOG_XMLRPC:-false}
RT_SESSION_SAVE_SECONDS=${RT_SESSION_SAVE_SECONDS:-3600}
RT_SESSION_FDATASYNC=${RT_SESSION_FDATASYNC:-false}
RT_TRACKER_DELAY_SCRAPE=${RT_TRACKER_DELAY_SCRAPE:-true}
RT_SEND_BUFFER_SIZE=${RT_SEND_BUFFER_SIZE:-4M}
RT_RECEIVE_BUFFER_SIZE=${RT_RECEIVE_BUFFER_SIZE:-4M}
RT_PREALLOCATE_TYPE=${RT_PREALLOCATE_TYPE:-0}

RT_DHT_PORT=${RT_DHT_PORT:-6881}
RT_INC_PORT=${RT_INC_PORT:-50000}

if [ -z "${WAN_IP:-}" ] && [ -n "${WAN_IP_CMD:-}" ] && [ "${WAN_IP_CMD}" != "false" ]; then
  WAN_IP=$(eval "$WAN_IP_CMD")
fi
if [ -n "${WAN_IP:-}" ]; then
  echo "Public IP address enforced to ${WAN_IP}"
fi

trim_slash() {
  printf '%s' "$1" | sed 's:/*$::'
}

RT_BASEDIR=$(trim_slash "${RT_BASEDIR}")
RT_DOWNLOAD_DIR=$(trim_slash "${RT_DOWNLOAD_DIR}")
RT_DOWNLOAD_COMPLETE_DIR=$(trim_slash "${RT_DOWNLOAD_COMPLETE_DIR}")
RT_DOWNLOAD_TEMP_DIR=$(trim_slash "${RT_DOWNLOAD_TEMP_DIR}")
RT_LOG_DIR=$(trim_slash "${RT_LOG_DIR}")
RT_SESSION_DIR=$(trim_slash "${RT_SESSION_DIR}")
RT_WATCH_DIR=$(trim_slash "${RT_WATCH_DIR}")
RT_RUNTIME_DIR=$(trim_slash "${RT_RUNTIME_DIR}")

echo "Setting timezone to ${TZ}..."
ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime
echo "${TZ}" > /etc/timezone

if [ "${PGID}" != "$(id -g rtorrent)" ]; then
  echo "Switching to PGID ${PGID}..."
  sed -i -e "s/^rtorrent:\([^:]*\):[0-9]*/rtorrent:\1:${PGID}/" /etc/group
  sed -i -e "s/^rtorrent:\([^:]*\):\([0-9]*\):[0-9]*/rtorrent:\1:\2:${PGID}/" /etc/passwd
fi
if [ "${PUID}" != "$(id -u rtorrent)" ]; then
  echo "Switching to PUID ${PUID}..."
  sed -i -e "s/^rtorrent:\([^:]*\):[0-9]*:\([0-9]*\)/rtorrent:\1:${PUID}:\2/" /etc/passwd
fi

echo "Fixing perms..."
mkdir -p "${RT_BASEDIR}" \
  "${RT_DOWNLOAD_DIR}" \
  "${RT_RUNTIME_DIR}" \
  /etc/rtorrent \
  /tpls
chown rtorrent:rtorrent "${RT_BASEDIR}" "${RT_DOWNLOAD_DIR}"
chown -R rtorrent:rtorrent /etc/rtorrent /tpls "${RT_RUNTIME_DIR}"
chown "${PUID}:${PGID}" /proc/self/fd/1 /proc/self/fd/2 || true

echo "Update healthcheck script..."
cat > /usr/local/bin/healthcheck <<'EOL'
#!/bin/sh
set -e

[ -s /var/run/rtorrent/rtorrent.pid ]
pid=$(cat /var/run/rtorrent/rtorrent.pid)
kill -0 "${pid}"
[ -S /var/run/rtorrent/scgi.socket ]
EOL
chmod +x /usr/local/bin/healthcheck

echo "Initializing files and folders..."
mkdir -p "${RT_LOG_DIR}" \
  "${RT_SESSION_DIR}" \
  "${RT_WATCH_DIR}" \
  "${RT_DOWNLOAD_COMPLETE_DIR}" \
  "${RT_DOWNLOAD_TEMP_DIR}"
touch "${RT_LOG_DIR}/rtorrent.log"
rm -f "${RT_SESSION_DIR}/rtorrent.lock"

echo "Checking rTorrent local configuration..."
sed -e "s!@RT_LOG_LEVEL@!$RT_LOG_LEVEL!g" \
  -e "s!@RT_DHT_PORT@!$RT_DHT_PORT!g" \
  -e "s!@RT_INC_PORT@!$RT_INC_PORT!g" \
  -e "s!@RT_SESSION_SAVE_SECONDS@!$RT_SESSION_SAVE_SECONDS!g" \
  -e "s!@RT_SESSION_FDATASYNC@!$RT_SESSION_FDATASYNC!g" \
  -e "s!@RT_TRACKER_DELAY_SCRAPE@!$RT_TRACKER_DELAY_SCRAPE!g" \
  -e "s!@RT_SEND_BUFFER_SIZE@!$RT_SEND_BUFFER_SIZE!g" \
  -e "s!@RT_RECEIVE_BUFFER_SIZE@!$RT_RECEIVE_BUFFER_SIZE!g" \
  -e "s!@RT_PREALLOCATE_TYPE@!$RT_PREALLOCATE_TYPE!g" \
  -e "s!@RT_BASEDIR@!$RT_BASEDIR!g" \
  -e "s!@RT_DOWNLOAD_DIR@!$RT_DOWNLOAD_DIR!g" \
  -e "s!@RT_DOWNLOAD_COMPLETE_DIR@!$RT_DOWNLOAD_COMPLETE_DIR!g" \
  -e "s!@RT_DOWNLOAD_TEMP_DIR@!$RT_DOWNLOAD_TEMP_DIR!g" \
  -e "s!@RT_LOG_DIR@!$RT_LOG_DIR!g" \
  -e "s!@RT_SESSION_DIR@!$RT_SESSION_DIR!g" \
  -e "s!@RT_WATCH_DIR@!$RT_WATCH_DIR!g" \
  -e "s!@RT_RUNTIME_DIR@!$RT_RUNTIME_DIR!g" \
  /tpls/etc/rtorrent/.rtlocal.rc > /etc/rtorrent/.rtlocal.rc
if [ "${RT_LOG_EXECUTE}" = "true" ]; then
  echo "  Enabling rTorrent execute log..."
  sed -i "s!#log\.execute.*!log\.execute = (cat,(cfg.logs),\"execute.log\")!g" /etc/rtorrent/.rtlocal.rc
fi
if [ "${RT_LOG_XMLRPC}" = "true" ]; then
  echo "  Enabling rTorrent xmlrpc log..."
  sed -i "s!#log\.xmlrpc.*!log\.xmlrpc = (cat,(cfg.logs),\"xmlrpc.log\")!g" /etc/rtorrent/.rtlocal.rc
fi

echo "Checking rTorrent configuration..."
if [ ! -f "${RT_BASEDIR}/.rtorrent.rc" ]; then
  echo "  Creating default configuration..."
  cp /tpls/.rtorrent.rc "${RT_BASEDIR}/.rtorrent.rc"
fi

echo "Fixing perms..."
chown -R rtorrent:rtorrent \
  "${RT_BASEDIR}" \
  "${RT_DOWNLOAD_DIR}" \
  /etc/rtorrent \
  "${RT_RUNTIME_DIR}"
chmod 644 "${RT_BASEDIR}/.rtorrent.rc" /etc/rtorrent/.rtlocal.rc

cmd="rtorrent -D -o import=/etc/rtorrent/.rtlocal.rc"
if [ -n "${WAN_IP:-}" ]; then
  cmd="${cmd} -i ${WAN_IP}"
fi

cd "${RT_BASEDIR}"
export HOME="${RT_BASEDIR}"
exec su-exec "${PUID}:${PGID}" sh -c "${cmd}"
