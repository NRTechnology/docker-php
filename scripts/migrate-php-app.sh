#!/usr/bin/env bash
#
# migrate-php-app.sh
# Batch migration helper for Docker-PHP applications.
#
# Scans /opt/docker-apps, identifies Compose projects using local/php images,
# reports missing baseline settings, and optionally applies safe additive
# changes (Docker log rotation and PHP-FPM healthcheck).
#
# IMPORTANT:
# - Does not start/recreate containers.
# - Does not modify Nginx, databases, volumes, networks, Wazuh Agent, or groups.
# - Does not remove unknown Compose settings.
# - Uses text-preserving insertion for missing service-level YAML keys.
# - A per-application backup is created before every changed Compose file.
#
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_NAME="migrate-php-app.sh"
SCRIPT_VERSION="1.0.0"

DOCKER_APPS_DIR="/opt/docker-apps"
REGISTRY_DIR="/var/lib/docker-php/monitoring/applications"
BACKUP_ROOT="${DOCKER_APPS_DIR}/.migration-backup"
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}"

MODE="scan"
VERBOSE=0
APP_FILTER=""

log()  { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
err()  { printf '[ERROR] %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

usage() {
    cat <<EOF
${SCRIPT_NAME} v${SCRIPT_VERSION}

Memindai dan memigrasikan seluruh aplikasi Docker-PHP di:
  ${DOCKER_APPS_DIR}

Usage:
  ./${SCRIPT_NAME}                       Scan seluruh aplikasi (default)
  ./${SCRIPT_NAME} --dry-run             Scan tanpa mengubah file
  ./${SCRIPT_NAME} --apply               Terapkan perubahan aman
  ./${SCRIPT_NAME} --apply --name APP    Terapkan hanya untuk satu aplikasi
  ./${SCRIPT_NAME} --rollback           Pulihkan backup migrasi terbaru
  ./${SCRIPT_NAME} --rollback --name APP Pulihkan backup terbaru aplikasi
  ./${SCRIPT_NAME} --verbose             Tampilkan detail tambahan
  ./${SCRIPT_NAME} --version
  ./${SCRIPT_NAME} --help

Perubahan yang dapat diterapkan:
  - Docker json-file log rotation (10m x 5), jika belum ada.
  - PHP-FPM healthcheck dasar, jika belum ada.
  - Application Registry JSON, jika metadata dapat ditentukan.

Batasan:
  - Tidak menjalankan docker compose up/recreate.
  - Tidak mengubah Nginx, database, volume, network, Wazuh Agent/group.
  - Tidak mengganti konfigurasi logging/healthcheck yang sudah ada.
  - Compose yang gagal divalidasi akan dikembalikan dari backup.
EOF
}

while (($#)); do
    case "$1" in
        --dry-run) MODE="scan"; shift ;;
        --apply) MODE="apply"; shift ;;
        --rollback) MODE="rollback"; shift ;;
        --name)
            [[ $# -ge 2 && -n "${2:-}" ]] || die "--name memerlukan nama aplikasi."
            APP_FILTER="$2"; shift 2 ;;
        --verbose|-v) VERBOSE=1; shift ;;
        --version|-V) echo "${SCRIPT_NAME} version ${SCRIPT_VERSION}"; exit 0 ;;
        --help|-h) usage; exit 0 ;;
        *) die "Opsi tidak dikenal: $1" ;;
    esac
done

[[ "$EUID" -eq 0 ]] || die "Jalankan script sebagai root."
command -v docker >/dev/null 2>&1 || die "Docker tidak ditemukan."
docker compose version >/dev/null 2>&1 || die "Docker Compose plugin tidak ditemukan."
command -v python3 >/dev/null 2>&1 || die "python3 tidak ditemukan."
[[ -d "$DOCKER_APPS_DIR" ]] || die "Direktori tidak ditemukan: ${DOCKER_APPS_DIR}"

