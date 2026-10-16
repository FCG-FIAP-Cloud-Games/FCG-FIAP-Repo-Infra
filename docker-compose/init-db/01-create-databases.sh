#!/bin/bash
# Executado pelo entrypoint do Postgres apenas na PRIMEIRA criação do volume.
# As variáveis *_DB_* vêm do serviço "postgres" no docker-compose (originadas do .env).
set -e

create_db() {
  local db="$1" user="$2" pass="$3"
  psql -v ON_ERROR_STOP=1 \
       -v db="$db" -v user="$user" -v pass="$pass" \
       --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-'EOSQL'
    CREATE USER :"user" WITH PASSWORD :'pass';
    CREATE DATABASE :"db" OWNER :"user";
EOSQL
}

create_db "${USERS_DB_NAME:?}"         "${USERS_DB_USER:?}"         "${USERS_DB_PASSWORD:?}"
create_db "${CATALOG_DB_NAME:?}"       "${CATALOG_DB_USER:?}"       "${CATALOG_DB_PASSWORD:?}"
create_db "${PAYMENTS_DB_NAME:?}"      "${PAYMENTS_DB_USER:?}"      "${PAYMENTS_DB_PASSWORD:?}"
create_db "${NOTIFICATIONS_DB_NAME:?}" "${NOTIFICATIONS_DB_USER:?}" "${NOTIFICATIONS_DB_PASSWORD:?}"
