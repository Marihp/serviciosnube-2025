#!/bin/bash
# ======== DEBUG ROBUSTO ========
set -Eeuo pipefail
IFS=$'\n\t'
PS4='+ $(date "+%F %T") ${BASH_SOURCE}:${LINENO}: '
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1
trap 'rc=$?; echo "[ERROR] rc=$rc line=$LINENO cmd=${BASH_COMMAND}"; exit $rc' ERR
set -x

# ======== VARIABLES (fallback si no se templó) ========
PROJECT="${project:-${PROJECT:-servicios-nube}}"
ENVIRONMENT="${environment:-${ENVIRONMENT:-dev}}"
REGION="${region:-${AWS_DEFAULT_REGION:-}}"
SSM_PATH="/${PROJECT}/${ENVIRONMENT}"

# Detectar región por IMDS si sigue vacía
if [ -z "${REGION}" ]; then
  TOKEN="$(curl -fsS -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" || true)"
  IIDOC="$(curl -fsS -H "X-aws-ec2-metadata-token: ${TOKEN}" http://169.254.169.254/latest/dynamic/instance-identity/document || true)"
  REGION="$(echo "${IIDOC}" | jq -r '.region // empty')"
  REGION="${REGION:-us-east-1}"
fi
export AWS_DEFAULT_REGION="${REGION}"
echo "[INFO] PROJECT=${PROJECT} ENVIRONMENT=${ENVIRONMENT} REGION=${REGION}" >&2

# ======== PAQUETES (como los tienes) ========
dnf -y update || true
dnf -y install jq tar ca-certificates git awscli amazon-ssm-agent
sudo dnf -y install dnf-plugins-core
sudo dnf -y install dnf-plugins-core
dnf -y install docker

# Compose plugin
COMP_URL="https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64"
mkdir -p /usr/lib/docker/cli-plugins
curl -fsSL "$COMP_URL" -o /usr/lib/docker/cli-plugins/docker-compose
chmod +x /usr/lib/docker/cli-plugins/docker-compose

# >>> Buildx plugin (clave para compose build) <<<
VER="$(curl -fsSL https://api.github.com/repos/docker/buildx/releases/latest | jq -r '.tag_name' | sed 's/^v//')"
[ -z "$VER" ] && VER="0.17.0"
curl -fsSL \
  "https://github.com/docker/buildx/releases/download/v${VER}/buildx-v${VER}.linux-amd64" \
  -o /usr/lib/docker/cli-plugins/docker-buildx
chmod +x /usr/lib/docker/cli-plugins/docker-buildx

# Docker daemon y grupo
systemctl enable --now docker
usermod -aG docker ec2-user || true
install -m0644 <(echo '{"log-driver":"json-file","log-opts":{"max-size":"10m","max-file":"3"}}') /etc/docker/daemon.json
systemctl restart docker || true

# Builder por defecto para buildx
docker buildx version
docker buildx create --name defaultbuilder --driver docker-container --use 2>/dev/null || docker buildx use defaultbuilder
docker buildx inspect --bootstrap || true

# ======== RUTAS DE REPO/APP ========
BASE_DIR="/opt/app"
REPO_DIR="${BASE_DIR}/app"     # repo clonado (contiene app/ e infra/)
APP_DIR="${REPO_DIR}/app"      # carpeta de la app (docker-compose.yml vive aquí)

# ======== CLONADO/ACTUALIZACIÓN DEL REPO (PRIMERO) ========
REPO_URL="https://github.com/Marihp/serviciosnube-2025.git"
REPO_BRANCH="main"
mkdir -p "${BASE_DIR}"
cd "${BASE_DIR}"

if [ -d "${REPO_DIR}/.git" ]; then
  echo "[INFO] Repo ya existe; fetch+reset origin/${REPO_BRANCH}" >&2
  ( cd "${REPO_DIR}" && git fetch --all --prune && git reset --hard "origin/${REPO_BRANCH}" )
else
  if [ -d "${REPO_DIR}" ]; then
    echo "[WARN] '${REPO_DIR}' existe sin .git; eliminando y clonando limpio" >&2
    rm -rf "${REPO_DIR}"
  fi
  git clone --depth 1 -b "${REPO_BRANCH}" "${REPO_URL}" "${REPO_DIR}"
fi

