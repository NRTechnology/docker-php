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
# - Only runs docker compose up -d when --apply changes a Compose file.
# - Does not modify Nginx, databases, volumes, networks, Wazuh Agent, or groups.
# - Creates/validates Application Registry for existing Docker-PHP applications.
# - Never installs or changes Wazuh Agent configuration.
# - Does not remove unknown Compose settings.
# - Uses text-preserving insertion for missing service-level YAML keys.
# - A per-application backup is created before every changed Compose file.
#
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_NAME="migrate-php-app.sh"
SCRIPT_VERSION="1.3.1"

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
  ./${SCRIPT_NAME} --apply               Migrasi, validasi, lalu compose up -d
  ./${SCRIPT_NAME} --apply --name APP    Terapkan hanya untuk satu aplikasi
  ./${SCRIPT_NAME} --rollback           Pulihkan backup migrasi terbaru
  ./${SCRIPT_NAME} --rollback --name APP Pulihkan backup terbaru aplikasi
  ./${SCRIPT_NAME} --verbose             Tampilkan detail tambahan
  ./${SCRIPT_NAME} --version
  ./${SCRIPT_NAME} --help

Perubahan yang dapat diterapkan:
  - Docker json-file log rotation (10m x 5), jika belum ada.
  - PHP-FPM healthcheck dasar, jika belum ada.
  - Application Registry JSON untuk aplikasi existing, jika metadata valid.
  - FIM diaktifkan hanya jika source dan seluruh writable mount valid.
  - Registry existing yang valid dan sesuai Compose dipertahankan.
  - Registry valid dengan writable berbeda diperbarui hanya pada field writable,
    setelah backup; metadata lainnya dipertahankan.
  - Registry invalid tidak pernah ditimpa otomatis.
  - Perubahan registry dicadangkan dan dapat dipulihkan dengan --rollback.

Alur --apply:
  1. Backup Compose.
  2. Tambahkan logging/healthcheck yang belum ada.
  3. Validasi seluruh Compose yang diproses.
  4. Buat registry jika belum ada; registry existing diklasifikasikan:
     valid/sesuai, valid tetapi writable berbeda (diperbarui saat --apply
     dengan backup), atau invalid (tidak ditimpa).
  5. Jika semua validasi berhasil, jalankan docker compose up -d
     untuk aplikasi yang Compose-nya berubah.
  6. Buat report TXT dan JSON.

Batasan:
  - docker compose up -d dapat recreate container aplikasi yang berubah.
  - Tidak mengubah Nginx, database, volume, network, Wazuh Agent/group.
  - Tidak memasang Agent atau mengubah konfigurasi Agent; itu tugas install-agent.sh.
  - install-agent.sh hanya membaca dan mengintegrasikan registry yang sudah disiapkan.
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
registry_status = "MISSING (create on --apply)"
if os.path.isfile(registry):
    try:
        existing=json.load(open(registry, encoding="utf-8"))
        app_root=os.path.realpath(os.path.join("/var/apps", app))
        expected_source=os.path.realpath(source) if source else ""
        expected_writable=sorted(os.path.realpath(x) for x in writable.split(";") if x)
        old_w=existing.get("writable") if isinstance(existing,dict) else None
        old_list=old_w if isinstance(old_w,list) else ([old_w] if isinstance(old_w,str) and old_w else [])
        old_list=sorted(os.path.realpath(x) for x in old_list if isinstance(x,str))
        core_ok=(isinstance(existing,dict) and existing.get("integration")=="docker-php"
            and existing.get("application")==app and existing.get("container")==container
            and existing.get("source")==expected_source
            and isinstance(existing.get("monitoring"),dict) and bool(old_list))
        def inside(path):
            try: return os.path.commonpath([app_root,path])==app_root
            except ValueError: return False
        paths_ok=bool(expected_writable) and all(os.path.isdir(x) and inside(x) for x in expected_writable)
        old_paths_ok=all(os.path.isdir(x) and inside(x) for x in old_list)
        if not core_ok or not paths_ok or not old_paths_ok:
            registry_status="INVALID (will not overwrite)"
        elif old_list == expected_writable:
            registry_status="VALID (preserve)"
        else:
            registry_status="VALID, WRITABLE DIFFERS (repair on --apply)"
    except Exception:
        registry_status="INVALID (will not overwrite)"
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
print(f"  Registry        : {registry_status}")
changes=[]
if not logging: changes.append("Add Docker log rotation")
elif not log_ok: changes.append("Logging exists but differs; preserve (manual review)")
if not health_ok: changes.append("Add basic PHP-FPM healthcheck")
if not os.path.isfile(registry): changes.append("Create Application Registry for existing app")
else: changes.append("Classify existing Registry; repair writable only if safely mismatched")
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
    local app="$1" compose_file="$2" json="$3" service="$4" backup_app="$5"
    mkdir -p "$REGISTRY_DIR"
    chmod 0750 "$(dirname "$REGISTRY_DIR")" "$REGISTRY_DIR"
    python3 - "$app" "$compose_file" "$json" "$service" "$REGISTRY_DIR" "$backup_app" <<'PY'
