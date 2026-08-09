#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root=$(mktemp -d)
fixture="$test_root/source"
test_bin="$test_root/bin"
action_log="$test_root/actions.log"
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$fixture/bin" "$fixture/development/docker-dbs" "$test_bin"
for route in qv-install-docker-dbs omarchy-install-docker-dbs; do
  install -m 0755 "$root/bin/$route" "$fixture/bin/$route"
done
install -m 0755 "$root/development/docker-dbs/install" \
  "$fixture/development/docker-dbs/install"
install -m 0644 "$root/development/docker-dbs/databases.psv" \
  "$fixture/development/docker-dbs/databases.psv"

install -m 0755 /dev/stdin "$test_bin/qv-cmd-present" <<'STUB'
#!/bin/bash
exit 0
STUB
install -m 0755 /dev/stdin "$test_bin/openssl" <<'STUB'
#!/bin/bash
[[ $* == "rand -hex 24" ]] || exit 2
printf '0123456789abcdef0123456789abcdef0123456789abcdef\n'
STUB
install -m 0755 /dev/stdin "$test_bin/gum" <<'STUB'
#!/bin/bash
(( ${QVOS_TEST_GUM_STATUS:-0} == 0 )) || exit "$QVOS_TEST_GUM_STATUS"
printf 'PostgreSQL\n'
STUB
install -m 0755 /dev/stdin "$test_bin/sudo" <<'STUB'
#!/bin/bash
printf 'sudo:' >>"$QVOS_TEST_ACTION_LOG"
printf '<%s>' "$@" >>"$QVOS_TEST_ACTION_LOG"
printf '\n' >>"$QVOS_TEST_ACTION_LOG"
[[ ${1:-} == "docker" ]] || exit 2
shift
case ${1:-} in
info) exit 0 ;;
container)
  if [[ $* == *'.State.Running'* ]]; then
    printf 'true\n'
    exit 0
  fi
  if [[ ${QVOS_TEST_CONTAINER_STATE:-absent} == "foreign" ]]; then
    printf 'foreign|mysql|mysql:8.4|3306\n'
    exit 0
  fi
  if [[ ${QVOS_TEST_CONTAINER_STATE:-absent} == "managed" ]]; then
    printf 'development/docker-dbs|mysql|mysql:8.4|3306\n'
    exit 0
  fi
  exit 1
  ;;
volume)
  if [[ ${2:-} == "inspect" && ${QVOS_TEST_VOLUME_STATE:-absent} == "foreign" ]]; then
    if [[ $* == *'--format'* ]]; then
      printf 'foreign\n'
    fi
    exit 0
  fi
  [[ ${2:-} == "create" ]] && exit 0
  [[ ${2:-} == "rm" ]] && exit 0
  exit 1
  ;;
run | start) exit 0 ;;
*) exit 2 ;;
esac
STUB

touch "$action_log"
run_database() {
  local home=$1
  shift

  install -d "$home"
  HOME="$home" \
    QVOS_PATH="$fixture" \
    OMARCHY_PATH="$fixture" \
    PATH="$test_bin:/usr/bin" \
    QVOS_TEST_ACTION_LOG="$action_log" \
    "$@"
}

postgres_home="$test_root/postgres-home"
run_database "$postgres_home" \
  "$fixture/bin/qv-install-docker-dbs" postgresql >"$test_root/postgres.out"
postgres_state="$postgres_home/.local/state/qvos/development/docker-dbs/postgresql"
credentials="$postgres_state/credentials.env"
[[ -f $credentials && $(stat -c '%a' "$credentials") == "600" ]] ||
  fail "PostgreSQL private credentials"
[[ $(stat -c '%a' "$postgres_state") == "700" ]] ||
  fail "PostgreSQL private state"
grep -Fqx 'POSTGRES_USER=qvos_admin' "$credentials" ||
  fail "PostgreSQL owner username"
grep -Eq '^POSTGRES_PASSWORD=[0-9a-f]{48}$' "$credentials" ||
  fail "PostgreSQL generated password"
grep -Fq '<--publish><127.0.0.1:5432:5432>' "$action_log" ||
  fail "PostgreSQL loopback binding"
grep -Fq "<--env-file><$credentials>" "$action_log" ||
  fail "PostgreSQL credential file handoff"
grep -Fq '<--volume><qvos-db-postgresql-data:/var/lib/postgresql>' \
  "$action_log" || fail "PostgreSQL persistent volume"
if grep -Fq '0123456789abcdef0123456789abcdef0123456789abcdef' "$action_log"; then
  fail "PostgreSQL secret leaked into Docker arguments"
fi

: >"$action_log"
mysql_home="$test_root/mysql-home"
run_database "$mysql_home" \
  "$fixture/bin/omarchy-install-docker-dbs" mysql >/dev/null
grep -Fq '<--name><qvos-db-mysql>' "$action_log" ||
  fail "Docker DB compatibility owner"

: >"$action_log"
QVOS_TEST_CONTAINER_STATE=managed run_database "$mysql_home" \
  "$fixture/bin/qv-install-docker-dbs" mysql >/dev/null
