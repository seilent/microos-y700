#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
tree=${MICROOS_TREE:-$here/../system_files}
sink=$tree/usr/libexec/microos/microos-typec-sink
unit=$tree/usr/lib/systemd/system/microos-typec-sink.service
tmp=$(mktemp -d)
pid=
cleanup() {
  [[ -n $pid ]] && kill "$pid" 2> /dev/null || true
  exec 3>&- || true
  rm -rf "${tmp:?}"
}
trap cleanup EXIT
rc=0
fail() { echo "FAIL: $*" >&2; rc=1; }

for l in ExecStart=/usr/libexec/microos/microos-typec-sink Restart=always RuntimeDirectory=microos-typec-sink \
  RuntimeDirectoryPreserve=yes WantedBy=multi-user.target; do
  grep -qxF "$l" "$unit" || fail "microos-typec-sink.service lacks $l"
done
if command -v systemd-analyze > /dev/null && [[ -x /usr/libexec/microos/microos-typec-sink ]]; then
  systemd-analyze verify --man=no --recursive-errors=no "$unit" > "$tmp/verify" 2>&1 || fail "systemd-analyze verify: $(cat "$tmp/verify")"
fi

p=$tmp/typec/port0
mkdir -p "$p" "$tmp/state"
echo "[source] sink" > "$p/power_role"
echo "dual source [sink]" > "$p/port_type"

start() {
  exec 3>&-
  rm -f "$tmp/mon"
  mkfifo "$tmp/mon"
  MICROOS_TYPEC_ROOT=$tmp/typec MICROOS_TYPEC_STATE=$tmp/state MICROOS_TYPEC_MONITOR="cat $tmp/mon" \
    MICROOS_TYPEC_SINK_TRY=0.5 python3 "$sink" 2>> "$tmp/log" &
  pid=$!
  exec 3> "$tmp/mon"
  printf 'monitor will print the received events for:\nKERNEL - the kernel uevent\n\n' >&3
}
stop() {
  kill "$pid"
  wait "$pid" 2> /dev/null || true
  pid=
}
ev() { echo "KERNEL[0.0] $1 /devices/platform/pmic-glink/typec/port0/$2 (typec)" >&3; }
want() {
  for _ in $(seq 40); do
    [[ $(< "$p/port_type") == "$1" ]] && return 0
    sleep 0.05
  done
  return 1
}
keep() {
  sleep "$2"
  [[ $(< "$p/port_type") == "$1" ]]
}
attach() {
  echo "$1" > "$p/power_role"
  ev change port0
  mkdir -p "$p-partner"
  echo "${2:-none}" > "$p-partner/accessory_mode"
  ev add port0-partner
}
detach() {
  rm -rf "${p:?}-partner"
  ev remove port0-partner
}
tries() { grep -c 'trying sink' "$tmp/log" || true; }

start
want dual || fail "startup: port_type $(< "$p/port_type"), not dual"

attach "[source] sink"
want sink || fail "dual role host: port_type $(< "$p/port_type"), not sink"
detach
attach "source [sink]"
keep sink 0.8 || fail "dual role host: port_type $(< "$p/port_type") after the sink attach"
stop
start
keep sink 0.3 || fail "restart while held: port_type $(< "$p/port_type"), not sink"
detach
want dual || fail "dual role host unplug: port_type $(< "$p/port_type"), not dual"

attach "[source] sink"
want sink || fail "device: port_type $(< "$p/port_type"), not sink"
detach
keep dual 0.8 || fail "device: port_type $(< "$p/port_type") after the try, not dual"
attach "[source] sink"
keep dual 0.3 || fail "device reattach: port_type $(< "$p/port_type"), not dual"
stop
start
keep dual 0.3 || fail "restart with the device attached: port_type $(< "$p/port_type"), not dual"
[[ $(tries) == 2 ]] || fail "tries $(tries), not 2 after the device reattach and the restart"
detach
sleep 0.2

attach "[source] sink" analog_audio
keep dual 0.3 || fail "audio accessory: port_type $(< "$p/port_type"), not dual"
detach
sleep 0.2

attach "source [sink]"
keep dual 0.3 || fail "charger: port_type $(< "$p/port_type"), not dual"
echo "[source] sink" > "$p/power_role"
ev change port0
keep dual 0.3 || fail "power role swap: port_type $(< "$p/port_type"), not dual"
[[ $(tries) == 2 ]] || fail "tries $(tries) after the accessory, charger and swap, not 2"
detach
sleep 0.2

rm "$p/port_type"
mkdir "$p/port_type"
attach "[source] sink"
sleep 0.2
detach
attach "[source] sink"
sleep 0.2
[[ $(grep -c 'leaving the port' "$tmp/log") == 1 ]] || fail "port_type write failure logged $(grep -c 'leaving the port' "$tmp/log") times"

kill -0 "$pid" 2> /dev/null || fail "microos-typec-sink exited: $(cat "$tmp/log")"
(( rc == 0 )) || cat "$tmp/log" >&2
exit $rc
