#!/usr/bin/env sh
set -eu

repository_root=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
cd "$repository_root"

die() {
  echo "Backup policy verification failed: $*" >&2
  exit 1
}

[ "${1:-}" = "--fixture" ] && [ "${2:-}" = "local" ] && [ "$#" -eq 2 ] ||
  die "usage: $0 --fixture local"

config=infra/backup/pgbackrest.conf.template
schedule=infra/backup/schedule.yml
manifest=infra/backup/durable-state-manifest.yml

for file in "$config" "$schedule" "$manifest" infra/compose/compose.yml infra/images/server/Dockerfile; do
  [ -f "$file" ] || die "missing required file $file"
done

require_line() {
  file=$1
  line=$2
  grep -Fqx "$line" "$file" || die "$file does not contain exact policy: $line"
}

require_line "$schedule" "  pgbackrest: 2.59.1"
require_line "$schedule" "  postgresql: 18.6"
require_line "$schedule" "  archive_boundary_seconds: 60"
require_line "$schedule" '  full: "0 02 * * 0"'
require_line "$schedule" '  differential: "0 02 * * 1-6"'
require_line "$schedule" "  retention_days: 14"
require_line "$schedule" "  wal_retention_days: 14"
require_line "$schedule" "  daily_retention_days: 30"
require_line "$schedule" "  weekly_retention_weeks: 12"
require_line "$schedule" "    cadence: \"15 05 * * *\""
require_line "$schedule" "    object_lock: compliance"
require_line "$schedule" "  healthy_only_after_disposable_restore: true"
require_line "$schedule" "  newest_logical: daily"
require_line "$schedule" "  latest_wal: daily"
require_line "$schedule" "  historical_pitr: weekly_seeded_random"
require_line "$schedule" "  maximum_rpo_seconds: 300"
require_line "$schedule" "  maximum_full_host_seconds: 14400"
require_line "$config" "repo1-cipher-type=aes-256-cbc"
require_line "$config" "repo2-cipher-type=aes-256-cbc"
require_line "$config" "repo1-retention-archive=14"
require_line "$config" "repo2-retention-archive=14"
require_line "$config" "archive-timeout=60"

[ "$(grep -c '^  - id:' "$manifest")" -eq 7 ] || die "durable-state inventory is incomplete"
for id in postgresql_volume physical_repository_primary physical_repository_mirror opentofu_state dns_inputs encryption_keys secret_manifest; do
  grep -Fq "id: $id" "$manifest" || die "durable-state inventory omits $id"
done

grep -Fq 'recovery_credentials_in_app_container: forbidden' "$manifest" || die "app credential separation rule is absent"
grep -Fq 'recovery_credentials_shared_between_repositories: forbidden' "$manifest" || die "repository credential independence rule is absent"

if grep -Ei 'BACKUP_(PRIMARY|MIRROR)|PG_BACKREST|PGBACKREST|recovery/(keys|manifest)|recovery-secret' infra/compose/compose.yml infra/images/server/Dockerfile >/dev/null; then
  die "application image/topology receives recovery credentials or recovery-secret paths"
fi

case "$(sed -n 's/^[[:space:]]*image: postgres:\(.*\)$/\1/p' infra/compose/compose.yml | head -n 1)" in
  18.6-*) ;;
  *) die "Compose PostgreSQL is not pinned to 18.6" ;;
esac

printf '%s\n' "Backup policy verification passed: encrypted independent repositories, exact cadence/retention, and seven durable locations"
