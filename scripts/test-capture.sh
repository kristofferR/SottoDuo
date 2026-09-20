#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd "$(dirname "$0")/.." && pwd)
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
read -r -a flags <<< "$(pkg-config --cflags --libs samplerate)"
cc -std=gnu11 -O2 -Wall -Wextra -Werror "$project_dir/Server/capture/audio-test.c" \
    -o "$temporary/audio-test" "${flags[@]}" -lm
"$temporary/audio-test"
bash "$project_dir/scripts/build-capture.sh" "$temporary/sotto-capture"
SOTTO_TEST_CAPTURE_HELPER="$temporary/sotto-capture" bun test "$project_dir/Server/tests/pipewire-native.test.ts"
