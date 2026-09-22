#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cmake -S "$ROOT/LinuxClient/gui" -B "$ROOT/build/linux-gui" -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON
cmake --build "$ROOT/build/linux-gui" --parallel 2