# The embedded helper uses only Python standard library. Compose itself parses
# YAML and emits normalized JSON, avoiding an additional YAML parser dependency.
compose_json() {
    local compose_file="$1"
    local project_dir
    project_dir="$(dirname "$compose_file")"
    (cd "$project_dir" && docker compose -f "$compose_file" config --format json 2>/dev/null)
}

is_php_project() {
    local json="$1"
    python3 - "$json" <<'PY'
import json, sys
try:
    obj=json.loads(sys.argv[1])
except Exception:
    sys.exit(1)
for svc in (obj.get("services") or {}).values():
    image=str(svc.get("image") or "")
    if image.startswith("local/php:"):
        sys.exit(0)
sys.exit(1)
PY
}

service_for_php() {
    local json="$1"
    python3 - "$json" <<'PY'
import json, sys
obj=json.loads(sys.argv[1])
for name, svc in (obj.get("services") or {}).items():
    if str(svc.get("image") or "").startswith("local/php:"):
        print(name)
        break
PY
}

report_one() {
    local app="$1" compose_file="$2" json="$3" service="$4"
    python3 - "$app" "$compose_file" "$json" "$service" <<'PY'
import json, os, sys
app, compose_file, raw, service = sys.argv[1:]
obj=json.loads(raw)
svc=(obj.get("services") or {}).get(service) or {}
image=str(svc.get("image") or "")
version=image.split(":",1)[1] if ":" in image else "unknown"
container=str(svc.get("container_name") or (app+"-php"))
logging=svc.get("logging") or {}
log_ok=(logging.get("driver")=="json-file" and
        str((logging.get("options") or {}).get("max-size",""))=="10m" and
        str((logging.get("options") or {}).get("max-file",""))=="5")
health_ok=bool(svc.get("healthcheck"))
ro=svc.get("read_only") is True
sec=any("no-new-privileges:true" in str(x) for x in (svc.get("security_opt") or []))
limits=bool(svc.get("cpus") or svc.get("mem_limit") or svc.get("pids_limit"))
mounts=svc.get("volumes") or []
source=""
writable=""
for m in mounts:
    if isinstance(m,dict):
        src=str(m.get("source") or "")
        dst=str(m.get("target") or "")
        rw=not bool(m.get("read_only",False))
    else:
        continue
    if dst=="/var/www/html":
        source=src
    if rw and (dst.endswith("/data") or dst.endswith("/writable") or "/storage/" in dst):
        writable=src if not writable else writable+";"+src
# Framework inference is intentionally conservative.
framework="unknown"
targets=" ".join(str(m.get("target","")) for m in mounts if isinstance(m,dict))
if "/var/www/html/storage/app" in targets or "/var/www/html/bootstrap/cache" in targets:
    framework="laravel"
elif "/var/www/html/writable" in targets:
    framework="ci"
elif "/var/www/html/data" in targets:
    framework="generic"
registry=os.path.join("/var/lib/docker-php/monitoring/applications", app+".json")
print(f"Application       : {app}")
print(f"  Compose         : {compose_file}")
print(f"  PHP service     : {service}")
print(f"  Container       : {container}")
print(f"  Image           : {image}")
print(f"  Framework       : {framework}")
print(f"  Logging         : {'OK' if log_ok else 'MISSING / NONSTANDARD'}")
print(f"  Healthcheck     : {'OK' if health_ok else 'MISSING'}")
print(f"  Read-only       : {'OK' if ro else 'MISSING'}")
print(f"  no-new-privileges: {'OK' if sec else 'MISSING'}")
print(f"  Resource limits : {'PRESENT' if limits else 'REVIEW'}")
print(f"  Source mount    : {source or 'UNKNOWN'}")
print(f"  Writable mount  : {writable or 'UNKNOWN'}")
print(f"  Registry        : {'EXISTS' if os.path.isfile(registry) else 'MISSING'}")
changes=[]
if not logging: changes.append("Add Docker log rotation")
elif not log_ok: changes.append("Logging exists but differs; preserve (manual review)")
if not health_ok: changes.append("Add basic PHP-FPM healthcheck")
if not os.path.isfile(registry): changes.append("Create Application Registry")
print("  Planned         : "+("; ".join(changes) if changes else "No change required"))
PY
}

