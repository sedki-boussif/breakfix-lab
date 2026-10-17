#!/usr/bin/env bash
# load.sh — a small load generator, because "it felt slow" is not a measurement.
#
# Parallel curl only: no hey, no ab, nothing to install. The stage 9 load
# challenges need a number they can compare before and after, and they need it
# on a VM with no internet, so this uses what is already there.
#
#   lab_load_run <url> <concurrency> <seconds>
#     prints one line: requests=N rps=N.N p50=N.NNN p95=N.NNN errors=N error_rate=N.NN
#
#   lab_load_p95 <url> <concurrency> <seconds>
#     prints just the p95 in seconds, for assert_below
set -euo pipefail
shopt -s inherit_errexit

# One worker: request in a loop until the deadline, one line per request.
_lab_load_worker() {
  local url="$1" deadline="$2" out="$3"
  while (( $(date +%s) < deadline )); do
    curl -s -o /dev/null --max-time 10 \
      -w '%{http_code} %{time_total}\n' "$url" >>"$out" 2>/dev/null || \
      printf '000 10.000\n' >>"$out"
  done
}

lab_load_run() {
  local url="${1:?url}" conc="${2:-10}" secs="${3:-20}"
  local dir deadline i pids=()
  dir="$(mktemp -d)"
  deadline=$(( $(date +%s) + secs ))

  for (( i = 0; i < conc; i++ )); do
    _lab_load_worker "$url" "$deadline" "$dir/w$i" &
    pids+=("$!")
  done
  for i in "${pids[@]}"; do wait "$i" 2>/dev/null || true; done

  cat "$dir"/w* 2>/dev/null | awk -v secs="$secs" '
    {
      n++
      code[n] = $1
      t[n] = $2 + 0
      if ($1 < 200 || $1 >= 400) errors++
    }
    END {
      if (n == 0) { print "requests=0 rps=0 p50=0 p95=0 errors=0 error_rate=0"; exit }
      # sort the times
      for (i = 1; i <= n; i++) s[i] = t[i]
      for (i = 2; i <= n; i++) {
        v = s[i]; j = i - 1
        while (j > 0 && s[j] > v) { s[j+1] = s[j]; j-- }
        s[j+1] = v
      }
      p50i = int(n * 0.50); if (p50i < 1) p50i = 1
      p95i = int(n * 0.95); if (p95i < 1) p95i = 1
      printf "requests=%d rps=%.1f p50=%.3f p95=%.3f errors=%d error_rate=%.2f\n",
             n, n / secs, s[p50i], s[p95i], errors + 0, (errors + 0) / n
    }'
  rm -rf "$dir"
}

lab_load_p95() {
  lab_load_run "$@" | sed -n 's/.*p95=\([0-9.]*\).*/\1/p'
}

lab_load_error_rate() {
  lab_load_run "$@" | sed -n 's/.*error_rate=\([0-9.]*\).*/\1/p'
}
