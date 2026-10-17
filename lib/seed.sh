#!/usr/bin/env bash
# seed.sh — invented data for all three apps.
#
#   bash lib/seed.sh all | stages | leaves | nurse
#
# Every name in here is obviously a placeholder, every address is at
# lab.invalid, which is reserved and can never resolve. Volumes come from
# lab.conf; SETUP.md section 9 explains why the numbers are what they are.
#
# Re-running tops the tables up to the target rather than duplicating, so this
# is safe to run twice.
set -euo pipefail

SEED_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd -- "$SEED_LIB_DIR/.." && pwd)"
# shellcheck source=lib/guard.sh
. "$SEED_LIB_DIR/guard.sh"
# shellcheck source=lib/svc.sh
. "$SEED_LIB_DIR/svc.sh"
# shellcheck source=/dev/null
[[ ! -f "$LAB_ROOT/lab.conf" ]] || . "$LAB_ROOT/lab.conf"

SEED_TRAINEES="${SEED_TRAINEES:-400}"
SEED_PLACEMENTS="${SEED_PLACEMENTS:-60000}"
SEED_AUDIT="${SEED_AUDIT:-5000}"
SEED_THESES="${SEED_THESES:-3000}"
SEED_LEAVE_REQUESTS="${SEED_LEAVE_REQUESTS:-60}"

# --- stages: the lab owns this schema, so it is seeded precisely ------------

# psql as the OWNER role. The app's own role deliberately cannot do this.
stages_psql() {
  local dir="${STAGES_DIR:?set STAGES_DIR in lab.conf}"
  local user="${POSTGRES_USER:-stages_owner}" db="${POSTGRES_DB:-stages}"
  if [[ "$(svc_mode stages)" == "compose" ]]; then
    ( cd "$dir" && lab_as_root docker compose exec -T db \
        psql -v ON_ERROR_STOP=1 -U "$user" -d "$db" "$@" )
  else
    psql -v ON_ERROR_STOP=1 -U "$user" -d "$db" -h 127.0.0.1 "$@"
  fi
}

seed_stages() {
  lab_guard
  printf 'stages: %s trainees, %s placements, %s audit rows\n' \
    "$SEED_TRAINEES" "$SEED_PLACEMENTS" "$SEED_AUDIT"
  stages_psql -v trainees="$SEED_TRAINEES" -v placements="$SEED_PLACEMENTS" \
              -v audit="$SEED_AUDIT" <<'SQL'
-- Obviously invented: a short list of given names against surnames that could
-- not belong to anyone, and addresses at a reserved domain.
INSERT INTO trainees (ref, full_name, cohort, email)
SELECT 'LAB-' || lpad(g::text, 5, '0'),
       (ARRAY['Amal','Bilal','Chadi','Dalia','Emna','Farid',
              'Ghada','Hatem','Ines','Jalel','Karim','Lina'])[1 + (g * 7) % 12]
         || ' ' ||
       (ARRAY['Specimen','Placeholder','Example','Testcase','Sample',
              'Notreal','Dummy','Standin','Mockley','Fictif'])[1 + (g * 3) % 10],
       'C' || (2024 + (g % 3))::text,
       'trainee' || g || '@lab.invalid'
FROM generate_series(1, :trainees) g
ON CONFLICT (ref) DO NOTHING;

-- Top up to the target rather than inserting blindly, so a second run is a
-- no-op instead of doubling the table.
INSERT INTO placements (trainee_id, ward, started_on, ended_on, status)
SELECT (SELECT id FROM trainees ORDER BY id LIMIT 1 OFFSET (g % (SELECT count(*) FROM trainees))),
       (ARRAY['Ward Alpha','Ward Bravo','Ward Charlie','Ward Delta','Ward Echo',
              'Ward Foxtrot','Ward Golf','Ward Hotel','Ward India','Ward Juliett',
              'Ward Kilo','Ward Lima'])[1 + (g * 5) % 12],
       -- generate_series yields bigint, and date - bigint has no operator.
       CURRENT_DATE - ((g * 13) % 540)::int,
       CURRENT_DATE - ((g * 13) % 540)::int + 28,
       (ARRAY['planned','active','completed'])[1 + (g % 3)]
FROM generate_series(1, GREATEST(0, :placements - (SELECT count(*) FROM placements))) g;

INSERT INTO audit_log (actor, action, detail)
SELECT (ARRAY['ops@lab.invalid','coordinator@lab.invalid','registry@lab.invalid'])[1 + (g % 3)],
       (ARRAY['login','upload','export','approve','reject'])[1 + (g % 5)],
       'seeded row ' || g
FROM generate_series(1, GREATEST(0, :audit - (SELECT count(*) FROM audit_log))) g;

ANALYZE trainees;
ANALYZE placements;
ANALYZE audit_log;

SELECT 'trainees' AS table, count(*) FROM trainees
UNION ALL SELECT 'placements', count(*) FROM placements
UNION ALL SELECT 'audit_log', count(*) FROM audit_log;
SQL
}

# --- leaves and nurse: schemas this repo does not own -----------------------
#
# These two are public repositories cloned at setup time, so their model and
# field names are not knowable from here. The seeder asks Django, fills fields
# by type, and refuses loudly — listing what it did find — rather than guessing
# wrong. Pin the model in lab.conf once, after section 6 or 7 of SETUP.md.

