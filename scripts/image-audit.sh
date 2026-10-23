#!/usr/bin/env bash
set -Eeuo pipefail

# Audit running Docker containers and compare PHP versions with the latest
# patch version listed on the official PHP downloads page. Older local/php
# containers can be updated after explicit confirmation.
# For PHP2Shell, this also identifies versions below the currently fixed release.
# If older local/php containers are found, ask for confirmation before:
#   1) pulling the PHP base image from its Dockerfile,
#   2) rebuilding via the existing build-image.sh, and
#   3) recreating Compose-managed services using the refreshed local/php image.
# This script never stops/recreates a container without explicit confirmation.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUILD_SCRIPT="${SCRIPT_DIR}/build-image.sh"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
info(){ printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
ok(){ printf "${GREEN}[ OK ]${NC} %s\n" "$*"; }
warn(){ printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err(){ printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }
section(){ printf "\n${CYAN}============================================================${NC}\n${CYAN}%s${NC}\n${CYAN}============================================================${NC}\n" "$*"; }
die(){ err "$*"; exit 1; }

command -v docker >/dev/null 2>&1 || die "Docker tidak ditemukan."
command -v curl >/dev/null 2>&1 || die "curl diperlukan untuk mengambil rekomendasi versi PHP resmi."
docker info >/dev/null 2>&1 || die "Docker daemon tidak dapat diakses. Jalankan dengan user yang memiliki akses Docker."
[[ -x "$BUILD_SCRIPT" ]] || die "build-image.sh tidak ditemukan atau tidak executable di: $BUILD_SCRIPT"

# Ambil versi patch terbaru yang dipublikasikan di halaman resmi PHP.
# Tidak ada nomor patch yang di-hardcode. Jika sumber resmi tidak dapat
# diakses atau branch tidak ditemukan, script gagal tertutup (manual review).
PHP_DOWNLOADS_PAGE=''
declare -A RECOMMENDED_CACHE=()
recommended_version(){
  local minor="$1" escaped_minor version
  if [[ -n "${RECOMMENDED_CACHE[$minor]:-}" ]]; then
    printf '%s' "${RECOMMENDED_CACHE[$minor]}"
    return 0
  fi

  if [[ -z "$PHP_DOWNLOADS_PAGE" ]]; then
    PHP_DOWNLOADS_PAGE="$(curl --connect-timeout 10 --max-time 30 -fsSL 'https://www.php.net/downloads.php?source=Y')" || return 1
  fi

  escaped_minor="${minor//./\.}"
  version="$(printf '%s\n' "$PHP_DOWNLOADS_PAGE" \
    | grep -oE "${escaped_minor}\.[0-9]+" \
    | sort -Vu \
    | tail -n 1)"
  [[ -n "$version" ]] || return 1
  RECOMMENDED_CACHE[$minor]="$version"
  printf '%s' "$version"
}
version_lt(){
  local a="$1" b="$2" first
  [[ "$a" != "$b" ]] || return 1
  first="$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -n1)"
  [[ "$first" == "$a" ]]
}

# Per-container inventory stored in parallel arrays.
IDS=() NAMES=() IMAGES=() PHPVERS=() STATES=() MINORS=() BASES=() COMPOSE_WDS=() COMPOSE_FILES=() COMPOSE_SERVICES=()
ACTIONABLE_VERSIONS=()

section "AUDIT CONTAINER DOCKER AKTIF"
mapfile -t running_ids < <(docker ps --quiet)
if [[ ${#running_ids[@]} -eq 0 ]]; then
  info "Tidak ada container yang sedang berjalan."
  exit 0
fi

printf '%-24s %-30s %-22s %-12s %-24s\n' 'CONTAINER' 'IMAGE' 'VERSI PHP' 'STATUS' 'TINDAKAN'
printf '%-24s %-30s %-22s %-12s %-24s\n' '------------------------' '------------------------------' '----------------------' '------------' '------------------------'

for id in "${running_ids[@]}"; do
  name="$(docker inspect --format '{{.Name}}' "$id" | sed 's#^/##')"
  image="$(docker inspect --format '{{.Config.Image}}' "$id")"
  state="$(docker inspect --format '{{.State.Status}}' "$id")"
  phpver="$(docker exec "$id" php -r 'echo PHP_VERSION;' 2>/dev/null || true)"
  wd="$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' "$id" 2>/dev/null || true)"
  files="$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.project.config_files" }}' "$id" 2>/dev/null || true)"
  service="$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.service" }}' "$id" 2>/dev/null || true)"
  minor=''; base=''; action='NON-PHP / SKIP'

  if [[ -n "$phpver" ]]; then
    minor="$(printf '%s' "$phpver" | awk -F. '{print $1"."$2}')"
    if recommended="$(recommended_version "$minor" 2>/dev/null)"; then
      if version_lt "$phpver" "$recommended"; then
        action="VERSI LAMA (<${recommended})"
        if [[ "$image" == "local/php:${minor}" ]]; then
          dockerfile="${ROOT_DIR}/images/${minor}/Dockerfile"
          if [[ -f "$dockerfile" ]]; then
            base="$(awk '$1=="FROM" {print $2; exit}' "$dockerfile")"
            if [[ -n "$base" && "$wd" != '<no value>' && -n "$wd" && "$files" != '<no value>' && -n "$files" && "$service" != '<no value>' && -n "$service" ]]; then
              action="UPDATE TERSEDIA (<${recommended})"
              ACTIONABLE_VERSIONS+=("$minor")
            else
              action="VERSI LAMA / MANUAL (<${recommended})"
            fi
          else
            action='VERSI LAMA / DOCKERFILE?'
          fi
        else
          action='VERSI LAMA / IMAGE EKSTERNAL'
        fi
      else
        action="SESUAI REKOMENDASI (${recommended})"
      fi
    else
      action='REKOMENDASI TAK TERSEDIA / MANUAL'
    fi
  fi

  printf '%-24s %-30s %-22s %-12s %-24s\n' "${name:0:24}" "${image:0:30}" "${phpver:-tidak terdeteksi}" "$state" "$action"
  IDS+=("$id"); NAMES+=("$name"); IMAGES+=("$image"); PHPVERS+=("$phpver"); STATES+=("$action"); MINORS+=("$minor"); BASES+=("$base"); COMPOSE_WDS+=("$wd"); COMPOSE_FILES+=("$files"); COMPOSE_SERVICES+=("$service")
done

# Deduplicate actionable PHP branches.
if [[ ${#ACTIONABLE_VERSIONS[@]} -gt 0 ]]; then
  mapfile -t ACTIONABLE_VERSIONS < <(printf '%s\n' "${ACTIONABLE_VERSIONS[@]}" | awk 'NF && !seen[$0]++')
fi

section "RINGKASAN"
if [[ ${#ACTIONABLE_VERSIONS[@]} -eq 0 ]]; then
  info "Tidak ada container local/php yang terdeteksi lebih tua dari rekomendasi resmi dan bisa diperbarui otomatis."
  warn "Container tanpa rekomendasi versi resmi, image eksternal, atau yang tidak dikelola Docker Compose memerlukan penanganan manual."
  exit 0
fi
printf 'Versi local/php yang akan dibangun ulang: %s\n' "${ACTIONABLE_VERSIONS[*]}"
cat <<'NOTICE'

Perubahan yang akan dilakukan setelah konfirmasi:
- Pull image dasar PHP sesuai FROM di images/<versi>/Dockerfile.
- Build ulang local/php:<versi> melalui build-image.sh dengan --no-cache.
- Verifikasi versi PHP hasil build terhadap versi rekomendasi terbaru dari php.net.
- Recreate service Docker Compose yang terdeteksi memakai image tersebut.

Container non-Compose, image eksternal, dan branch PHP yang tidak memiliki versi rekomendasi resmi tidak akan diubah otomatis.
NOTICE

read -r -p "Lanjutkan proses update dan recreate service yang terdeteksi? Ketik UPDATE untuk melanjutkan: " answer
[[ "$answer" == 'UPDATE' ]] || { info "Dibatalkan. Tidak ada image atau container yang diubah."; exit 0; }

# Pull base images and build each vulnerable local/php branch once.
for minor in "${ACTIONABLE_VERSIONS[@]}"; do
  dockerfile="${ROOT_DIR}/images/${minor}/Dockerfile"
  base="$(awk '$1=="FROM" {print $2; exit}' "$dockerfile")"
  [[ -n "$base" ]] || { err "Tidak dapat membaca FROM dari $dockerfile"; continue; }
  section "UPDATE IMAGE PHP ${minor}"
  info "Image dasar: $base"
  if ! docker pull "$base"; then
    err "Pull image dasar gagal untuk PHP ${minor}; lewati build versi ini."
    continue
  fi
  if ! (cd "$SCRIPT_DIR" && "$BUILD_SCRIPT" "$minor" --no-cache); then
    err "Build image local/php:${minor} gagal; service tidak akan direcreate untuk versi ini."
    continue
  fi
  built_php="$(docker run --rm --entrypoint php "local/php:${minor}" -r 'echo PHP_VERSION;' 2>/dev/null || true)"
  required="$(recommended_version "$minor" 2>/dev/null || true)"
  if [[ -z "$required" ]]; then
    err "Tidak dapat mengambil versi rekomendasi resmi untuk PHP ${minor}. Tidak melakukan recreate untuk cabang ini."
    continue
  fi
  if [[ -z "$built_php" ]] || version_lt "$built_php" "$required"; then
    err "Hasil build PHP ${built_php:-tidak diketahui} belum memenuhi versi rekomendasi ${required}. Tidak melakukan recreate untuk cabang ini."
    continue
  fi
  ok "Image local/php:${minor} terverifikasi menggunakan PHP ${built_php} (rekomendasi resmi: ${required})."

  # Recreate only outdated Compose services marked UPDATE TERSEDIA during the initial audit.
  for i in "${!IDS[@]}"; do
    [[ "${MINORS[$i]}" == "$minor" ]] || continue
    # Match the status assigned during the audit phase.
    # Outdated eligible containers are marked "UPDATE TERSEDIA (<recommended>)".
    [[ "${STATES[$i]}" == UPDATE\ TERSEDIA\ \(* ]] || continue
    wd="${COMPOSE_WDS[$i]}"; files="${COMPOSE_FILES[$i]}"; service="${COMPOSE_SERVICES[$i]}"
    [[ -n "$wd" && "$wd" != '<no value>' && -n "$files" && "$files" != '<no value>' && -n "$service" && "$service" != '<no value>' ]] || { warn "Label Compose hilang untuk ${NAMES[$i]}; tidak direcreate otomatis."; continue; }

    # Compose stores its config file list as comma-separated paths.
    IFS=',' read -r -a compose_file_list <<< "$files"
    compose_args=()
    valid_files=true
    for cf in "${compose_file_list[@]}"; do
      [[ "$cf" = /* ]] || cf="${wd}/${cf}"
      if [[ -f "$cf" ]]; then compose_args+=( -f "$cf" ); else err "File Compose tidak ditemukan: $cf"; valid_files=false; fi
    done
    if [[ "$valid_files" != true || ${#compose_args[@]} -eq 0 ]]; then
      warn "Tidak dapat menyusun konfigurasi Compose untuk ${NAMES[$i]}; perlu recreate manual."
      continue
    fi
    section "RECREATE SERVICE ${service} (${NAMES[$i]})"
    if (cd "$wd" && docker compose "${compose_args[@]}" up -d --no-deps --force-recreate "$service"); then
      ok "Permintaan recreate berhasil untuk service ${service}."
    else
      err "Recreate gagal untuk service ${service}; periksa Compose dan log aplikasi."
    fi
  done
done

section "VALIDASI AKHIR"
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
warn "Periksa health check dan log aplikasi setelah pembaruan. Script tidak dapat memastikan aplikasi berfungsi hanya dari status container."
warn "Branch PHP yang tidak tercantum pada halaman rekomendasi resmi php.net dan image non-local/php memerlukan penanganan manual."
