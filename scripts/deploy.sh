#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"                      # псевдоним из ~/.ssh/config (ПР № 5, шаг 1.6)
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
ROOT="$(git rev-parse --show-toplevel)"
LOCAL_DIR="${ROOT}/site/"

err() { echo "ОШИБКА: $*" >&2; exit 1; }

# 1. Разбор аргумента --dry-run
DRY_RUN=0
case "${1:-}" in
    "")        ;;
    --dry-run) DRY_RUN=1 ;;
    *)         err "неизвестный аргумент '$1'. Использование: $0 [--dry-run]" ;;
esac

# rsync из macOS (openrsync) не поддерживает --chmod=D755,F644
RSYNC_VERSION="$(rsync --version 2>&1 || true)"
[[ "$RSYNC_VERSION" == *openrsync* ]] && err "найден openrsync из macOS, установите GNU rsync: brew install rsync"

# 2. Проверки по требованиям 4 и 5
[[ -f "${LOCAL_DIR}index.html" ]] || err "файл site/index.html не найден, доставка отменена"

# изменения в отслеживаемых файлах (включая индекс) и новые файлы в site/, ещё не добавленные в git
CHANGES="$(git -C "$ROOT" status --porcelain --untracked-files=no)"
UNTRACKED="$(git -C "$ROOT" ls-files --others --exclude-standard -- site ':!:**/.DS_Store')"
if [[ -n "$CHANGES" || -n "$UNTRACKED" ]]; then
    err "в репозитории есть незафиксированные изменения, выполните commit:
${CHANGES}${UNTRACKED:+
${UNTRACKED}}"
fi

COMMIT="$(git -C "$ROOT" rev-parse --short HEAD)"

# 3. Синхронизация каталога (одно SSH-соединение, без запроса пароля)
RSYNC_OPTS=(-avz --delete --chmod=D755,F644 --exclude='.DS_Store'
            -e "ssh -o BatchMode=yes -o ConnectTimeout=5")
(( DRY_RUN )) && RSYNC_OPTS+=(--dry-run)

rsync "${RSYNC_OPTS[@]}" "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}/" \
    || err "rsync завершился с ошибкой"

# 4. При --dry-run — завершение без проверки доступности
if (( DRY_RUN )); then
    echo "Пробный запуск: изменения не применены (коммит ${COMMIT})"
    exit 0
fi

# 5. Проверка доступности с проверкой сертификата
curl -fsS --max-time 10 --cacert "${CA_CERT}" -o /dev/null "${SITE_URL}" \
    || err "ресурс ${SITE_URL} недоступен после доставки"

echo "Деплой выполнен: коммит ${COMMIT}"
exit 0
