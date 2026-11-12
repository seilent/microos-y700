set positional-arguments

builder := "localhost/microos-pkg-builder"

pkg name:
    #!/usr/bin/env bash
    set -euo pipefail
    hash=$(build/pkg-hash.sh "$1")
    mapfile -t inputs < <(build/pkg-hash.sh --inputs "$1")
    dirty=0
    [[ -z $(git status --porcelain -- "${inputs[@]}") ]] || dirty=1
    out=out/pkg/$1
    tag=localhost/microos-pkg/$1:$hash
    mapfile -t deps < <(build/pkg-hash.sh --deps "$1")
    depdir=out/deps/$1
    rm -rf "$depdir"
    mounts=()
    for dep in "${deps[@]}"; do
      dtag=localhost/microos-pkg/$dep:$(build/pkg-hash.sh "$dep")
      mapfile -t dinputs < <(build/pkg-hash.sh --inputs "$dep")
      if [[ -n $(git status --porcelain -- "${dinputs[@]}") \
        || $(podman image inspect -f '{{{{index .Labels "microos.dirty"}}' "$dtag" 2>/dev/null) != 0 ]]; then
        just pkg "$dep"
      fi
      [[ $(podman image inspect -f '{{{{index .Labels "microos.dirty"}}' "$dtag") == 0 ]] || dirty=1
      mkdir -p "$depdir"
      ctr=$(podman create "$dtag" none)
      podman cp "$ctr:/rpms/." "$depdir/"
      podman rm "$ctr" >/dev/null
    done
    (( ${#deps[@]} == 0 )) || mounts=(-v "$PWD/$depdir:/deps:ro,Z")
    podman build --memory=14g --cpu-period=100000 --cpu-quota=800000 -t {{builder}} -f build/pkg.Containerfile build
    img={{builder}}
    if [[ -f packages/$1/Containerfile ]]; then
      img={{builder}}-$1
      podman build --memory=14g --cpu-period=100000 --cpu-quota=800000 -t "$img" -f "packages/$1/Containerfile" "packages/$1"
    fi
    rm -rf "$out"
    mkdir -p "$out"
    cache=()
    if [[ -n ${PKG_CCACHE:-} ]]; then
      mkdir -p "$PKG_CCACHE"
      cache=(-v "$PKG_CCACHE:/ccache:Z" -e CCACHE_DIR=/ccache)
    fi
    if [[ -f packages/$1/fetch.sh ]]; then
      work=out/work/$1
      rm -rf "$work"
      mkdir -p "$work"
      podman run --rm --memory=14g --cpus=8 \
        -v "$PWD/packages/$1:/src:ro,Z" \
        -v "$PWD/$work:/work:Z" \
        "$img" /src/fetch.sh /work
      podman run --rm --memory=14g --cpus=8 --network=none "${cache[@]}" "${mounts[@]}" \
        -v "$PWD/packages/$1:/src:ro,Z" \
        -v "$PWD/$work:/work:ro,Z" \
        -v "$PWD/$out:/out:Z" \
        "$img" /src/build.sh /out /work
      rm -rf "$work"
    else
      podman run --rm --memory=14g --cpus=8 "${cache[@]}" "${mounts[@]}" \
        -v "$PWD/packages/$1:/src:ro,Z" \
        -v "$PWD/$out:/out:Z" \
        "$img" /src/build.sh /out
    fi
    if [[ -f tests/pkg-$1.sh ]]; then
      podman run --rm --memory=14g --cpus=8 --security-opt apparmor=unconfined "${mounts[@]}" \
        -v "$PWD/tests:/tests:ro,Z" \
        -v "$PWD/$out:/out:ro,Z" \
        "$img" "/tests/pkg-$1.sh" /out
    fi
    rm -rf "$depdir"
    [[ ! -e $out/dirty ]] || dirty=1
    podman build --memory=14g --cpu-period=100000 --cpu-quota=800000 -f build/pkg-wrap.Containerfile --label "microos.dirty=$dirty" -t "$tag" "$out"
    echo "$tag"

kernel:
    PKG_CCACHE="${XDG_CACHE_HOME:-$HOME/.cache}/microos-ccache/kernel" just pkg kernel

kernel-dev:
    #!/usr/bin/env bash
    set -euo pipefail
    . packages/kernel/SOURCE.env
    tree=${KERNEL_DEV_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/microos-kernel-dev}/$KERNEL_TAG
    ccache=${XDG_CACHE_HOME:-$HOME/.cache}/microos-ccache/kernel
    out=out/pkg/kernel-dev
    tag=localhost/microos-pkg/kernel-dev:$(build/pkg-hash.sh kernel)
    mkdir -p "$tree" "$ccache"
    podman build --memory=14g --cpu-period=100000 --cpu-quota=800000 -t {{builder}} -f build/pkg.Containerfile build
    rm -rf "$out"
    mkdir -p "$out"
    podman run --rm --memory=14g --cpus=8 -v "$ccache:/ccache:Z" -e CCACHE_DIR=/ccache \
      -v "$tree:/kdev:Z" -e MICROOS_KERNEL_DEV=/kdev \
      -v "$PWD/packages/kernel:/src:ro,Z" -v "$PWD/$out:/out:Z" \
      {{builder}} /src/build.sh /out
    podman run --rm --memory=14g --cpus=8 --security-opt apparmor=unconfined \
      -v "$PWD/tests:/tests:ro,Z" -v "$PWD/$out:/out:ro,Z" \
      {{builder}} /tests/pkg-kernel.sh /out
    podman build --memory=14g --cpu-period=100000 --cpu-quota=800000 -f build/pkg-wrap.Containerfile \
      --label microos.dirty=1 -t "$tag" "$out"
    echo "$tag"
    echo "dtbs: $tree/obj/arch/arm64/boot/dts/qcom"

pkg-push name:
    #!/usr/bin/env bash
    set -euo pipefail
    mapfile -t inputs < <(build/pkg-hash.sh --inputs "$1")
    if [[ -n $(git status --porcelain -- "${inputs[@]}") ]]; then
      echo "uncommitted changes in the inputs of $1" >&2
      exit 1
    fi
    hash=$(build/pkg-hash.sh "$1")
    local=localhost/microos-pkg/$1:$hash
    if [[ $(podman inspect -f '{{{{index .Labels "microos.dirty"}}' "$local") != 0 ]]; then
      echo "$local was built from uncommitted inputs" >&2
      exit 1
    fi
    for dep in $(build/pkg-hash.sh --deps "$1"); do
      dtag=localhost/microos-pkg/$dep:$(build/pkg-hash.sh "$dep")
      if ! podman image exists "$dtag"; then
        echo "dep $dep has no local image $dtag, run just pkg $dep" >&2
        exit 1
      fi
      if [[ $(podman inspect -f '{{{{index .Labels "microos.dirty"}}' "$dtag") != 0 ]]; then
        echo "$dtag, a dep of $1, was built from uncommitted inputs" >&2
        exit 1
      fi
    done
    repo=ghcr.io/seilent/microos-y700/pkg/$1
    api=/user/packages/container/microos-y700%2Fpkg%2F$1
    keys=${MICROOS_KEYS:-$HOME/.config/microos/keys}
    cosign=${COSIGN:-cosign}
    podman login --get-login ghcr.io >/dev/null
    if ! gh api "$api" >/dev/null 2>&1; then
      start=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      gh workflow run package-init.yml -R seilent/microos-y700 -f name="$1"
      run=
      for _ in $(seq 60); do
        sleep 5
        run=$(gh run list -R seilent/microos-y700 --workflow package-init.yml --event workflow_dispatch \
          --user seilent --json databaseId,createdAt \
          --jq "[.[] | select(.createdAt >= \"$start\")][0].databaseId // empty")
        [[ -z $run ]] || break
      done
      [[ -n $run ]] || { echo "package-init run not found" >&2; exit 1; }
      gh run watch "$run" -R seilent/microos-y700 --exit-status >/dev/null
    fi
    pub=system_files/usr/share/microos/keys/microos.pub
    if err=$(skopeo inspect --raw "docker://$repo:$hash" 2>&1 >/dev/null); then
      cfg=$(skopeo inspect --config --raw "docker://$repo:$hash" | sha256sum | cut -d' ' -f1)
      if [[ $cfg != "$(podman image inspect -f '{{{{.Id}}' "$local")" ]]; then
        echo "$repo:$hash exists with another image than $local" >&2
        exit 1
      fi
      digest=sha256:$(skopeo inspect --raw "docker://$repo:$hash" | sha256sum | cut -d' ' -f1)
      if err=$("$cosign" verify --key "$pub" "$repo@$digest" 2>&1 >/dev/null); then
        echo "$repo:$hash exists and is signed"
        exit 0
      fi
      if ! grep -qiE 'no signatures found|no matching signatures' <<< "$err"; then
        echo "$err" >&2
        exit 1
      fi
      echo "$repo:$hash exists unsigned, signing $digest" >&2
    elif grep -qiE 'manifest unknown|404' <<< "$err"; then
      podman tag "$local" "$repo:$hash"
      f=$(mktemp)
      trap 'rm -f "$f"' EXIT
      podman push --digestfile "$f" "$repo:$hash"
      digest=$(cat "$f")
    else
      echo "$err" >&2
      exit 1
    fi
    COSIGN_PASSWORD=$(cat "$keys/microos.password") \
      "$cosign" sign -y --new-bundle-format=false --use-signing-config=false --key "$keys/microos.key" "$repo@$digest"
    "$cosign" verify --key "$pub" "$repo@$digest" >/dev/null
    init=$(gh api "$api/versions" --jq '.[] | select(.metadata.container.tags | index("init")) | .id')
    if [[ -n $init ]]; then
      gh api -X DELETE "$api/versions/$init"
    fi
    echo "$repo:$hash"

test:
    tests/pkg-hash.sh

test-services:
    #!/usr/bin/env bash
    set -euo pipefail
    case $(uname -m) in
      x86_64) arch=amd64 ;;
      aarch64) arch=arm64 ;;
      *) echo "no fedora:44 for $(uname -m)" >&2; exit 1 ;;
    esac
    fedora=registry.fedoraproject.org/fedora:44@sha256:1ff9eb02e4e2d7fb1175becac7139b2960c4fdcccedce81c86ec25b98ef3124d
    dnf="dnf -yq --setopt=install_weak_deps=False install"
    run() { podman run --rm --memory=14g --cpus=8 --arch "$arch" -v "$PWD:/repo:ro,Z" "$@"; }
    run "$fedora" sh -c "$dnf git-core && /repo/tests/pkg-hash.sh"
