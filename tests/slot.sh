#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
tree=${MICROOS_TREE:-$here/../system_files}
slot=$tree/usr/libexec/microos/microos-slot
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
rc=0
fail() { echo "FAIL: $*" >&2; rc=1; }

ss=4096
A=2
B=3
img=$tmp/lun4.img
conf=$tmp/slot.conf

mk() {
  truncate -s 64M "$1"
  {
    echo "label: gpt"
    echo "size=1MiB, name=xbl_a"
    echo "size=1MiB, name=xbl_config_a"
    echo 'size=8MiB, name=boot_a, attrs="RequiredPartition,GUID:48,49,50,51,52,53,54,60"'
    echo 'size=8MiB, name=boot_b, attrs="LegacyBIOSBootable,GUID:48,51,52,55,57"'
    echo "size=1MiB, name=dtbo_a"
    echo "size=1MiB, name=dtbo_b"
    echo "size=4MiB, name=vendor_boot_a"
    echo "size=4MiB, name=vendor_boot_b"
    [[ -z ${2:-} ]] || echo "$2"
  } | sfdisk -q --sector-size "$ss" "$1"
}
u64() { od -An -tu8 -j "$2" -N8 "$1" | tr -d ' '; }
last() { echo $(($(stat -c %s "$1") / ss - 1)); }
hdr() { if [[ $2 == primary ]]; then echo "$ss"; else echo $(($(last "$1") * ss)); fi; }
attr() {
  local h
  h=$(hdr "$1" "$2")
  od -An -tx1 -j $(($(u64 "$1" $((h + 72))) * ss + $3 * 128 + 54)) -N1 "$1" | tr -d ' '
}
state() { echo "$(attr "$1" primary $A) $(attr "$1" backup $A) $(attr "$1" primary $B) $(attr "$1" backup $B)"; }
valid() {
  sfdisk --sector-size "$ss" --verify "$1" > /dev/null 2>&1 && [[ -z $(sfdisk --sector-size "$ss" --dump "$1" 2>&1 > /dev/null) ]]
}
flip() {
  local b
  b=$(od -An -tu1 -j "$2" -N1 "$1" | tr -d ' ')
  printf "\\x$(printf %02x $((b ^ 255)))" | dd of="$1" bs=1 seek="$2" conv=notrunc status=none
}
allowed() {
  local h e
  for c in primary backup; do
    h=$(hdr "$1" $c)
    e=$(($(u64 "$1" $((h + 72))) * ss))
    seq $((h + 16)) $((h + 19))
    seq $((h + 88)) $((h + 91))
    echo $((e + A * 128 + 54))
    echo $((e + B * 128 + 54))
  done > "$tmp/allowed"
}
outside() {
  python3 - "$1" "$2" "$tmp/allowed" << 'EOF'
import sys
a, b = (open(p, "rb").read() for p in sys.argv[1:3])
allowed = {int(x) for x in open(sys.argv[3]).read().split()}
n = abs(len(a) - len(b))
for o in range(0, min(len(a), len(b)), 65536):
    if a[o:o + 65536] != b[o:o + 65536]:
        n += sum(1 for i in range(o, min(o + 65536, len(a), len(b))) if a[i] != b[i] and i not in allowed)
print(n)
EOF
}
same() { [[ $(sha256sum < "$1") == $(sha256sum < "$2") ]]; }
run() {
  env MICROOS_SLOT_TEST=1 MICROOS_SLOT_DISKS="${DISKS:-boot_a=$img boot_b=$img}" MICROOS_SLOT_BLOCK_SIZE="${BS:-$ss}" \
    MICROOS_SLOT_CONF="$conf" "$slot" "$@" > "$tmp/out" 2> "$tmp/err"
}
writes() { printf 'MICROOS_SLOT_WRITE=%s\nMICROOS_BOOT_TRIES=3\n' "$1" > "$conf"; }
has() { grep -qxF "$1" "$tmp/out" || fail "$2: no line '$1' in: $(cat "$tmp/out")"; }
step() {
  local want=$1 r=0
  shift
  cp "$img" "$tmp/before.img"
  run "$@" || r=$?
  [[ $r == 0 ]] || fail "$*: exit $r: $(cat "$tmp/err")"
  [[ $(state "$img") == "$want" ]] || fail "$*: bytes $(state "$img"), want $want"
  [[ $(outside "$tmp/before.img" "$img") == 0 ]] || fail "$*: bytes changed outside the slot attributes and CRCs"
  valid "$img" || fail "$*: sfdisk sees a bad GPT"
  run status || fail "$*: status after: $(cat "$tmp/err")"
  has "gpt: ok" "$*"
}
sums() { sha256sum "$tmp"/*.img; }
refuse() {
  local name=$1 r=0 before
  shift
  before=$(sums)
  run "$@" || r=$?
  [[ $r == 1 ]] || fail "$name: exit $r"
  [[ $(sums) == "$before" ]] || fail "$name: an image changed"
  [[ $(cat "$tmp/err") == *"${WHY:-}"* ]] || fail "$name: $(cat "$tmp/err")"
}

mk "$img"
valid "$img" || fail "synthetic GPT is bad"
[[ $(state "$img") == "7f 7f 99 99" ]] || fail "initial bytes $(state "$img")"
allowed "$img"
cp "$img" "$tmp/start.img"

writes 0
run status || fail "status: exit $?: $(cat "$tmp/err")"
has "disk $(realpath "$img") block 4096" status
has "gpt: ok" status
has "a boot_a: active 1 priority 3 retry 7 successful 1 unbootable 0 (0x7f)" status
has "b boot_b: active 0 priority 1 retry 3 successful 0 unbootable 1 (0x99)" status

for c in "set b" mark-good; do
  for w in 0 2 missing; do
    if [[ $w == missing ]]; then rm -f "$conf"; else writes "$w"; fi
    r=0
    run $c || r=$?
    [[ $r == 3 ]] || fail "$c with MICROOS_SLOT_WRITE=$w: exit $r"
    same "$img" "$tmp/start.img" || fail "$c with MICROOS_SLOT_WRITE=$w changed the disk"
  done
done

writes 1
for a in "" "set" "set c" "set a b" "mark-good b" "status x" "reset"; do
  r=0
  run $a || r=$?
  [[ $r == 2 ]] || fail "usage '$a': exit $r"
done
same "$img" "$tmp/start.img" || fail "usage errors changed the disk"

step "7f 7f 59 59" mark-good
cp "$tmp/start.img" "$img"
step "78 78 0f 0f" set b
step "78 78 4f 4f" mark-good
step "0f 0f 48 48" set a
cp "$img" "$tmp/before.img"
run set a || fail "set a again: $(cat "$tmp/err")"
same "$img" "$tmp/before.img" || fail "set a again wrote"
has "microos-slot: unchanged" "set a again"
[[ $(outside "$tmp/start.img" "$img") == 0 ]] || fail "bytes changed outside the slot attributes and CRCs since the start"

mk "$tmp/other.img"
mk "$tmp/lun0.img" "size=4MiB, name=microos"
DISKS="boot_a=$tmp/other.img boot_b=$img" WHY="not on one disk" refuse "boot_a on another disk" set b
DISKS="boot_a=$img boot_b=$img microos=$img" WHY="holds microos" refuse "microos on the disk" set b
DISKS="boot_a=$tmp/lun0.img boot_b=$tmp/lun0.img" WHY="disk holds microos" refuse "microos in the GPT" set b
DISKS="boot_a=$img" WHY="no boot_b" refuse "no boot_b" set b
DISKS="boot_a=$tmp/none boot_b=$tmp/none" refuse "missing disk" status
DISKS="boot_a $img" WHY="label=path" refuse "bad hook" status
BS=512 WHY="no header at LBA 1" refuse "512 byte blocks" status

bad=$tmp/bad.img
cp "$img" "$bad"
flip "$bad" $((2 * ss + 56))
[[ $(outside "$img" "$bad") == 1 ]] || fail "the outside check missed a flipped byte"
for c in "primary entries $((2 * ss + 56)) entry array CRC mismatch" \
  "primary header $((ss + 40)) header CRC mismatch" \
  "backup header $(($(last "$img") * ss + 16)) header CRC mismatch" \
  "backup entries $(($(u64 "$img" $(($(last "$img") * ss + 72))) * ss + A * 128 + 54)) entry array CRC mismatch"; do
  read -r copy part off why <<< "$c"
  cp "$img" "$bad"
  flip "$bad" "$off"
  same "$img" "$bad" && fail "corrupt $copy $part did not change the image"
  for a in status "set b" mark-good; do
    DISKS="boot_a=$bad boot_b=$bad" WHY="$copy GPT: $why" refuse "corrupt $copy $part, $a" $a
  done
done
cp "$img" "$bad"
python3 - "$bad" "$ss" << 'EOF'
import struct, sys, zlib
path, ss = sys.argv[1], int(sys.argv[2])
with open(path, "r+b") as f:
    f.seek(0, 2)
    h = (f.tell() // ss - 1) * ss
    f.seek(h)
    hdr = bytearray(f.read(ss))
    elba, n, es = struct.unpack_from("<QII", hdr, 72)
    f.seek(elba * ss)
    e = bytearray(f.read(n * es))
    e[56] ^= 1
    struct.pack_into("<I", hdr, 88, zlib.crc32(e))
    hdr[16:20] = bytes(4)
    struct.pack_into("<I", hdr, 16, zlib.crc32(hdr[:struct.unpack_from("<I", hdr, 12)[0]]))
    f.seek(elba * ss)
    f.write(e)
    f.seek(h)
    f.write(hdr)
EOF
valid "$bad" || fail "renamed backup entry: sfdisk sees a bad GPT"
DISKS="boot_a=$bad boot_b=$bad" WHY="differ outside the slot attributes" refuse "backup differs outside the attributes" set b

cp "$img" "$tmp/torn.img"
for c in "mark-good 08 08 4f 4f" "set a 0f 0f 08 08" "set b 08 08 0f 0f"; do
  cp "$tmp/torn.img" "$img"
  r=0
  MICROOS_SLOT_FAIL=after-backup run set b || r=$?
  [[ $r == 1 && $(cat "$tmp/err") == *"fail point"* ]] || fail "torn set b: exit $r: $(cat "$tmp/err")"
  [[ $(state "$img") == "0f 08 48 0f" ]] || fail "torn set b: bytes $(state "$img")"
  valid "$img" || fail "torn set b: sfdisk sees a bad GPT"
  run status || fail "status of a torn write: exit $?: $(cat "$tmp/err")"
  has "gpt: torn, the backup holds a write the primary lacks; set or mark-good completes it" "torn status"
  has "a boot_a: active 0 priority 0 retry 1 successful 0 unbootable 0 (0x08)" "torn status"
  has "b boot_b: active 1 priority 3 retry 1 successful 0 unbootable 0 (0x0f)" "torn status"
  has "a boot_a primary: active 1 priority 3 retry 1 successful 0 unbootable 0 (0x0f)" "torn status"
  has "b boot_b primary: active 0 priority 0 retry 1 successful 1 unbootable 0 (0x48)" "torn status"
  read -r a1 a2 want <<< "$c"
  [[ $a1 == set ]] || { want="$a2 $want"; a2=""; }
  step "$want" $a1 $a2
  [[ $(outside "$tmp/torn.img" "$img") == 0 ]] || fail "repair by $a1 $a2: bytes changed outside the slot attributes and CRCs"
done

r=0
env MICROOS_SLOT_DISKS="boot_a=$img boot_b=$img" MICROOS_SLOT_BLOCK_SIZE="$ss" MICROOS_SLOT_CONF="$conf" "$slot" status > /dev/null 2> "$tmp/err" || r=$?
err=$(cat "$tmp/err")
[[ $r == 1 && ($err == *"needs root"* || $err == *"no boot_b partition"*) ]] || fail "status without the hook: exit $r: $err"

if (( rc == 0 )); then
  echo "slot: ok"
fi
exit "$rc"