# Add missing keys to the PHP service without parsing/re-serializing YAML.
# Compose has already parsed the file. This helper only inserts at service scope.
patch_compose() {
    local compose_file="$1" service="$2"
    python3 - "$compose_file" "$service" <<'PY'
from pathlib import Path
import re, sys
path=Path(sys.argv[1]); service=sys.argv[2]
text=path.read_text()
lines=text.splitlines(keepends=True)

# Find the service declaration under services: (standard 2-space Compose layout).
service_re=re.compile(r'^  '+re.escape(service)+r':[ \t]*(?:#.*)?(?:\r?\n)?$')
start=None
for i,line in enumerate(lines):
    if service_re.match(line):
        start=i
        break
if start is None:
    raise SystemExit(f"Service '{service}' tidak ditemukan pada format Compose standar.")

# Determine service block end: next sibling service (2 spaces) or top-level key.
end=len(lines)
for i in range(start+1,len(lines)):
    line=lines[i]
    if re.match(r'^  [A-Za-z0-9_.-]+:[ \t]*(?:#.*)?(?:\r?\n)?$',line):
        end=i; break
    if re.match(r'^[A-Za-z0-9_.-]+:[ \t]*(?:#.*)?(?:\r?\n)?$',line):
        end=i; break

block=''.join(lines[start+1:end])
has_logging=bool(re.search(r'(?m)^    logging\s*:',block))
has_health=bool(re.search(r'(?m)^    healthcheck\s*:',block))
insert=[]
if not has_logging:
    insert += [
        '    # Added by migrate-php-app.sh: bounded container stdout/stderr logs.\n',
        '    logging:\n',
        '      driver: json-file\n',
        '      options:\n',
        '        max-size: "10m"\n',
        '        max-file: "5"\n',
        '\n',
    ]
if not has_health:
    insert += [
        '    # Added by migrate-php-app.sh: basic PHP-FPM process/config check.\n',
        '    healthcheck:\n',
        '      test: ["CMD-SHELL", "php-fpm -t >/dev/null 2>&1 && kill -0 1"]\n',
        '      interval: 30s\n',
        '      timeout: 5s\n',
        '      retries: 3\n',
        '      start_period: 30s\n',
        '\n',
    ]
if insert:
    lines[start+1:start+1]=insert
    path.write_text(''.join(lines))
print(("logging="+("existing" if has_logging else "added")+
       ", healthcheck="+("existing" if has_health else "added")))
PY
}

write_registry() {
    local app="$1" compose_file="$2" json="$3" service="$4"
    mkdir -p "$REGISTRY_DIR"
    chmod 0750 "$(dirname "$REGISTRY_DIR")" "$REGISTRY_DIR"
    python3 - "$app" "$compose_file" "$json" "$service" "$REGISTRY_DIR" <<'PY'
import json, os, sys, tempfile
app, compose_file, raw, service, outdir=sys.argv[1:]
obj=json.loads(raw); svc=(obj.get("services") or {}).get(service) or {}
image=str(svc.get("image") or "")
php=image.split(":",1)[1] if ":" in image else "unknown"
container=str(svc.get("container_name") or app+"-php")
source=""
writable=[]
for m in svc.get("volumes") or []:
    if not isinstance(m,dict): continue
    dst=str(m.get("target") or "")
    src=str(m.get("source") or "")
    if dst=="/var/www/html": source=src
    if not m.get("read_only",False) and (
        dst.endswith("/data") or dst.endswith("/writable") or
        "/storage/" in dst or dst.endswith("/bootstrap/cache")
    ):
        writable.append(src)
targets=" ".join(str(m.get("target","")) for m in svc.get("volumes") or [] if isinstance(m,dict))
framework="unknown"
if "/var/www/html/storage/app" in targets or "/var/www/html/bootstrap/cache" in targets:
    framework="laravel"
elif "/var/www/html/writable" in targets:
    framework="ci"
elif "/var/www/html/data" in targets:
    framework="generic"
record={
 "integration":"docker-php",
 "application":app,
 "container":container,
 "php_version":php,
 "framework":framework,
 "source":source or None,
 "writable":writable[0] if len(writable)==1 else writable or None,
 "compose":compose_file,
 "monitoring":{
  "fim":False,
  "docker_health":bool(svc.get("healthcheck")),
  "security":False,
  "malware":False,
  "php_fpm":False
 }
}
os.makedirs(outdir,exist_ok=True)
target=os.path.join(outdir,app+".json")
# Do not overwrite an existing registry; preserve operator-maintained metadata.
if os.path.exists(target):
    print("EXISTS")
else:
    fd,tmp=tempfile.mkstemp(prefix="."+app+".",suffix=".tmp",dir=outdir)
    try:
        with os.fdopen(fd,"w") as f:
            json.dump(record,f,indent=2); f.write("\n"); f.flush(); os.fsync(f.fileno())
        os.chmod(tmp,0o640)
        os.replace(tmp,target)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)
    print("CREATED")