import json, os, sys, tempfile, shutil
from pathlib import Path
app, compose_file, raw, service, outdir, backup_dir = sys.argv[1:]
obj=json.loads(raw); svc=(obj.get("services") or {}).get(service)
if not isinstance(svc,dict): raise SystemExit(f"Service PHP '{service}' tidak ditemukan.")
image=str(svc.get("image") or "")
if not image.startswith("local/php:"): raise SystemExit(f"Image service '{service}' bukan local/php.")
php=image.split(":",1)[1] if ":" in image else "unknown"
container=str(svc.get("container_name") or app+"-php")
compose_path=Path(compose_file).resolve(); compose_dir=compose_path.parent
def host_path(value):
    p=Path(value)
    if not p.is_absolute(): p=compose_dir/p
    return p.resolve()
source_values=[]; writable_values=[]
for mount in svc.get("volumes") or []:
    if not isinstance(mount,dict): continue
    dst=str(mount.get("target") or ""); src=str(mount.get("source") or "")
    if dst=="/var/www/html" and src: source_values.append(host_path(src))
    if src and not mount.get("read_only",False) and (
        dst.endswith("/data") or dst.endswith("/writable") or "/storage/" in dst
        or dst.endswith("/bootstrap/cache")):
        writable_values.append(host_path(src))
if len(source_values)!=1:
    raise SystemExit("Mount source /var/www/html tidak ditemukan atau ambigu; registry tidak diubah.")
source_path=source_values[0]
writable_paths=sorted({str(p) for p in writable_values})
if not writable_paths: raise SystemExit("Tidak ada writable mount yang dikenali; registry tidak diubah.")
app_root=(Path("/var/apps")/app).resolve()
def inside_app(path):
    try: Path(path).relative_to(app_root); return True
    except ValueError: return False
source_valid=source_path.is_dir() and inside_app(source_path)
writable_valid=all(Path(p).is_dir() and inside_app(p) for p in writable_paths)
fim_eligible=source_valid and writable_valid
targets=" ".join(str(m.get("target","")) for m in (svc.get("volumes") or []) if isinstance(m,dict))
framework="unknown"
if "/var/www/html/storage/app" in targets or "/var/www/html/bootstrap/cache" in targets: framework="laravel"
elif "/var/www/html/writable" in targets: framework="ci"
elif "/var/www/html/data" in targets: framework="generic"
target=Path(outdir)/(app+".json"); target.parent.mkdir(parents=True,mode=0o750,exist_ok=True)
backup_path=Path(backup_dir)/"registry-before.json"
def atomic_write(record):
    fd,tmp=tempfile.mkstemp(prefix="."+app+".",suffix=".tmp",dir=outdir)
    try:
        with os.fdopen(fd,"w",encoding="utf-8") as f:
            json.dump(record,f,indent=2,ensure_ascii=False); f.write("\n"); f.flush(); os.fsync(f.fileno())
        os.chmod(tmp,0o640); os.replace(tmp,target)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)
def normalize_writable(value):
    if isinstance(value,str) and value: values=[value]
    elif isinstance(value,list) and value and all(isinstance(x,str) and x for x in value): values=value
    else: return None
    try: return sorted({str(Path(x).resolve(strict=True)) for x in values})
    except (OSError,RuntimeError): return None
