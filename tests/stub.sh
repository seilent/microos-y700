#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
pack=$here/../build/y700-stub/pack
conf=$here/../system_files/usr/lib/microos/stub.conf
tmp=$(mktemp -d)
trap 'rm -rf "${tmp:?}"' EXIT
rc=0
fail() { echo "FAIL: $*" >&2; rc=1; }

if [[ -z ${CROSS_COMPILE+x} ]]; then
  if [[ $(uname -m) == aarch64 ]]; then
    CROSS_COMPILE=""
  else
    CROSS_COMPILE=aarch64-linux-gnu-
  fi
fi
export CROSS_COMPILE

. "$conf"
le() { od -An -v -t"u$2" -j "$1" -N "$2" "$3" | tr -d ' '; }
syms() { "${CROSS_COMPILE}nm" "$1/stub.elf"; }
sym() {
  local a _ n
  while read -r a _ n; do
    [[ $n != "$2" ]] || echo $(( 16#$a ))
  done < <(syms "$1")
}
arbiter() { "${CROSS_COMPILE}objdump" -d "$1/stub.elf" | grep -cE '#0xc(40|42|44|50), lsl #16' || true; }

payload=$tmp/Image
psize=$((0x2345000))
{
  printf '\x00\x00\x00\x14\x1f\x20\x03\xd5'
  printf '\x00\x00\x00\x00\x00\x00\x00\x00'
  printf "$(printf '\\x%02x' $(( psize & 0xff )) $(( psize >> 8 & 0xff )) $(( psize >> 16 & 0xff )) $(( psize >> 24 & 0xff )))"
  printf '\x00\x00\x00\x00'
  printf '\x0a\x00\x00\x00\x00\x00\x00\x00'
  head -c 24 /dev/zero
  printf 'ARMd'
  head -c 4 /dev/zero
  head -c 1000000 /dev/urandom
} > "$payload"
[[ $(stat -c %s "$payload") == 1000064 && $(le 16 8 "$payload") == "$psize" ]] || fail "synthetic payload"

check() {
  local out=$1 keep=$2 name=$3
  [[ $(stat -c %s "$out") == $(( MICROOS_STUB_PAYLOAD + 1000064 )) ]] || fail "$name size $(stat -c %s "$out")"
  [[ $(dd if="$out" bs=1 skip=56 count=4 status=none) == ARMd ]] || fail "$name magic"
  [[ $(le 16 8 "$out") == $(( psize + MICROOS_STUB_PAYLOAD )) ]] || fail "$name image_size $(le 16 8 "$out")"
  [[ $(le 8 8 "$out") == 0 ]] || fail "$name text_offset $(le 8 8 "$out")"
  [[ $(le 24 8 "$out") == 10 ]] || fail "$name flags $(le 24 8 "$out")"
  cmp -s <(tail -c +$(( MICROOS_STUB_PAYLOAD + 1 )) "$out") "$payload" || fail "$name payload bytes differ"
  [[ -s $keep/stub.elf ]] || fail "$name kept no ELF"
  local start end
  start=$(sym "$keep" wd_start)
  end=$(sym "$keep" wd_end)
  [[ -n $start && -n $end ]] && (( start % 4096 == 0 && end - start <= 4096 )) || fail "$name routine $start to $end"
  [[ $(sym "$keep" _start) == 0 ]] || fail "$name _start is not at 0"
}

"$pack" --keep "$tmp/k1" "$payload" "$tmp/packed" > "$tmp/out" || fail "pack: $(cat "$tmp/out")"
check "$tmp/packed" "$tmp/k1" preset
syms "$tmp/k1" | grep -qw sdam_preset || fail "preset build has no sdam_preset"
(( $(arbiter "$tmp/k1") > 0 )) || fail "preset build has no arbiter address"

"$pack" --preset-free --keep "$tmp/k0" "$payload" "$tmp/free" > "$tmp/out" || fail "pack --preset-free: $(cat "$tmp/out")"
check "$tmp/free" "$tmp/k0" preset-free
! syms "$tmp/k0" | grep -qw sdam_preset || fail "preset free build has sdam_preset"
(( $(arbiter "$tmp/k0") == 0 )) || fail "preset free build loads an arbiter address"
cmp -s <(head -c $(( MICROOS_STUB_PAYLOAD )) "$tmp/packed") <(head -c $(( MICROOS_STUB_PAYLOAD )) "$tmp/free") && fail "preset and preset free stubs are equal"

"$pack" "$payload" "$tmp/again" > /dev/null || fail "second pack"
cmp -s "$tmp/packed" "$tmp/again" || fail "pack is not reproducible"

head -c 64 /dev/zero > "$tmp/bad"
if "$pack" "$tmp/bad" "$tmp/badout" 2> /dev/null; then
  fail "pack took a payload with no arm64 header"
fi
[[ ! -e $tmp/badout ]] || fail "pack wrote output for a bad payload"

if (( rc == 0 )); then
  echo "stub: ok"
fi
exit "$rc"
