#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd "$(dirname "$0")/.." && pwd)
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
if ! dependency_flags=$(pkg-config --cflags --libs samplerate); then
    printf 'Install pkg-config and the libsamplerate development package. See docs/pipewire-capture.md.\n' >&2
    exit 1
fi
read -r -a flags <<< "$dependency_flags"
cc -std=gnu11 -O2 -Wall -Wextra -Werror "$project_dir/Server/capture/audio-test.c" \
    -o "$temporary/audio-test" "${flags[@]}" -lm
"$temporary/audio-test"
bash "$project_dir/scripts/build-capture.sh" "$temporary/sotto-capture"
SOTTO_TEST_CAPTURE_HELPER="$temporary/sotto-capture" bun test "$project_dir/Server/tests/pipewire-native.test.ts"