if target.exists():
    # CONDITION 3: invalid registry; never overwrite automatically.
    try: existing=json.loads(target.read_text(encoding="utf-8"))
    except Exception as exc: raise SystemExit(f"REGISTRY_INVALID: JSON tidak valid ({exc}); registry tidak diubah.")
    if not isinstance(existing,dict):
        raise SystemExit("REGISTRY_INVALID: root registry harus JSON object; registry tidak diubah.")
    required={"integration":"docker-php","application":app,"container":container,"source":str(source_path)}
    mismatch=[k for k,v in required.items() if existing.get(k)!=v]
    if mismatch:
        raise SystemExit("REGISTRY_INVALID: field inti tidak sesuai Compose ("+", ".join(mismatch)+"); registry tidak diubah.")
    if not isinstance(existing.get("monitoring"),dict):
        raise SystemExit("REGISTRY_INVALID: object monitoring tidak valid; registry tidak diubah.")
    if not source_valid or not writable_valid:
        raise SystemExit("REGISTRY_INVALID: source/writable Compose harus berupa direktori yang ada di dalam /var/apps/"+app+"; registry tidak diubah.")
    old_writable=normalize_writable(existing.get("writable"))
    if old_writable is None:
        raise SystemExit("REGISTRY_INVALID: field writable kosong/tidak valid atau path tidak tersedia; registry tidak diubah.")
    if old_writable==writable_paths:
        # CONDITION 1: valid and exact; preserve all metadata.
        if fim_eligible and existing["monitoring"].get("fim") is not True:
            backup_path.parent.mkdir(parents=True,exist_ok=True)
            if not backup_path.exists(): shutil.copy2(target,backup_path)
            existing["monitoring"]["fim"]=True; atomic_write(existing)
            print("EXISTS_FIM_ENABLED")
        else: print("EXISTS_VALID")
    else:
        # CONDITION 2: valid core registry, writable differs. Backup first,
        # update only writable, preserve all other metadata.
        backup_path.parent.mkdir(parents=True,exist_ok=True)
        if not backup_path.exists(): shutil.copy2(target,backup_path)
        existing["writable"]=writable_paths[0] if len(writable_paths)==1 else writable_paths
        if fim_eligible: existing["monitoring"]["fim"]=True
        atomic_write(existing); print("EXISTS_WRITABLE_UPDATED")
else:
    record={"integration":"docker-php","application":app,"container":container,
        "php_version":php,"framework":framework,"source":str(source_path),
        "writable":writable_paths[0] if len(writable_paths)==1 else writable_paths,
        "compose":str(compose_path),
        "monitoring":{"fim":bool(fim_eligible),"docker_health":bool(svc.get("healthcheck")),
                      "security":False,"malware":False,"php_fpm":False}}
    atomic_write(record)
    print("CREATED_FIM_ENABLED" if fim_eligible else "CREATED_FIM_DISABLED_PATH_INVALID")
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
    # Restore a registry that this migration changed, or remove one it created.
    local app_backup="$(dirname "$latest")"
    local registry="${REGISTRY_DIR}/${app}.json"
    if [[ -f "${app_backup}/registry-before.json" && -f "$registry" ]]; then
        cp -a "${app_backup}/registry-before.json" "$registry"
        log "Rollback ${app}: registry sebelum migrasi dipulihkan."
    fi
    local marker="${app_backup}/registry-created.sha256"
    if [[ ! -f "${app_backup}/registry-before.json" && -f "$marker" && -f "$registry" ]]; then
        local expected actual
        expected="$(cat "$marker")"
        actual="$(sha256sum "${REGISTRY_DIR}/${app}.json" | awk '{print $1}')"
        if [[ "$expected" == "$actual" ]]; then
            rm -f "${REGISTRY_DIR}/${app}.json"
            log "Rollback ${app}: registry hasil migrasi dihapus."
        else
            warn "Rollback ${app}: registry sudah berubah; tidak dihapus."
        fi
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

