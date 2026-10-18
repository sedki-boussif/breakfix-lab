#!/usr/bin/env bash
# s2-01 — a mission: nothing is broken. This generates the access log the
# questions are about, and writes the answer sheet you fill in.
#
# The log is generated locally and never fetched: no run-time network calls,
# and every address in it comes from the RFC 5737 documentation ranges, which
# can never belong to anybody.
#
# Idempotent by refusing to regenerate: a second run leaves an existing log
# alone, because replacing it under someone who has already answered three
# questions would be worse than useless. The generator is seeded, so a log
# removed and regenerated is byte-identical anyway.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s2-01-read-the-access-log'
dir="${S2_01_DIR:-/var/tmp/lab-s2-01}"
log="$dir/access.log"
answers="$dir/answers.txt"
lines="${S2_01_LINES:-50000}"

mkdir -p "$dir"

if [[ -s "$log" ]]; then
  printf 'The log already exists: %s (%s lines)\n' "$log" "$(wc -l <"$log")"
  printf 'Leaving it alone — regenerating it under half-finished answers would\n'
  printf 'be worse than useless. To start over: rm -rf %s\n\n' "$dir"
else
  printf 'Generating %s lines of nginx access log...\n' "$lines"
  python3 - "$log" "$lines" <<'PY'
import sys

path, n = sys.argv[1], int(sys.argv[2])

# A linear congruential generator, written out rather than imported, so the log
# is byte-identical on every machine and every Python version. Determinism is
# not needed to grade the answers — check.sh computes them from whatever log is
# there — but a reproducible exercise is worth three lines.
_s = 20261018
def rnd(limit):
    global _s
    _s = (_s * 1103515245 + 12345) % 2147483648
    return _s % limit

def shuffle(seq):
    for i in range(len(seq) - 1, 0, -1):
        j = rnd(i + 1)
        seq[i], seq[j] = seq[j], seq[i]

# --- the cast ---------------------------------------------------------------
# Only RFC 5737 documentation addresses. 192.0.2.0/24 is the busy crawler and
# user traffic, 198.51.100.0/24 the office, 203.0.113.0/24 everything else.
#
# The twelve heavy addresses get explicit, well-separated counts so that "the
# top ten" has one correct ordering and grading it is not a coin toss. The
# counts shift a little when the 404s are placed below, which is why check.sh
# verifies the tenth and eleventh are not tied rather than trusting this.
# The background fills the remainder from subranges none of the named addresses
# use, so it cannot quietly inflate one of them.
heavy = [
    ("192.0.2.17",   3000), ("198.51.100.9",  2800), ("192.0.2.88",   2600),
    ("203.0.113.42", 2400), ("192.0.2.5",     2200), ("198.51.100.74", 2000),
    ("203.0.113.7",  1800), ("192.0.2.201",   1600), ("198.51.100.31", 1400),
    ("203.0.113.150", 1200), ("192.0.2.64",   1000), ("198.51.100.5",   800),
]
# The address responsible for most 404s is deliberately NOT the busiest one:
# the interesting answer and the obvious answer are different questions.
noisy_404 = "203.0.113.99"

urls_heavy = [
    ("/api/theses/",            9000), ("/",                    7000),
    ("/api/theses/search/",     5200), ("/static/js/app.js",    4400),
    ("/static/css/main.css",    3800), ("/api/health/",         3200),
    ("/api/theses/export/",     2600), ("/login/",              2000),
    ("/api/supervisors/",       1500), ("/static/img/logo.png",  1100),
    ("/favicon.ico",             800), ("/robots.txt",           500),
]
# Paths that only ever 404: the shape of a scanner, and where the noisy
# address spends its time.
urls_missing = ["/wp-login.php", "/admin.php", "/.env", "/phpmyadmin/",
                "/api/v2/theses/", "/static/css/old.css"]

status_plan = [(200, 41000), (404, 3600), (301, 1900), (304, 1500),
               (500, 900), (403, 500), (502, 400), (503, 200)]

agents = ["Mozilla/5.0 (X11; Linux x86_64)", "curl/8.5.0",
          "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
          "lab-monitor/1.0", "Mozilla/5.0 (compatible; LabBot/2.1)"]

# --- build the columns independently, then shuffle each ---------------------
# Each column is a bag with the planned counts in it; shuffling decorrelates
# them so the log does not read as sorted by anything.
def bag(plan, total, filler):
    out = []
    for value, count in plan:
        out.extend([value] * count)
    short = total - len(out)
    for i in range(short):
        out.append(filler(i))
    del out[total:]
    return out

