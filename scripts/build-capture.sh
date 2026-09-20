#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd "$(dirname "$0")/.." && pwd)
output="${1:-$project_dir/build/capture/sotto-capture}"
mkdir -p "$(dirname "$output")"
read -r -a flags <<< "$(pkg-config --cflags --libs libpipewire-0.3 libusb-1.0 samplerate)"
cc -std=gnu11 -O2 -Wall -Wextra -Werror "$project_dir/Server/capture/main.c" \
    -o "$output" "${flags[@]}" -lm