grep -Fq 'sudo:<docker><start><qvos-db-mysql>' "$action_log" ||
  fail "managed Docker DB rerun"
if grep -Eq '(<run>|<volume><create>)' "$action_log"; then
  fail "managed Docker DB rerun created duplicate resources"
fi

: >"$action_log"
redis_home="$test_root/redis-home"
run_database "$redis_home" \
  "$fixture/bin/qv-install-docker-dbs" redis >/dev/null
redis_state="$redis_home/.local/state/qvos/development/docker-dbs/redis"
[[ -f $redis_state/redis.conf && $(stat -c '%a' "$redis_state/redis.conf") == "600" ]] ||
  fail "Redis private configuration"
[[ -d $redis_state/data && $(stat -c '%a' "$redis_state/data") == "700" ]] ||
  fail "Redis private data"
grep -Fq '<--publish><127.0.0.1:6379:6379>' "$action_log" ||
  fail "Redis loopback binding"
grep -Fq '<--user><' "$action_log" || fail "Redis desktop UID"
if grep -Fq '0123456789abcdef0123456789abcdef0123456789abcdef' "$action_log"; then
  fail "Redis secret leaked into Docker arguments"
fi

for definition in \
  'mongodb:27017:27017:MONGO_INITDB_ROOT_PASSWORD' \
  'mariadb:3307:3306:MARIADB_ROOT_PASSWORD' \
  'mssql:1433:1433:MSSQL_SA_PASSWORD'; do
  IFS=':' read -r database host_port container_port password_key <<<"$definition"
  database_home="$test_root/$database-home"
  : >"$action_log"
  run_database "$database_home" \
    "$fixture/bin/qv-install-docker-dbs" "$database" >/dev/null
  database_credentials="$database_home/.local/state/qvos/development/docker-dbs/$database/credentials.env"
  grep -Eq "^${password_key}=.+" "$database_credentials" ||
    fail "$database generated credential"
  grep -Fq "<--publish><127.0.0.1:$host_port:$container_port>" \
    "$action_log" || fail "$database loopback binding"
  if grep -Fq '0123456789abcdef0123456789abcdef0123456789abcdef' \
    "$action_log"; then
    fail "$database secret leaked into Docker arguments"
  fi
done

cancel_home="$test_root/cancel-home"
set +e
QVOS_TEST_GUM_STATUS=1 run_database "$cancel_home" \
  "$fixture/bin/qv-install-docker-dbs" >/dev/null 2>&1
cancel_status=$?
set -e
(( cancel_status == 130 )) || fail "Docker DB selection cancellation"
[[ ! -e $cancel_home/.local/state/qvos ]] ||
  fail "Docker DB cancellation state"

: >"$action_log"
invalid_home="$test_root/invalid-home"
if run_database "$invalid_home" \
  "$fixture/bin/qv-install-docker-dbs" unknown >/dev/null 2>&1; then
  fail "unknown Docker DB acceptance"
fi
[[ ! -s $action_log && ! -e $invalid_home/.local/state/qvos ]] ||
  fail "unknown Docker DB mutation"

unsafe_home="$test_root/unsafe-home"
foreign_state="$test_root/foreign-state"
install -d "$unsafe_home" "$foreign_state"
ln -s "$foreign_state" "$unsafe_home/.local"
if run_database "$unsafe_home" \
  "$fixture/bin/qv-install-docker-dbs" mysql >/dev/null 2>&1; then
  fail "symbolic-link Docker DB state acceptance"
fi
[[ -z $(find "$foreign_state" -mindepth 1 -print -quit) ]] ||
  fail "symbolic-link Docker DB target mutation"

: >"$action_log"
foreign_container_home="$test_root/foreign-container-home"
if QVOS_TEST_CONTAINER_STATE=foreign run_database "$foreign_container_home" \
  "$fixture/bin/qv-install-docker-dbs" mysql >/dev/null 2>&1; then
  fail "foreign Docker container adoption"
fi
[[ ! -e $foreign_container_home/.local/state/qvos/development/docker-dbs/mysql/credentials.env ]] ||
  fail "foreign Docker container credential creation"
if grep -Fq '<run>' "$action_log"; then
  fail "foreign Docker container replacement"
fi

: >"$action_log"
foreign_volume_home="$test_root/foreign-volume-home"
if QVOS_TEST_VOLUME_STATE=foreign run_database "$foreign_volume_home" \
  "$fixture/bin/qv-install-docker-dbs" mysql >/dev/null 2>&1; then
  fail "foreign Docker volume adoption"
fi
if grep -Fq '<run>' "$action_log"; then
  fail "foreign Docker volume container creation"
fi

: >"$action_log"
managed_home="$test_root/managed-home"
if QVOS_TEST_CONTAINER_STATE=managed run_database "$managed_home" \
  "$fixture/bin/qv-install-docker-dbs" mysql >/dev/null 2>&1; then
  fail "managed Docker container without credentials"
fi
if grep -Fq '<start>' "$action_log"; then
  fail "managed Docker container started without credentials"
fi

"$root/development/docker-dbs/check"
printf 'ok - Docker DB installation is local, private, persistent, and non-adopting\n'