REPORT_ROOT="${DOCKER_APPS_DIR}/.migration-reports"
REPORT_TXT="${REPORT_ROOT}/migration-${TIMESTAMP}.txt"
REPORT_JSON="${REPORT_ROOT}/migration-${TIMESTAMP}.json"

if [[ "$MODE" == "apply" ]]; then
    mkdir -p "$BACKUP_DIR" "$REPORT_ROOT"
    chmod 0700 "$BACKUP_ROOT" "$BACKUP_DIR" "$REPORT_ROOT"
    exec > >(tee -a "$REPORT_TXT") 2>&1
    log "Backup migrasi: ${BACKUP_DIR}"
    log "Report: ${REPORT_TXT}"
fi

scanned=0
eligible=0
changed=0
failed=0
skipped=0
registry_created=0
compose_up_ok=0
compose_up_failed=0
declare -a APPS_TO_UP=()
declare -a VALIDATED_APPS=()
declare -a FAILED_APPS=()

printf '\n============================================================\n'
printf ' DOCKER-PHP BATCH MIGRATION SCAN v%s\n' "$SCRIPT_VERSION"
printf ' Directory: %s\n' "$DOCKER_APPS_DIR"
printf ' Mode     : %s\n' "$MODE"
printf ' Registry : create for existing apps; validate/preserve if present\n'
printf ' Agent    : not installed or modified by this script\n'
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
            FAILED_APPS+=("$app:patch")
            ((failed+=1))
            continue
        fi
        if ! (cd "$app_dir" && docker compose -f "$compose_file" config >/dev/null); then
            cp -a "$backup_app/$(basename "$compose_file")" "$compose_file"
            warn "${app}: validasi Compose gagal; konfigurasi dipulihkan."
            FAILED_APPS+=("$app:validation")
            ((failed+=1))
            continue
        fi
        ((changed+=1))
        APPS_TO_UP+=("$app")
        log "${app}: Compose berhasil diperbarui dan divalidasi."
    else
        # Keep a Compose snapshot even for registry-only changes so --rollback
        # can locate this migration backup and restore registry-before.json.
        cp -a "$compose_file" "$backup_app/$(basename "$compose_file")"
        log "${app}: tidak membutuhkan perubahan Compose; container tidak perlu di-up ulang."
    fi

    # Re-read normalized configuration after patch; registry is based on
    # effective Compose data. Never overwrite existing registry metadata.
    if ! json_after="$(compose_json "$compose_file")"; then
        warn "${app}: gagal membaca Compose setelah perubahan; registry dilewati."
        FAILED_APPS+=("$app:post-config")
        ((failed+=1))
        continue
    fi
    registry_result="$(write_registry "$app" "$compose_file" "$json_after" "$service" "$backup_app")" || {
        warn "${app}: registry gagal divalidasi/diperbarui; registry existing tidak ditimpa."
        FAILED_APPS+=("$app:registry")
        ((failed+=1))
        continue
    }
    if [[ "$registry_result" == "CREATED_FIM_ENABLED" || "$registry_result" == "CREATED_FIM_DISABLED_PATH_INVALID" ]]; then
        sha256sum "${REGISTRY_DIR}/${app}.json" | awk '{print $1}' > "${backup_app}/registry-created.sha256"
        chmod 0600 "${backup_app}/registry-created.sha256"
        ((registry_created+=1))
        log "${app}: Application Registry dibuat (${registry_result})."
    elif [[ "$registry_result" == "EXISTS_FIM_ENABLED" ]]; then
        log "${app}: Registry valid; hanya monitoring.fim diaktifkan. Container tidak direcreate."
    elif [[ "$registry_result" == "EXISTS_VALID" ]]; then
        log "${app}: Registry valid dan writable sesuai Compose; metadata dipertahankan."
    elif [[ "$registry_result" == "EXISTS_WRITABLE_UPDATED" ]]; then
        log "${app}: Registry valid tetapi writable berbeda; field writable diperbarui setelah backup. Metadata lainnya dipertahankan."
    elif [[ "$registry_result" == "EXISTS_FIM_NOT_ELIGIBLE" ]]; then
        warn "${app}: FIM tidak diaktifkan karena source/writable path belum valid."
    else
        warn "${app}: status registry tidak dikenal: ${registry_result}"
        FAILED_APPS+=("$app:registry-result")
        ((failed+=1))
        continue
    fi
    VALIDATED_APPS+=("$app")
