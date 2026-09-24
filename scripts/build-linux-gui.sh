#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="$ROOT/Clients/Linux/gui"
build_dir="$ROOT/build/linux-gui"
configure_args=()
# Refresh a relocated source tree once, preserving subsequent incremental builds.
if [[ -f "$build_dir/CMakeCache.txt" ]] && \
   ! grep -Fxq "CMAKE_HOME_DIRECTORY:INTERNAL=$source_dir" "$build_dir/CMakeCache.txt"; then
  configure_args+=(--fresh)
fi
cmake "${configure_args[@]}" -S "$source_dir" -B "$build_dir" -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON
cmake --build "$build_dir" --parallel 2
