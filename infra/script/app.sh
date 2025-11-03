#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

# Paquetes
dnf -y update
dnf -y install git aws-cli jq git
yum -y install docker docker-compose-plugin
systemctl enable --now docker || true
usermod -aG docker ec2-user || true

# === Parámetros ===
PROJECT="${PROJECT:-servicios-nube}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
SSM_PATH="/${PROJECT}/${ENVIRONMENT}"

# Lee SSM (no sensibles)
get_ssm () { aws ssm get-parameter --with-decryption --name "$1" --query 'Parameter.Value' --output text; }

COMPANY_NAME="$(get_ssm "${SSM_PATH}/COMPANY_NAME")"
DB_HOST="$(get_ssm "${SSM_PATH}/DB_HOST")"
DB_DATABASE="$(get_ssm "${SSM_PATH}/DB_DATABASE")"
AWS_S3_LAMBDA_URL="$(get_ssm "${SSM_PATH}/AWS_S3_LAMBDA_URL")"
AWS_DB_LAMBDA_URL="$(get_ssm "${SSM_PATH}/AWS_DB_LAMBDA_URL")"
STRESS_PATH="$(get_ssm "${SSM_PATH}/STRESS_PATH")"
LOAD_BALANCER_URL="$(get_ssm "${SSM_PATH}/LOAD_BALANCER_URL")"

# Lee Secrets (JSON) -> DB_USER, DB_PASSWORD, APIKEYs
APP_SECRET_ARN="$(aws secretsmanager list-secrets --query "SecretList[?Name=='${PROJECT}/${ENVIRONMENT}/app'].ARN|[0]" --output text)"
APP_JSON="$(aws secretsmanager get-secret-value --secret-id "$APP_SECRET_ARN" --query SecretString --output text)"
DB_USER="$(echo "$APP_JSON" | jq -r '.DB_USER')"
DB_PASSWORD="$(echo "$APP_JSON" | jq -r '.DB_PASSWORD')"
AWS_S3_LAMBDA_APIKEY="$(echo "$APP_JSON" | jq -r '.AWS_S3_LAMBDA_APIKEY')"
AWS_DB_LAMBDA_APIKEY="$(echo "$APP_JSON" | jq -r '.AWS_DB_LAMBDA_APIKEY')"

# Escribe .env para tu app (directorio donde corre compose)
APP_DIR="/opt/app/app"        
mkdir -p "$APP_DIR"
cat > "${APP_DIR}/.env" <<EOF
COMPANY_NAME=${COMPANY_NAME}

DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
DB_HOST=${DB_HOST}
DB_DATABASE=${DB_DATABASE}

AWS_S3_LAMBDA_URL=${AWS_S3_LAMBDA_URL}
AWS_S3_LAMBDA_APIKEY=${AWS_S3_LAMBDA_APIKEY}

AWS_DB_LAMBDA_URL=${AWS_DB_LAMBDA_URL}
AWS_DB_LAMBDA_APIKEY=${AWS_DB_LAMBDA_APIKEY}

STRESS_PATH=${STRESS_PATH}
LOAD_BALANCER_URL=${LOAD_BALANCER_URL}
EOF


REPO_URL="https://github.com/Marihp/serviciosnube-2025.git"
REPO_BRANCH="main"
mkdir -p /opt/app && cd /opt/app
git clone --depth 1 -b "${REPO_BRANCH}" "${REPO_URL}" app || (cd app && git fetch && git reset --hard "origin/${REPO_BRANCH}")

# Arranca compose
cd "$APP_DIR"
docker compose up -d --build