PY
}

find_compose() {
    local dir="$1"
    if [[ -f "${dir}/docker-compose.yml" ]]; then
        printf '%s' "${dir}/docker-compose.yml"
    elif [[ -f "${dir}/compose.yaml" ]]; then
        printf '%s' "${dir}/compose.yaml"
    elif [[ -f "${dir}/compose.yml" ]]; then
        printf '%s' "${dir}/compose.yml"
    fi
}

rollback_app() {
    local app="$1"
    local latest=""
    [[ -d "$BACKUP_ROOT" ]] || return 1
    latest="$(find "$BACKUP_ROOT" -mindepth 2 -maxdepth 2 -type f \
        \( -name docker-compose.yml -o -name compose.yaml -o -name compose.yml \) \
        -path "*/${app}/*" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2-)"
    [[ -n "$latest" && -f "$latest" ]] || return 1
    local original_name
    original_name="$(basename "$latest")"
    local target="${DOCKER_APPS_DIR}/${app}/${original_name}"
    cp -a "$latest" "$target"
    # Remove only a registry file created by this migration backup.
    local marker="$(dirname "$latest")/registry-created.marker"
    if [[ -f "$marker" ]]; then
        rm -f "${REGISTRY_DIR}/${app}.json"
        log "Rollback ${app}: registry hasil migrasi dihapus."
    fi
    log "Rollback ${app}: dipulihkan dari ${latest}"
}

if [[ "$MODE" == "rollback" ]]; then
    [[ "$EUID" -eq 0 ]] || die "Rollback harus dijalankan sebagai root."
    if [[ -n "$APP_FILTER" ]]; then
        rollback_app "$APP_FILTER" || die "Backup tidak ditemukan untuk ${APP_FILTER}."
    else
        [[ -d "$BACKUP_ROOT" ]] || die "Direktori backup belum ada."
        count=0
        for d in "$DOCKER_APPS_DIR"/*; do
            [[ -d "$d" ]] || continue
            app="$(basename "$d")"
            if rollback_app "$app"; then count=$((count+1)); fi
        done
        log "Rollback selesai. File dipulihkan: ${count}"
    fi
    exit 0
fi

if [[ "$MODE" == "apply" ]]; then
    mkdir -p "$BACKUP_DIR"
    chmod 0700 "$BACKUP_ROOT" "$BACKUP_DIR"
    log "Backup migrasi: ${BACKUP_DIR}"
fi

scanned=0
eligible=0
changed=0
failed=0
skipped=0

printf '\n============================================================\n'
printf ' DOCKER-PHP BATCH MIGRATION SCAN v%s\n' "$SCRIPT_VERSION"
printf ' Directory: %s\n' "$DOCKER_APPS_DIR"
printf ' Mode     : %s\n' "$MODE"
printf '============================================================\n\n'

shopt -s nullglob
for app_dir in "$DOCKER_APPS_DIR"/*; do
    [[ -d "$app_dir" ]] || continue
    app="$(basename "$app_dir")"
    [[ "$app" == ".migration-backup" ]] && continue
    [[ -z "$APP_FILTER" || "$app" == "$APP_FILTER" ]] || continue

    compose_file="$(find_compose "$app_dir" || true)"
    [[ -n "$compose_file" ]] || { ((skipped+=1)); ((scanned+=1)); continue; }
    ((scanned+=1))

    if ! json="$(compose_json "$compose_file")"; then
        warn "${app}: Compose tidak dapat diparse/dirender; SKIP."
        ((failed+=1))
        continue
    fi
    if ! is_php_project "$json"; then
        [[ "$VERBOSE" -eq 1 ]] && log "${app}: bukan project local/php; SKIP."
        ((skipped+=1))
        continue
    fi
    ((eligible+=1))
    service="$(service_for_php "$json")"
    [[ -n "$service" ]] || { warn "${app}: service PHP tidak ditemukan."; ((failed+=1)); continue; }

    printf '%s\n' '------------------------------------------------------------'
    report_one "$app" "$compose_file" "$json" "$service"

    if [[ "$MODE" != "apply" ]]; then
        continue
    fi

    # Determine whether additive changes are needed before taking a backup.
    need_patch="$(python3 - "$json" "$service" <<'PY'
import json,sys
obj=json.loads(sys.argv[1]); svc=(obj.get("services") or {}).get(sys.argv[2]) or {}
print("yes" if not svc.get("logging") or not svc.get("healthcheck") else "no")
PY
)"
    backup_app="${BACKUP_DIR}/${app}"
    mkdir -p "$backup_app"
    chmod 0700 "$backup_app"

    if [[ "$need_patch" == "yes" ]]; then
        cp -a "$compose_file" "$backup_app/$(basename "$compose_file")"
        if ! patch_compose "$compose_file" "$service"; then
            cp -a "$backup_app/$(basename "$compose_file")" "$compose_file"
            warn "${app}: patch gagal; konfigurasi dipulihkan."
            ((failed+=1))
            continue
        fi
        if ! (cd "$app_dir" && docker compose -f "$compose_file" config >/dev/null); then
            cp -a "$backup_app/$(basename "$compose_file")" "$compose_file"
            warn "${app}: validasi Compose gagal; konfigurasi dipulihkan."
            ((failed+=1))
            continue
        fi
        ((changed+=1))
        log "${app}: Compose berhasil diperbarui dan divalidasi."
    else
        log "${app}: tidak membutuhkan perubahan Compose."
    fi

    # Re-read normalized configuration after patch; registry is based on
    # effective Compose data. Never overwrite existing registry metadata.
    if ! json_after="$(compose_json "$compose_file")"; then
        warn "${app}: gagal membaca Compose setelah perubahan; registry dilewati."
        ((failed+=1))
        continue
    fi
    registry_result="$(write_registry "$app" "$compose_file" "$json_after" "$service")" || {
        warn "${app}: gagal membuat registry."
        ((failed+=1))
        continue
    }
    if [[ "$registry_result" == "CREATED" ]]; then
        : > "${backup_app}/registry-created.marker"
        chmod 0600 "${backup_app}/registry-created.marker"
    fi
    log "${app}: registry ${registry_result}."
done

printf '\n============================================================\n'
printf ' MIGRATION SUMMARY\n'
printf '============================================================\n'
printf 'Directories scanned : %d\n' "$scanned"
printf 'PHP applications    : %d\n' "$eligible"
printf 'Compose changed     : %d\n' "$changed"
printf 'Skipped             : %d\n' "$skipped"
printf 'Failed              : %d\n' "$failed"
if [[ "$MODE" == "apply" ]]; then
    printf 'Backup directory    : %s\n' "$BACKUP_DIR"
    printf '\nContainer tidak di-recreate. Jadwalkan penerapan dengan:\n'
    printf '  cd /opt/docker-apps/<app> && docker compose up -d\n'
else
    printf '\nTidak ada file yang diubah. Gunakan --apply untuk menerapkan.\n'
fi
printf '============================================================\n'

[[ "$failed" -eq 0 ]]
