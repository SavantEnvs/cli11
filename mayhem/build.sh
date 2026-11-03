#!/usr/bin/env bash
#
# mayhem/build.sh — CLI11 is header-only, so the "project" is compiled into each harness translation
# unit with the sanitizer/DWARF flags. Also builds upstream's Catch2 suite and a KAT probe with the
# project's NORMAL flags for mayhem/test.sh.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

OBJ="$(mktemp -d)"
trap 'rm -rf "$OBJ"' EXIT

# Instrument the fuzzed library code (headers, compiled into these TUs) with SanCov unconditionally.
FUZZ_CXXFLAGS="-std=c++17 -O1 $SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link -I$SRC/include"

$CXX $FUZZ_CXXFLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$OBJ/lsan_off.o"
$CXX $FUZZ_CXXFLAGS -c "$SRC/fuzz/fuzzApp.cpp" -o "$OBJ/fuzzApp.o"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$OBJ/standalone_main.o"

for t in app file; do
  name="cli11_${t}_fuzzer"
  $CXX $FUZZ_CXXFLAGS -c "$SRC/fuzz/cli11_${t}_fuzz.cpp" -o "$OBJ/$name.o"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE \
      "$OBJ/$name.o" "$OBJ/fuzzApp.o" "$OBJ/lsan_off.o" -o "/mayhem/$name"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS \
      "$OBJ/$name.o" "$OBJ/fuzzApp.o" "$OBJ/lsan_off.o" "$OBJ/standalone_main.o" -o "/mayhem/$name-standalone"
done

# Oracle build: upstream's Catch2 suite (apt libcatch2-dev) with the project's normal flags,
# in a build dir covered by upstream's `/*build*` gitignore.
cmake -S "$SRC" -B "$SRC/build-tests" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
    -DCMAKE_CXX_STANDARD=17 -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS" \
    -DCLI11_BUILD_EXAMPLES=OFF -DCLI11_BUILD_DOCS=OFF -DCLI11_BUILD_TESTS=ON \
    -DCLI11_SANITIZERS=OFF -DCMAKE_DISABLE_FIND_PACKAGE_Boost=ON
cmake --build "$SRC/build-tests" -j"$MAYHEM_JOBS"

# KAT probe, normal flags, dynamically linked.
$CXX -std=c++17 -O1 $COVERAGE_FLAGS -I"$SRC/include" "$SRC/mayhem/kat/cli11_kat.cpp" -o /mayhem/cli11_kat