done

# Start/recreate only after every eligible application's Compose is valid.
if [[ "$MODE" == "apply" ]]; then
    if [[ "$failed" -eq 0 ]]; then
        log "Semua konfigurasi Compose valid. Memulai tahap docker compose up -d."
        for app in "${APPS_TO_UP[@]}"; do
            app_dir="${DOCKER_APPS_DIR}/${app}"
            compose_file="$(find_compose "$app_dir" || true)"
            if [[ -z "$compose_file" ]]; then
                warn "${app}: file Compose hilang sebelum compose up."
                FAILED_APPS+=("$app:compose-missing")
                ((failed+=1))
                ((compose_up_failed+=1))
                continue
            fi
            if (cd "$app_dir" && docker compose -f "$compose_file" up -d); then
                log "${app}: docker compose up -d berhasil."
                ((compose_up_ok+=1))
            else
                warn "${app}: docker compose up -d GAGAL. Periksa container secara manual."
                FAILED_APPS+=("$app:compose-up")
                ((failed+=1))
                ((compose_up_failed+=1))
            fi
        done
    else
        warn "Ada konfigurasi/operasi gagal. Tahap docker compose up -d dibatalkan untuk seluruh batch."
    fi
fi

printf '\n============================================================\n'
printf ' MIGRATION SUMMARY\n'
printf '============================================================\n'
printf 'Directories scanned : %d\n' "$scanned"
printf 'PHP applications    : %d\n' "$eligible"
printf 'Compose changed     : %d\n' "$changed"
printf 'Registry created    : %d\n' "$registry_created"
if [[ "$MODE" == "apply" ]]; then
    printf 'Compose up success  : %d\n' "$compose_up_ok"
    printf 'Compose up failed   : %d\n' "$compose_up_failed"
fi
printf 'Skipped             : %d\n' "$skipped"
printf 'Failed              : %d\n' "$failed"
if [[ "$MODE" == "apply" ]]; then
    printf 'Backup directory    : %s\n' "$BACKUP_DIR"
    printf 'TXT report          : %s\n' "$REPORT_TXT"
    printf 'JSON report         : %s\n' "$REPORT_JSON"
else
    printf '\nTidak ada file yang diubah. Gunakan --apply untuk menerapkan.\n'
fi
printf '============================================================\n'

if [[ "$MODE" == "apply" ]]; then
    python3 - "$REPORT_JSON" "$SCRIPT_VERSION" "$TIMESTAMP" "$DOCKER_APPS_DIR" \
        "$scanned" "$eligible" "$changed" "$registry_created" "$compose_up_ok" \
        "$compose_up_failed" "$skipped" "$failed" "$BACKUP_DIR" \
        "$(printf '%s\n' "${VALIDATED_APPS[@]}")" \
        "$(printf '%s\n' "${APPS_TO_UP[@]}")" \
        "$(printf '%s\n' "${FAILED_APPS[@]}")" <<'PY'
import json, sys
(path, version, timestamp, root, scanned, eligible, changed, registry,
 up_ok, up_failed, skipped, failed, backup, validated, queued, failures) = sys.argv[1:]
def lines(value):
    return [x for x in value.splitlines() if x]
data = {
  "script": "migrate-php-app.sh",
  "version": version,
  "timestamp": timestamp,
  "directory": root,
  "mode": "apply",
  "summary": {
    "directories_scanned": int(scanned),
    "php_applications": int(eligible),
    "compose_changed": int(changed),
    "registry_created": int(registry),
    "compose_up_success": int(up_ok),
    "compose_up_failed": int(up_failed),
    "skipped": int(skipped),
    "failed": int(failed)
  },
  "validated_applications": lines(validated),
  "compose_up_attempted": lines(queued),
  "failures": lines(failures),
  "backup_directory": backup
}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
    chmod 0600 "$REPORT_TXT" "$REPORT_JSON"
fi

[[ "$failed" -eq 0 ]]
