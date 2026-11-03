#!/usr/bin/env bash
#
# mayhem/test.sh — RUN upstream's Catch2 suite (built by mayhem/build.sh) plus known-answer probes.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}


fail=0

# 1) Upstream Catch2 suite: run every ctest-registered binary directly and sum its summary line.
#    A neutered binary prints no summary, so it contributes no passes and trips the minimum below.
TESTDIR="$SRC/build-tests/tests"
[ -d "$TESTDIR" ] || { echo "missing $TESTDIR — build.sh must build the suite" >&2; emit_ctrf "catch2" 0 1 0; exit 1; }
passed=0; failed=0; skipped=0
names=$(cd "$SRC/build-tests" && ctest -N | sed -n 's/^ *Test *#[0-9]*: //p')
[ -n "$names" ] || { echo "ctest lists no tests" >&2; emit_ctrf "catch2" 0 1 0; exit 1; }
for n in $names; do
  out=$(cd "$TESTDIR" && timeout 600 "./$n" 2>&1) || true
  if line=$(printf '%s\n' "$out" | grep -E '^test cases:'); then
    tot=$(printf '%s' "$line" | sed -E 's/^test cases: *([0-9]+).*/\1/')
    p=$(printf '%s' "$line" | sed -nE 's/.*\| *([0-9]+) passed.*/\1/p'); p=${p:-0}
    f=$(printf '%s' "$line" | sed -nE 's/.*\| *([0-9]+) failed.*/\1/p'); f=${f:-0}
    s=$(printf '%s' "$line" | sed -nE 's/.*\| *([0-9]+) skipped.*/\1/p'); s=${s:-0}
    passed=$((passed+p)); failed=$((failed+f)); skipped=$((skipped+s))
    echo "FAIL $n: $line"
  elif line=$(printf '%s\n' "$out" | grep -E '^All tests passed'); then
    p=$(printf '%s' "$line" | sed -E 's/.* in ([0-9]+) test case.*/\1/')
    passed=$((passed+p))
  else
    echo "FAIL $n: no Catch2 summary" >&2
    failed=$((failed+1))
  fi
done
echo "catch2 totals: passed=$passed failed=$failed skipped=$skipped"
if [ "$passed" -lt 100 ]; then echo "too few Catch2 test cases passed ($passed < 100)" >&2; failed=$((failed+1)); fi

# 2) Known-answer probes through the public CLI11 API (exact expected output).
kat=$(/mayhem/cli11_kat 2>&1) || kat="PROBE EXITED NONZERO: $kat"
expect=$'count=42 ratio=2.5 name=alpha verbose=1 nums=3:24\nsub=1 target=build\nrange_rejected=1\nconfig level=13 tag=hello\nconfig_out=level=13\ntag="hello"\n'
if [ "$kat" == "${expect%$'\n'}" ]; then
  passed=$((passed+1))
else
  echo "KAT mismatch. got:" >&2; printf '%s\n' "$kat" >&2
  failed=$((failed+1))
fi

emit_ctrf "catch2+kat" "$passed" "$failed" "$skipped"