# ======== HELPERS SSM ========
get_ssm() {
  local key="$1"
  local out
  if out=$(aws ssm get-parameter --with-decryption --name "$key" --region "${REGION}" --query 'Parameter.Value' --output text 2>/dev/null); then
    printf '%s' "$out"
  else
    echo "[WARN] SSM key not found: ${key}" >&2
    printf ''
  fi
}
get_ssm_first() {
  local val
  for key in "$@"; do
    val="$(get_ssm "$key")"
    if [ -n "$val" ] && [ "$val" != "None" ]; then
      echo "[INFO] SSM hit: ${key}" >&2
      printf '%s' "$val"
      return 0
    fi
  done
  printf ''
}

# ======== LEER SSM y normalizar DB_HOST ========
COMPANY_NAME="Nexa Cloud"

DB_HOST="$(get_ssm_first "${SSM_PATH}/db/host" "${SSM_PATH}/DB_HOST")"
DB_PORT="$(get_ssm_first "${SSM_PATH}/db/port" "${SSM_PATH}/DB_PORT")"
DB_DATABASE="$(get_ssm_first "${SSM_PATH}/db/name" "${SSM_PATH}/DB_DATABASE")"
DB_USER="$(get_ssm_first "${SSM_PATH}/db/user" "${SSM_PATH}/DB_USER")"
DB_PASSWORD="$(get_ssm_first "${SSM_PATH}/db/master_password" "${SSM_PATH}/DB_PASSWORD")"

AWS_S3_LAMBDA_URL="$(get_ssm_first "${SSM_PATH}/lambda/s3/url" "${SSM_PATH}/AWS_S3_LAMBDA_URL")"
AWS_DB_LAMBDA_URL="$(get_ssm_first "${SSM_PATH}/lambda/db/url" "${SSM_PATH}/AWS_DB_LAMBDA_URL")"
AWS_S3_LAMBDA_APIKEY="$(get_ssm_first "${SSM_PATH}/lambda/s3/apikey" "${SSM_PATH}/AWS_S3_LAMBDA_APIKEY")"
AWS_DB_LAMBDA_APIKEY="$(get_ssm_first "${SSM_PATH}/lambda/db/apikey" "${SSM_PATH}/AWS_DB_LAMBDA_APIKEY")"
STRESS_PATH="/api/performHighServerLoad"
LOAD_BALANCER_URL="$(get_ssm_first "${SSM_PATH}/alb/url" "${SSM_PATH}/LOAD_BALANCER_URL")"

if [[ "${DB_HOST}" == *:* ]]; then
  host_part="${DB_HOST%:*}"
  port_part="${DB_HOST##*:}"
  if [ -z "${DB_PORT}" ] && [[ "${port_part}" =~ ^[0-9]+$ ]]; then DB_PORT="${port_part}"; fi
  DB_HOST="${host_part}"
  echo "[INFO] Normalizado DB_HOST=${DB_HOST} DB_PORT=${DB_PORT}" >&2
fi

# ======== GENERAR .env en /opt/app/app/app/.env ========
umask 077
mkdir -p "${APP_DIR}"
cat > "${APP_DIR}/.env" <<EOF
COMPANY_NAME=${COMPANY_NAME}

DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
DB_DATABASE=${DB_DATABASE}

AWS_S3_LAMBDA_URL=${AWS_S3_LAMBDA_URL}
AWS_S3_LAMBDA_APIKEY=${AWS_S3_LAMBDA_APIKEY}

AWS_DB_LAMBDA_URL=${AWS_DB_LAMBDA_URL}
AWS_DB_LAMBDA_APIKEY=${AWS_DB_LAMBDA_APIKEY}

STRESS_PATH=${STRESS_PATH}
LOAD_BALANCER_URL=${LOAD_BALANCER_URL}
EOF
chmod 600 "${APP_DIR}/.env" || true
echo "[INFO] .env escrito en ${APP_DIR}/.env" >&2
ls -l "${APP_DIR}/.env" || true

# ======== ARRANQUE: forzar compose con buildx y .env ========
cd "${APP_DIR}"
if ! docker compose -f docker-compose.yml --env-file .env build; then
  echo "[ERROR] docker compose build falló" >&2
fi
if ! docker compose -f docker-compose.yml --env-file .env up -d; then
  echo "[ERROR] docker compose up falló; mostrando contenedores" >&2
  docker ps -a || true
fi
docker compose -f docker-compose.yml --env-file .env ps || true

# ======== AMAZON SSM AGENT ========
sudo dnf install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
sudo systemctl enable amazon-ssm-agent
sudo systemctl start amazon-ssm-agent

echo "[INFO] user-data COMPLETADO" >&2
