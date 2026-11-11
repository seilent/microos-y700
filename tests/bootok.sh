#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
tree=${MICROOS_TREE:-$here/../system_files}
bootok=$tree/usr/libexec/microos/microos-boot-ok
bootlog=$tree/usr/libexec/microos/microos-bootlog
applied=$tree/usr/libexec/microos/microos-update-applied
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
rc=0
fail() { echo "FAIL: $*" >&2; rc=1; }

export MICROOS_RUNDIR=$tmp/run MICROOS_STATEDIR=$tmp/state MICROOS_ESP=$tmp/esp FAKE_STATE=$tmp/fake
export MICROOS_BOOT_OK_CONF=$tree/usr/lib/microos/boot-ok.conf
export MICROOS_CMDLINE=$tmp/proc-cmdline MICROOS_BOOT_B=$tmp/boot_b MICROOS_NVMEM_ROOT=$tmp/nvmem MICROOS_SDAM_TRIES=1
export MICROOS_SDAM_LIB=$tree/usr/libexec/microos/microos-sdam MICROOS_STUB_CONF=$tree/usr/lib/microos/stub.conf
export MICROOS_DEVMEM=$tmp/mem MICROOS_DEVMEM_BASE=0xd60a0000 MICROOS_STUB_WAIT=2
export MICROOS_SLOT_CONF=$tmp/slot.conf MICROOS_SLOT=$here/bootok/bin/microos-slot
export MICROOS_BOOT_OK_HOLD=0 MICROOS_BOOT_OK_STEP=1 MICROOS_BOOT_OK_WAIT=2
export PATH=$here/bootok/bin:$PATH

c() { local s; s=$(printf '%064d' 0); echo "${s//0/$1}"; }
P=$(c a).0
B=$(c b).0
H=$(c 9).0
C=$(c c).0
D=$(c d).0

