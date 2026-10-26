#!/bin/bash
# O Postgres executa este arquivo na primeira criacao do volume.
# Tambem pode ser executado uma vez para acrescentar bancos em volume antigo.
# Nao altera senhas, proprietarios, tabelas ou registros ja existentes.
set -euo pipefail

create_db() {
  local db="$1" user="$2" pass="$3"
  psql -v ON_ERROR_STOP=1 \
       -v db="$db" -v user="$user" -v pass="$pass" \
       --username "${POSTGRES_USER:-postgres}" --dbname "${POSTGRES_DB:-postgres}" <<-'EOSQL'
    SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'user', :'pass')
      WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'user')
    \gexec
    SELECT format('CREATE DATABASE %I OWNER %I', :'db', :'user')
      WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = :'db')
    \gexec
EOSQL
  printf 'FCG: banco %s disponivel; migrations pertencem a API.\n' "$db"
}

create_db "${USERS_DB_NAME:?}"         "${USERS_DB_USER:?}"         "${USERS_DB_PASSWORD:?}"
create_db "${CATALOG_DB_NAME:?}"       "${CATALOG_DB_USER:?}"       "${CATALOG_DB_PASSWORD:?}"
create_db "${PAYMENTS_DB_NAME:?}"      "${PAYMENTS_DB_USER:?}"      "${PAYMENTS_DB_PASSWORD:?}"
create_db "${NOTIFICATIONS_DB_NAME:?}" "${NOTIFICATIONS_DB_USER:?}" "${NOTIFICATIONS_DB_PASSWORD:?}"