app_manage() {
  local app="$1"; shift
  local dirvar; dirvar="$(printf '%s_DIR' "${app^^}")"
  local dir="${!dirvar:?set ${dirvar} in lab.conf}"
  if [[ "$(svc_mode "$app")" == "compose" ]]; then
    ( cd "$dir" && lab_as_root docker compose exec -T "$(svc_name "$app" api)" \
        python manage.py "$@" )
  else
    ( cd "$dir" && lab_as_root ./.venv/bin/python manage.py "$@" )
  fi
}

# django_seed <app> <model hint> <count>
django_seed() {
  local app="$1" hint="$2" count="$3"
  SEED_MODEL_HINT="$hint" SEED_COUNT="$count" \
    app_manage "$app" shell <<'PY'
import datetime, os, random
from django.apps import apps

hint = os.environ["SEED_MODEL_HINT"].lower()
count = int(os.environ["SEED_COUNT"])
random.seed(20261017)  # deterministic: the same lab twice is the same lab

# An exact name wins over a substring, so a hint of "Thesis" cannot land on
# ThesisStatusHistory depending on the order Django happens to return models in.
exact = [m for m in apps.get_models() if m.__name__.lower() == hint]
matches = exact or sorted(
    (m for m in apps.get_models() if hint in m.__name__.lower()),
    key=lambda m: len(m.__name__),
)
if not matches:
    print("SEED-FAIL: no model matching %r. Models this project has:" % hint)
    for m in sorted(apps.get_models(), key=lambda x: x._meta.label):
        print("   ", m._meta.label)
    print("Set the right hint in lab.conf and run again.")
    raise SystemExit(1)

model = matches[0]
print("seeding %s (%d rows wanted)" % (model._meta.label, count))

GIVEN = ["Amal", "Bilal", "Chadi", "Dalia", "Emna", "Farid",
         "Ghada", "Hatem", "Ines", "Jalel", "Karim", "Lina"]
SURNAME = ["Specimen", "Placeholder", "Example", "Testcase", "Sample",
           "Notreal", "Dummy", "Standin", "Mockley", "Fictif"]
TOPIC = ["handover practice", "ward rota design", "placement feedback",
         "infection-control drills", "night-shift handovers", "triage timing"]


def value_for(field, n):
    """A plausible, obviously-invented value, chosen by field type."""
    kind = field.get_internal_type()
    if getattr(field, "choices", None):
        return field.choices[n % len(field.choices)][0]
    if kind in ("CharField", "TextField", "SlugField"):
        if field.unique:
            # Unique first, readable second: the counter leads so truncation to
            # max_length can never collide two rows.
            return ("LAB-%06d %s" % (n, TOPIC[n % len(TOPIC)]))[: (field.max_length or 200)]
        wide = field.max_length is None or field.max_length > 40
        base = "%s %d" % (TOPIC[n % len(TOPIC)], n) if wide else "LAB-%05d" % n
        return base[: (field.max_length or 200)]
    if kind == "EmailField":
        return "%s.%s%d@lab.invalid" % (GIVEN[n % 12].lower(), SURNAME[n % 10].lower(), n)
    if kind in ("IntegerField", "BigIntegerField", "SmallIntegerField",
                "PositiveIntegerField", "PositiveSmallIntegerField"):
        # A unique integer column cannot be one of seven values. nurse's
        # Thesis.numero is exactly this case.
        return 900000 + n if field.unique else 1 + (n % 7)
    if kind in ("DecimalField", "FloatField"):
        return 1 + (n % 7)
    if kind == "BooleanField":
        return bool(n % 2)
    if kind == "DateField":
        return datetime.date.today() - datetime.timedelta(days=(n * 3) % 365)
    if kind == "DateTimeField":
        return datetime.datetime.now() - datetime.timedelta(hours=(n * 7) % 2000)
    if kind in ("ForeignKey", "OneToOneField"):
        related = field.related_model.objects.all()[:50]
        return related[n % len(related)] if related else None
    return None


existing = model.objects.count()
made = 0
for n in range(existing, count):
    data, skip = {}, False
    for f in model._meta.fields:
        if f.auto_created or f.primary_key or f.has_default() or f.blank and f.null:
            continue
        v = value_for(f, n)
        if v is None:
            if f.null:
                continue
            skip = True
            print("SEED-FAIL: cannot invent a value for %s.%s (%s)"
                  % (model.__name__, f.name, f.get_internal_type()))
            break
        data[f.attname if f.get_internal_type() not in ("ForeignKey", "OneToOneField")
             else f.name] = v
    if skip:
        raise SystemExit(1)
    model.objects.create(**data)
    made += 1

print("seeded %d new rows; %s now holds %d" % (made, model.__name__, model.objects.count()))
PY
}

seed_leaves() {
  lab_guard
  printf 'leaves: %s leave requests\n' "$SEED_LEAVE_REQUESTS"
  django_seed leaves "${LEAVES_SEED_MODEL:-LeaveRequest}" "$SEED_LEAVE_REQUESTS"
}

seed_nurse() {
  lab_guard
  printf 'nurse: %s theses\n' "$SEED_THESES"
  django_seed nurse "${NURSE_SEED_MODEL:-Thesis}" "$SEED_THESES"
}

main() {
  lab_guard
  case "${1:-all}" in
    stages) seed_stages ;;
    leaves) seed_leaves ;;
    nurse)  seed_nurse ;;
    all)    seed_stages; seed_leaves; seed_nurse ;;
    *) printf 'usage: %s [all|stages|leaves|nurse]\n' "$0" >&2; exit 2 ;;
  esac
}

# Runnable as a script, sourceable as a library.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