flag() { if [[ $1 == *$2* ]]; then echo true; else echo false; fi; }
st() {
  local e id fl i=0 sep=""
  {
    printf '{"deployments":['
    for e; do
      id=${e%% *}
      fl=${e#"$id"}
      printf '%s{"checksum":"%s","serial":%s,"index":%d,"booted":%s,"pinned":%s,"staged":%s}' "$sep" \
        "${id%.*}" "${id##*.}" "$i" "$(flag "$fl" b)" "$(flag "$fl" p)" "$(flag "$fl" s)"
      sep=,
      i=$((i + 1))
    done
    printf ']}\n'
  } > "$FAKE_STATE/status.json"
}
ID=0123456789ab
le32() { printf "$(printf '\\x%02x' $(( $1 & 0xff )) $(( $1 >> 8 & 0xff )) $(( $1 >> 16 & 0xff )) $(( $1 >> 24 & 0xff )))"; }
put() { dd of="$1" bs=1 seek="$(( $2 ))" conv=notrunc status=none; }
mem32() { le32 "$2" | put "$MICROOS_DEVMEM" "$1"; }
memword() { od -An -tu4 -j "$(( $1 ))" -N4 "$MICROOS_DEVMEM" | tr -d ' '; }
sdam() { od -An -tx1 -j72 -N1 "$MICROOS_NVMEM_ROOT/spmi_sdam1/nvmem" | tr -d ' \n'; }
attempts() { cat "$MICROOS_ESP/microos/boot-attempts" 2> /dev/null || echo none; }
slotlog() { cat "$FAKE_STATE/slot.log" 2> /dev/null || true; }
has() { grep -qF -- "$1" "$tmp/out"; }
bootimg() {
  local cmd=$1 ver=${2:-2}
  rm -f "$MICROOS_BOOT_B"
  truncate -s 4096 "$MICROOS_BOOT_B"
  printf 'ANDROID!' | put "$MICROOS_BOOT_B" 0
  le32 "$ver" | put "$MICROOS_BOOT_B" 40
  printf '%s' "${cmd:0:511}" | put "$MICROOS_BOOT_B" 64
  printf '%s' "${cmd:511}" | put "$MICROOS_BOOT_B" 608
}
stub() { mem32 0x2000 $(( 0x5744 << 16 | $1 )); mem32 0x2004 "$2"; }
responder() {
  for _ in $(seq 1 50); do
    if [[ $(memword 0x2040) == $(( 0x4449534d )) ]]; then
      stub 3 9
      return
    fi
    sleep 0.1
  done
}
reset() {
  rm -rf "$MICROOS_RUNDIR" "$MICROOS_STATEDIR" "$MICROOS_ESP" "$FAKE_STATE/status.json" "$FAKE_STATE/reads" \
    "$FAKE_STATE/events" "$FAKE_STATE/ostree.log" "$FAKE_STATE/lockprobe" "$FAKE_STATE/shifted" "$FAKE_STATE/shifted-pin" \
    "$FAKE_STATE/stages" "$FAKE_STATE/system-reads" "$FAKE_STATE/slot.log" "$MICROOS_NVMEM_ROOT" "$MICROOS_DEVMEM" "$MICROOS_BOOT_B"
  mkdir -p "$MICROOS_RUNDIR" "$MICROOS_STATEDIR" "$MICROOS_ESP/microos" "$FAKE_STATE" "$MICROOS_NVMEM_ROOT/spmi_sdam1" "$tmp/dt/nvram@7100"
  head -c 256 /dev/zero > "$MICROOS_NVMEM_ROOT/spmi_sdam1/nvmem"
  printf '\005' | put "$MICROOS_NVMEM_ROOT/spmi_sdam1/nvmem" 72
  ln -sfn "$tmp/dt/nvram@7100" "$MICROOS_NVMEM_ROOT/spmi_sdam1/of_node"
  truncate -s $(( 0x3000 )) "$MICROOS_DEVMEM"
  echo "root=PARTLABEL=microos rootwait ro init=/init microos.id=$ID" > "$tmp/proc-cmdline"
  echo "$ID 2" > "$MICROOS_ESP/microos/boot-attempts"
  bootimg "root=PARTLABEL=microos microos.id=ba9876543210"
  echo MICROOS_SLOT_WRITE=0 > "$MICROOS_SLOT_CONF"
}
is_pinned() { jq -e --arg id "$1" 'any(.deployments[]; .pinned and "\(.checksum).\(.serial)" == $id)' "$FAKE_STATE/status.json" > /dev/null; }
pins() { paste -sd, "$MICROOS_STATEDIR/boot-ok-pins" 2> /dev/null || true; }
events() { cat "$FAKE_STATE/events" 2> /dev/null || true; }
writes() { grep -E '^ostree admin (pin|undeploy)' "$FAKE_STATE/ostree.log" 2> /dev/null || true; }
run() { "$bootok" > "$tmp/out" 2>&1; }
run_rc() { r=0; run || r=$?; }

mkdir -p "$FAKE_STATE"

reset
st "$B b" "$P p"
echo "$P" > "$MICROOS_STATEDIR/boot-ok-pins"
echo "$P" > "$MICROOS_STATEDIR/confirmed"
MICROOS_BOOT_OK_HOLD=2 run || fail "criterion pass: $(cat "$tmp/out")"
mapfile -t ev < <(events)
[[ ${ev[0]:-} == "pin booted pins=$P,$B confirmed=$P" ]] || fail "first event is not the pin after the append: ${ev[0]:-}"
[[ ${ev[1]:-} == "unpin 1 $P" ]] || fail "second event is not the unpin of the listed id: ${ev[1]:-}"
(( ${#ev[@]} == 2 )) || fail "extra events: $(events)"
[[ $(pins) == "$B" ]] || fail "boot-ok-pins after a pass: $(pins)"
[[ $(cat "$MICROOS_STATEDIR/confirmed") == "$B" ]] || fail "confirmed after a pass"
is_pinned "$B" || fail "booted not pinned after a pass"
is_pinned "$P" && fail "listed id still pinned after a pass"
[[ $(cat "$FAKE_STATE/lockprobe") == held ]] || fail "update.lock was free while ostree ran"
[[ $(tail -n 1 "$tmp/out") == "microos-boot-ok: confirmed $B" ]] || fail "last line: $(tail -n 1 "$tmp/out")"

reset
st "$B b"
( exec 7> "$MICROOS_RUNDIR/update.lock"; flock 7; exec sleep 4 ) &
holder=$!
sleep 0.3
run &
pid=$!
sleep 2
[[ -z $(writes) ]] || fail "ostree pin while update.lock was held"
wait "$pid" || fail "boot ok after the lock was released: $(cat "$tmp/out")"
wait "$holder" || true
is_pinned "$B" || fail "booted not pinned after the lock wait"
reset
st "$B b"
( exec 7> "$MICROOS_RUNDIR/update.lock"; flock 7; exec sleep 5 ) &
holder=$!
sleep 0.3
r=0
MICROOS_BOOT_OK_LOCK_WAIT=1 run || r=$?
(( r == 3 )) || fail "lock timeout exit $r"
grep -q "not confirmed: update.lock busy" "$tmp/out" || fail "lock timeout message: $(cat "$tmp/out")"
[[ -z $(writes) ]] || fail "ostree write on a lock timeout"
kill "$holder" 2> /dev/null || true
wait "$holder" 2> /dev/null || true

reset
st "$B b" "$P p"
echo "$P" > "$MICROOS_STATEDIR/boot-ok-pins"
FAKE_SYSTEM=degraded FAKE_FAILED_UNITS="NetworkManager.service foo.service" MICROOS_BOOT_OK_HOLD=2 run_rc
(( r == 1 )) || fail "failed unit exit $r"
has "not confirmed: failed: NetworkManager.service foo.service after 2 s" || fail "failed unit message: $(cat "$tmp/out")"
[[ -z $(writes) && -z $(events) ]] || fail "a failed unit still pinned: $(events)"
[[ ! -e $MICROOS_RUNDIR/boot-confirmed ]] || fail "boot-confirmed written with a failed unit"
reset
st "$B b"
FAKE_SYSTEM=degraded FAKE_FAILED_UNITS="foo.service" MICROOS_BOOT_OK_ALLOW="bar.service foo.service" MICROOS_BOOT_OK_HOLD=2 run \
  || fail "degraded with an allowed failure: $(cat "$tmp/out")"
reset
st "$B b"
FAKE_STARTING=2 run || fail "system running after a wait: $(cat "$tmp/out")"
reset
st "$B b"
FAKE_DEGRADED_AFTER=2 FAKE_FAILED_UNITS=sshd.service MICROOS_BOOT_OK_HOLD=3 run_rc
(( r == 1 )) || fail "failure in the hold: exit $r"
has "not confirmed: failed: sshd.service after 2 s of the hold" || fail "hold failure message: $(cat "$tmp/out")"

reset
st "$B b"
FAKE_INACTIVE=sshd.service FAKE_COND_NO=sshd.service MICROOS_BOOT_OK_HOLD=2 run || fail "sshd with ConditionResult=no: $(cat "$tmp/out")"
reset
st "$B b"
FAKE_INACTIVE=sshd.service MICROOS_BOOT_OK_HOLD=2 run_rc
(( r == 1 )) || fail "sshd inactive with ConditionResult=yes: exit $r"
[[ -z $(writes) ]] || fail "inactive sshd still pinned"

reset
st "$B b"
t0=$SECONDS
FAKE_SYSTEM=starting run_rc
(( r == 1 )) || fail "system never running: exit $r"
(( SECONDS - t0 >= 2 )) || fail "system wait shorter than MICROOS_BOOT_OK_WAIT"
has "not confirmed: system starting after 2 s" || fail "gate timeout message: $(cat "$tmp/out")"
stub 2 7
[[ ! -e $MICROOS_RUNDIR/boot-confirmed && $(attempts) == "$ID 2" && $(sdam) == 05 && $(memword 0x2040) == 0 ]] \
  || fail "gate timeout acted: counter $(attempts), sdam $(sdam), disarm $(memword 0x2040)"

reset
st "$B b" "$P p"
echo "$P" > "$MICROOS_STATEDIR/boot-ok-pins"
for f in "$MICROOS_RUNDIR/deployments" "$MICROOS_STATEDIR/confirmed" "$MICROOS_STATEDIR/boot-ok-pins"; do
  echo keep > "$tmp/target-${f##*/}"
  echo keep > "$tmp/target-${f##*/}.tmp"
  ln -s "$tmp/target-${f##*/}.tmp" "$f.tmp"
done
ln -s "$tmp/target-deployments" "$MICROOS_RUNDIR/deployments"
ln -s "$tmp/target-confirmed" "$MICROOS_STATEDIR/confirmed"
run || fail "pass with planted links: $(cat "$tmp/out")"
for f in "$MICROOS_RUNDIR/deployments" "$MICROOS_STATEDIR/confirmed" "$MICROOS_STATEDIR/boot-ok-pins"; do
  [[ $(cat "$tmp/target-${f##*/}") == keep && $(cat "$tmp/target-${f##*/}.tmp") == keep ]] || fail "planted link at $f followed"
  [[ -f $f && ! -L $f ]] || fail "$f not replaced by a file"
done
[[ $(cat "$MICROOS_STATEDIR/confirmed") == "$B" ]] || fail "confirmed after planted links"
[[ $(head -n 1 "$MICROOS_RUNDIR/deployments") == "booted=$B" ]] || fail "deployments after planted links"
[[ -z $(find "$MICROOS_RUNDIR" "$MICROOS_STATEDIR" -name '*.??????' -type f) ]] || fail "temp files left"

reset
st "$B b" "$P p"
echo "$P" > "$MICROOS_STATEDIR/boot-ok-pins"
echo "$B" > "$MICROOS_STATEDIR/boot-ok-skip"
run_rc
(( r == 3 )) || fail "skip file naming the booted deployment: exit $r"
[[ $(tail -n 1 "$tmp/out") == "microos-boot-ok: skipped once" ]] || fail "skip message: $(cat "$tmp/out")"
[[ ! -e $MICROOS_STATEDIR/boot-ok-skip ]] || fail "skip file kept after a skip"
[[ -z $(writes) && -z $(events) ]] || fail "pinned on a skip: $(events)"
[[ ! -e $MICROOS_RUNDIR/boot-confirmed && $(attempts) == "$ID 2" ]] || fail "skip confirmed the boot"
[[ ! -e $MICROOS_STATEDIR/confirmed ]] || fail "confirmed written on a skip"
[[ $(pins) == "$P" ]] || fail "boot-ok-pins changed on a skip: $(pins)"
run || fail "pass after a skip: $(cat "$tmp/out")"
is_pinned "$B" || fail "booted not pinned after a skip"
is_pinned "$P" && fail "P still pinned after the pass after a skip"
reset
st "$B b" "$P p"
echo "$P" > "$MICROOS_STATEDIR/boot-ok-pins"
echo "$C" > "$MICROOS_STATEDIR/boot-ok-skip"
run || fail "skip file naming another deployment: $(cat "$tmp/out")"
[[ ! -e $MICROOS_STATEDIR/boot-ok-skip ]] || fail "skip file kept after a mismatch"
grep -q "boot-ok-skip names '$C', booted $B, not skipped" "$tmp/out" || fail "skip mismatch message: $(cat "$tmp/out")"
is_pinned "$B" || fail "booted not pinned after a skip mismatch"
[[ $(pins) == "$B" ]] || fail "boot-ok-pins after a skip mismatch: $(pins)"

reset
st "$B b" "$P p" "$H p"
echo "$P" > "$MICROOS_STATEDIR/boot-ok-pins"
run || fail "pass with a hand pin: $(cat "$tmp/out")"
is_pinned "$H" || fail "hand pin dropped"
grep -q "$H" "$MICROOS_STATEDIR/boot-ok-pins" && fail "hand pin listed"
reset
st "$H b p"
run || fail "pass with a hand pinned booted: $(cat "$tmp/out")"
[[ -z $(pins) ]] || fail "hand pinned booted listed: $(pins)"
st "$B b" "$H p"
run || fail "pass after a hand pinned booted: $(cat "$tmp/out")"
is_pinned "$H" || fail "hand pinned deployment unpinned by a later boot ok"
[[ $(pins) == "$B" ]] || fail "boot-ok-pins after the later boot ok: $(pins)"

reset
st "$B b" "$P p"
echo "$P" > "$MICROOS_STATEDIR/boot-ok-pins"
FAKE_STAGE_ON_READ=3 run || fail "pass with a stage inside the window: $(cat "$tmp/out")"
grep -qE '^ostree admin pin [0-9]' "$FAKE_STATE/ostree.log" && fail "pin by index"
grep -q "^unpin [0-9]* $B" "$FAKE_STATE/events" && fail "booted unpinned"
is_pinned "$B" || fail "booted not pinned after a stage"
is_pinned "$P" && fail "P pinned after a stage"
reset
st "$B b" "$P p"
echo "$P" > "$MICROOS_STATEDIR/boot-ok-pins"
FAKE_SHIFT_ON_UNPIN=1 run || fail "pass with an index shift: $(cat "$tmp/out")"
grep -q "^unpin 1 $B" "$FAKE_STATE/events" || fail "the shift did not hit booted: $(events)"
[[ $(grep -c '^pin booted' "$FAKE_STATE/events") == 2 ]] || fail "booted not pinned again after the shift: $(events)"
is_pinned "$B" || fail "booted not pinned after the shift"
is_pinned "$P" && fail "P pinned after the shift"
[[ $(pins) == "$B" ]] || fail "boot-ok-pins after the shift: $(pins)"
npinned() { jq '[.deployments[] | select(.pinned)] | length' "$FAKE_STATE/status.json"; }
U=$(c 8).0
reset
st "$B b" "$H p" "$P p"
echo "$P" > "$MICROOS_STATEDIR/boot-ok-pins"
FAKE_SHIFT_ON_UNPIN=1 run || fail "pass with a shift onto a hand pin: $(cat "$tmp/out")"
grep -q "^unpin 2 $H" "$FAKE_STATE/events" || fail "the shift did not hit the hand pin: $(events)"
grep -q "^pin [0-9]* $H" "$FAKE_STATE/events" || fail "hand pin not pinned again by its id: $(events)"
{ is_pinned "$B" && is_pinned "$H"; } || fail "booted or hand pin lost after a shift"
is_pinned "$P" && fail "P pinned after a shift onto a hand pin"
[[ $(npinned) == 2 ]] || fail "extra pins after a shift onto a hand pin: $(npinned)"
[[ $(pins) == "$B" ]] || fail "boot-ok-pins after a shift onto a hand pin: $(pins)"
reset
st "$B b p" "$U" "$H p" "$P p"
echo "$P" > "$MICROOS_STATEDIR/boot-ok-pins"
FAKE_SHIFT_ON_UNPIN=1 FAKE_SHIFT_ON_PIN=1 run || fail "pass with two shifts: $(cat "$tmp/out")"
grep -q "^pin [0-9]* $U" "$FAKE_STATE/events" || fail "the second shift did not pin U: $(events)"
grep -q "^unpin [0-9]* $U" "$FAKE_STATE/events" || fail "the leaked pin on U was not removed: $(events)"
{ is_pinned "$B" && is_pinned "$H"; } || fail "booted or hand pin lost after two shifts"
is_pinned "$U" && fail "pin leaked onto U"
is_pinned "$P" && fail "P pinned after two shifts"
[[ $(npinned) == 2 ]] || fail "extra pins after two shifts: $(npinned)"

reset
st "$B b p"
echo "$B" > "$MICROOS_STATEDIR/boot-ok-pins"
echo "$B" > "$MICROOS_STATEDIR/confirmed"
run || fail "pass with nothing to do: $(cat "$tmp/out")"
[[ -z $(writes) ]] || fail "pin or unpin with nothing to do: $(writes)"
[[ -z $(events) ]] || fail "events with nothing to do: $(events)"

reset
st "$B b"
run || fail "RAM boot: $(cat "$tmp/out")"
has "RAM boot of $ID" || fail "RAM boot not detected: $(cat "$tmp/out")"
[[ $(attempts) == "$ID 0" ]] || fail "RAM boot counter: $(attempts)"
[[ $(sdam) == 01 ]] || fail "RAM boot preset byte $(sdam)"
[[ $(cat "$MICROOS_RUNDIR/boot-confirmed") == "$B" ]] || fail "RAM boot boot-confirmed"
has "no stub, status word 0x0" || fail "missing stub not reported: $(cat "$tmp/out")"
[[ $(memword 0x2040) == 0 ]] || fail "disarm written with no stub"
[[ -z $(slotlog) ]] || fail "RAM boot ran microos-slot: $(slotlog)"
[[ $(tail -n 1 "$tmp/out") == "microos-boot-ok: confirmed $B" ]] || fail "RAM boot last line: $(tail -n 1 "$tmp/out")"
reset
st "$B b"
echo MICROOS_SLOT_WRITE=1 > "$MICROOS_SLOT_CONF"
run || fail "RAM boot with slot writes on: $(cat "$tmp/out")"
[[ -z $(slotlog) ]] || fail "RAM boot with slot writes on ran microos-slot: $(slotlog)"

reset
st "$B b"
bootimg "root=PARTLABEL=microos rootwait microos.id=$ID loglevel=4"
run || fail "flash boot: $(cat "$tmp/out")"
has "flash boot of $ID" || fail "flash boot not detected: $(cat "$tmp/out")"
has "slot writes are off, boot_b not marked good" || fail "slot writes off not reported: $(cat "$tmp/out")"
[[ -z $(slotlog) && $(attempts) == "$ID 0" && $(sdam) == 01 ]] || fail "flash boot, slot off: $(slotlog), $(attempts), $(sdam)"
reset
st "$B b"
bootimg "root=PARTLABEL=microos microos.id=$ID"
echo MICROOS_SLOT_WRITE=1 > "$MICROOS_SLOT_CONF"
run || fail "flash boot with slot writes on: $(cat "$tmp/out")"
[[ $(slotlog) == "microos-slot mark-good" ]] || fail "mark-good not run: $(slotlog)"
has "boot_b marked good" || fail "mark-good not reported: $(cat "$tmp/out")"
reset
st "$B b"
bootimg "root=PARTLABEL=microos microos.id=$ID"
echo MICROOS_SLOT_WRITE=1 > "$MICROOS_SLOT_CONF"
FAKE_SLOT_RC=1 run || fail "flash boot with a failing microos-slot: $(cat "$tmp/out")"
has "microos-slot mark-good failed" || fail "mark-good failure not reported: $(cat "$tmp/out")"
[[ -e $MICROOS_RUNDIR/boot-confirmed ]] || fail "no boot-confirmed after a mark-good failure"
reset
st "$B b"
bootimg "root=PARTLABEL=microos microos.id=$ID"
echo MICROOS_SLOT_WRITE=1 > "$MICROOS_SLOT_CONF"
MICROOS_SLOT=$tmp/missing run || fail "flash boot with no microos-slot: $(cat "$tmp/out")"
has "$tmp/missing is missing, boot_b not marked good" || fail "missing microos-slot not reported: $(cat "$tmp/out")"
reset
st "$B b"
long=$(printf 'x%.0s' {1..520})
bootimg "root=PARTLABEL=microos $long microos.id=$ID"
echo MICROOS_SLOT_WRITE=1 > "$MICROOS_SLOT_CONF"
run || fail "flash boot with extra_cmdline: $(cat "$tmp/out")"
[[ $(slotlog) == "microos-slot mark-good" ]] || fail "id in extra_cmdline not found: $(cat "$tmp/out")"
reset
st "$B b"
bootimg "root=PARTLABEL=microos microos.id=$ID" 3
echo MICROOS_SLOT_WRITE=1 > "$MICROOS_SLOT_CONF"
run || fail "v3 boot_b: $(cat "$tmp/out")"
has "header version 3, cmdline not read" && has "RAM boot of $ID" || fail "v3 boot_b: $(cat "$tmp/out")"
[[ -z $(slotlog) ]] || fail "v3 boot_b ran microos-slot"
reset
st "$B b"
rm "$MICROOS_BOOT_B"
run || fail "no boot_b: $(cat "$tmp/out")"
has "RAM boot of $ID" || fail "no boot_b: $(cat "$tmp/out")"
reset
st "$B b"
echo "root=PARTLABEL=microos" > "$tmp/proc-cmdline"
run || fail "no microos.id: $(cat "$tmp/out")"
[[ $(attempts) == "$ID 2" ]] || fail "counter changed with no microos.id: $(attempts)"

reset
st "$B b"
stub 2 7
responder &
resp=$!
run || fail "stub present: $(cat "$tmp/out")"
wait "$resp" || true
[[ $(memword 0x2040) == $(( 0x4449534d )) ]] || fail "disarm word $(memword 0x2040)"
has "stub stopped at 9 s" || fail "stub stop not reported: $(cat "$tmp/out")"
reset
st "$B b"
stub 2 7
t0=$SECONDS
run || fail "stub that does not stop: $(cat "$tmp/out")"
(( SECONDS - t0 >= 2 )) || fail "stub wait shorter than MICROOS_STUB_WAIT"
has "stub still running at 7 s after the disarm, it resets at 1200 s" || fail "running stub not reported: $(cat "$tmp/out")"
reset
st "$B b"
stub 4 $(( 0xfffffffe ))
run || fail "stub refused: $(cat "$tmp/out")"
has "stub CPU_ON was refused, PSCI 4294967294" || fail "refused stub not reported: $(cat "$tmp/out")"
[[ $(memword 0x2040) == 0 ]] || fail "disarm written for a refused stub"
reset
st "$B b"
MICROOS_DEVMEM=$tmp/nomem run || fail "no devmem: $(cat "$tmp/out")"
has "stub words not reachable through $tmp/nomem" || fail "devmem failure not reported: $(cat "$tmp/out")"
reset
st "$B b"
rm "$MICROOS_NVMEM_ROOT/spmi_sdam1/of_node"
run || fail "no SDAM: $(cat "$tmp/out")"
has "fastboot preset not cleared, no SDAM nvram@7100" || fail "missing SDAM not reported: $(cat "$tmp/out")"

export MICROOS_BOOT=$tmp/bootfs MICROOS_CMDLINE=$tmp/cmdline MICROOS_BOOTID=$tmp/bootid
log=$MICROOS_BOOT/microos/shutdown.log
echo "ostree=/ostree/boot.1/default/x/0 quiet microos.deploy=$B" > "$MICROOS_CMDLINE"
echo "0123456789abcdef-rest" > "$MICROOS_BOOTID"
rm -f "$FAKE_STATE/bootc.log.bootlog"
mkdir -p "$MICROOS_BOOT"
bootc_calls=$(wc -l < "$FAKE_STATE/bootc.log" 2> /dev/null || echo 0)

r=0
out=$(FAKE_MOUNT_FAIL=1 "$bootlog" run step1 -- sh -c 'echo hi; exit 5' 2>&1) || r=$?
(( r == 5 )) || fail "bootlog with ro /boot: exit $r"
[[ $out == *"warning: no "* ]] || fail "bootlog with ro /boot: no warning: $out"
[[ ! -e $log ]] || fail "bootlog wrote with ro /boot"

r=0
out=$("$bootlog" run step2 -- sh -c 'echo first; echo second; exit 4' 2> /dev/null) || r=$?
(( r == 4 )) || fail "bootlog exit $r"
[[ $out == $'first\nsecond' ]] || fail "bootlog output: $out"
line=$(tail -n 1 "$log")
[[ $line =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z\ boot=01234567\ step=step2\ rc=4\ booted=$B\ second$ ]] || fail "bootlog line: $line"
echo "quiet" > "$MICROOS_CMDLINE"
"$bootlog" run step3 -- true || fail "bootlog of true"
[[ $(tail -n 1 "$log") == *" step=step3 rc=0 booted=unknown "* ]] || fail "bootlog without microos.deploy: $(tail -n 1 "$log")"

seq 1 200000 | sed 's/^/padding line /' > "$log"
"$bootlog" run trim -- echo trimmed > /dev/null || fail "bootlog trim run"
[[ $(wc -l < "$log") == 2000 ]] || fail "trimmed log has $(wc -l < "$log") lines"
[[ $(tail -n 1 "$log") == *" step=trim rc=0 "*" trimmed" ]] || fail "trimmed log last line"

: > "$log"
"$bootlog" run para1 -- sh -c 'sleep 0.5; echo one' > /dev/null &
p1=$!
"$bootlog" run para2 -- sh -c 'sleep 0.5; echo two' > /dev/null &
p2=$!
wait "$p1" "$p2"
{ grep -q ' step=para1 .* one$' "$log" && grep -q ' step=para2 .* two$' "$log"; } || fail "concurrent lines: $(cat "$log")"

r=0
"$bootlog" run killed -- sh -c 'kill -TERM $$' > /dev/null 2>&1 || r=$?
(( r == 143 )) || fail "command killed by SIGTERM: exit $r"
[[ $(tail -n 1 "$log") == *" step=killed rc=143 "* ]] || fail "SIGTERM status not logged: $(tail -n 1 "$log")"

out=$("$bootlog" run big -- seq 1 300000 2> /dev/null) || fail "big output run"
[[ $out == "$(seq 1 300000)" ]] || fail "big output not printed in full"

"$bootlog" run term -- sh -c 'echo early; exec sleep 30' > "$tmp/termout" 2>&1 &
pid=$!
sleep 1
t0=$SECONDS
kill -TERM "$pid"
r=0
wait "$pid" || r=$?
(( r == 143 )) || fail "bootlog under SIGTERM: exit $r"
(( SECONDS - t0 <= 5 )) || fail "bootlog under SIGTERM took $((SECONDS - t0)) s"
grep -qx early "$tmp/termout" || fail "bootlog under SIGTERM lost the output: $(cat "$tmp/termout")"
[[ $(tail -n 1 "$log") == *" step=term rc=143 "*" early" ]] || fail "bootlog under SIGTERM line: $(tail -n 1 "$log")"

"$bootlog" run abrt -- sh -c 'echo early; exec sleep 30' > "$tmp/abrtout" 2>&1 &
pid=$!
sleep 1
kill -ABRT "$pid"
r=0
wait "$pid" || r=$?
(( r == 134 )) || fail "bootlog under SIGABRT: exit $r"
grep -qx early "$tmp/abrtout" || fail "bootlog under SIGABRT lost the output: $(cat "$tmp/abrtout")"
[[ $(tail -n 1 "$log") == *" step=abrt rc=134 "*" early" ]] || fail "bootlog under SIGABRT line: $(tail -n 1 "$log")"

( exec 7> "$MICROOS_RUNDIR/bootlog.lock"; flock 7; exec sleep 10 ) &
holder=$!
sleep 0.3
t0=$SECONDS
r=0
"$bootlog" run held -- sh -c 'exit 6' > /dev/null 2>&1 || r=$?
(( r == 6 )) || fail "bootlog with a held lock: exit $r"
(( SECONDS - t0 <= 5 )) || fail "bootlog with a held lock took $((SECONDS - t0)) s"
grep -q ' step=held ' "$log" && fail "bootlog wrote under a held lock"
kill "$holder" 2> /dev/null || true
wait "$holder" 2> /dev/null || true

[[ $(wc -l < "$FAKE_STATE/bootc.log" 2> /dev/null || echo 0) == "$bootc_calls" ]] || fail "bootlog called bootc"
unset MICROOS_BOOT MICROOS_CMDLINE MICROOS_BOOTID

reset
st "$B b"
nap=$MICROOS_RUNDIR/update-not-applied
exp=$MICROOS_STATEDIR/expected-deployment
digest=sha256:$(c 1)
other=sha256:$(c 2)
"$applied" > /dev/null || fail "update applied with no expected file"
[[ ! -e $nap ]] || fail "not applied written with no expected file"
printf 'deploy=%s\ndigest=%s\nversion=20261013.abc\nimage=ghcr.io/seilent/microos-y700:testing\nstaged=2026-10-13T00:00:00Z\n' "$B" "$other" > "$exp"
echo stale > "$nap"
"$applied" > /dev/null || fail "update applied by id"
[[ ! -e $exp && ! -e $nap ]] || fail "files kept after an applied id"
printf 'deploy=%s\ndigest=%s\nversion=20261013.abc\n' "$C" "$digest" > "$exp"
echo stale > "$nap"
"$applied" > /dev/null || fail "update applied by digest"
[[ ! -e $exp && ! -e $nap ]] || fail "files kept after an applied digest"
printf 'deploy=%s\ndigest=%s\nversion=20261013.abc\n' "$C" "$other" > "$exp"
out=$("$applied" 2>&1) || fail "update not applied run"
[[ -e $exp ]] || fail "expected file removed when not applied"
[[ $(cat "$nap" 2> /dev/null) == "expected=$C"$'\n'"booted=$B"$'\n'"digest=$other"$'\n'"version=20261013.abc" ]] || fail "not applied file: $(cat "$nap" 2> /dev/null)"
[[ $out == *"microos-update-applied: expected $C, booted $B"* ]] || fail "not applied message: $out"

! grep -q rollback "$FAKE_STATE/bootc.log" 2> /dev/null || fail "bootc rollback was called"

if (( rc == 0 )); then
  echo "bootok: ok"
fi
exit "$rc"