def background_ip(i):
    # 198.51.100.128-254 and 203.0.113.180-254: 202 addresses, none of them
    # named above, so the planned counts stay the planned counts.
    i %= 202
    return "198.51.100.%d" % (128 + i) if i < 127 else "203.0.113.%d" % (180 + i - 127)

ips = bag(heavy, n, lambda i: background_ip(i * 7))
shuffle(ips)
urls = bag(urls_heavy, n, lambda i: "/api/theses/%d/" % (1 + i % 900))
shuffle(urls)
statuses = bag(status_plan, n, lambda i: 200)
shuffle(statuses)

# --- place the 404s so the questions have the answers they should ----------
# The noisy address owns a clear plurality of the 404s, and its requests are
# for paths that do not exist. Done by rewriting chosen rows rather than by
# sampling, so the answer is exact rather than probable.
four_oh_four = [i for i, s in enumerate(statuses) if s == 404]
for k, i in enumerate(four_oh_four):
    if k < 1500:
        ips[i] = noisy_404
        urls[i] = urls_missing[k % len(urls_missing)]
    elif k < 1900:
        # Second place, well behind: a plurality is not a near-tie.
        ips[i] = "192.0.2.17"
        urls[i] = urls_missing[k % len(urls_missing)]

# --- the 5xx are not spread evenly, because incidents are not --------------
# Three quarters of them land in a two-hour window. "5xx per hour" is a
# question about when, and a flat answer would teach the wrong lesson.
fives = [i for i, s in enumerate(statuses) if s >= 500]
hours = []
for k in range(n):
    hours.append(rnd(24))
for k, i in enumerate(fives):
    hours[i] = 14 if k % 2 == 0 else 15
    if k % 9 == 0:                     # a thin background of 5xx elsewhere
        hours[i] = rnd(24)

rows = []
for i in range(n):
    ip, url, st, hh = ips[i], urls[i], statuses[i], hours[i]
    if st == 404 or st == 304:
        size = 0 if st == 304 else 564
    elif st >= 500:
        size = 1270
    elif st == 301:
        size = 178
    elif st == 403:
        size = 199
    elif url.startswith("/static/") or url == "/favicon.ico":
        size = 2048 + rnd(8192)
    else:
        size = 420 + rnd(9000)
    mm, ss = rnd(60), rnd(60)
    rows.append((hh, mm, ss,
                 '%s - - [18/Oct/2026:%02d:%02d:%02d +0000] "GET %s HTTP/1.1" '
                 '%d %d "-" "%s"' % (ip, hh, mm, ss, url, st, size,
                                     agents[rnd(len(agents))])))

# A log is chronological. Sorting by the timestamp is the last step, so the
# file looks like something nginx wrote rather than something a script did.
rows.sort(key=lambda r: (r[0], r[1], r[2]))
with open(path, "w") as fh:
    for r in rows:
        fh.write(r[3] + "\n")
PY
  printf 'Written: %s (%s lines, %s)\n\n' \
    "$log" "$(wc -l <"$log")" "$(du -h "$log" | cut -f1)"
fi

if [[ -s "$answers" ]]; then
  printf 'Your answer sheet is already there: %s\n' "$answers"
else
  cat >"$answers" <<'TXT'
# s2-01 answers. Fill in the value after each "=" and leave the keys alone.
# Lines beginning with # are ignored. Formats are in the brief; getting the
# format wrong is graded as a wrong answer, which is also true of a report.

# 1. The ten addresses with the most requests, most first, comma separated.
top_ips=

# 2. The ten paths with the most requests, most first, comma separated.
top_urls=

# 3. Every status code in the log with its count, ascending by code,
#    as code:count pairs, comma separated.  e.g. 200:41000,404:3600
status_counts=

# 4. The 5xx responses per hour, for every hour that has at least one,
#    ascending by hour, as HH:count pairs.  e.g. 09:3,14:338
fivexx_by_hour=

# 5. The single address responsible for the most 404s.
top_404_ip=

# 6. Total bytes served: the sum of the response size column.
bytes_total=
TXT
  printf 'Answer sheet: %s\n' "$answers"
fi

printf '\nSix questions, in %s. Answer them in %s, then:\n' "$answers" "$answers"
printf '  lab check %s\n' "$ID"
lab_state_set "$ID" BROKEN_AT 0
