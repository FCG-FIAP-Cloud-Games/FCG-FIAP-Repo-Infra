# FCG — infraestrutura local

Esta composição inicia as quatro APIs, PostgreSQL e RabbitMQ com o nome de projeto `fcg-demo`. O PostgreSQL cria os quatro bancos e seus usuários. Users, Catalog e Payments preparam suas próprias tabelas antes de iniciar as operações. O Users disponibiliza a chave pública automaticamente para o Catalog, em um volume separado; a chave privada permanece exclusiva do Users.

## Imagens

As imagens estão publicadas no Docker Hub. As versões usadas pelo Compose ficam em [docker-compose/.env](docker-compose/.env):

| Serviço | Imagem |
|---|---|
| Users | `fgcprojetofiap/users-api:1.4` |
| Catalog | `fgcprojetofiap/catalog-api:1.0.2` |
| Payments | `fgcprojetofiap/payments-api:1.2` |
| Notifications | `fgcprojetofiap/notifications-api:1.0.3` |

## Executar

Com Docker Desktop aberto e usando containers Linux, abra um terminal na raiz deste repositório:

```powershell
cd docker-compose
docker compose up -d
docker compose ps -a
```

O Docker baixa as imagens do Hub e inicia os serviços. Não é necessário clonar ou compilar os repositórios das APIs.

Na primeira inicialização com volume vazio, os bancos, tabelas, chaves e administrador de demonstração são preparados automaticamente. Não é necessário executar scripts manualmente, copiar uma chave PEM ou iniciar um serviço preparador.

## Acessos

| Serviço | Endereço |
|---|---|
| Users | http://localhost:5088/swagger |
| Catalog | http://localhost:5081/swagger |
| Payments | http://localhost:5082/swagger |
| Notifications | http://localhost:5083/swagger |
| RabbitMQ | http://localhost:15672 |

Administrador sintético do Users: `admin@fcg.local` / `Admin_Demo_2026!`.

As credenciais dos quatro bancos e do RabbitMQ estão no `.env` de demonstração. Elas são destinadas ao ambiente local.

## O que acontece na inicialização

1. O entrypoint oficial do PostgreSQL executa [01-create-databases.sh](docker-compose/init-db/01-create-databases.sh) quando o volume de dados está vazio. O script cria os quatro bancos e usuários ausentes; não altera senhas, proprietários, tabelas nem registros existentes. O healthcheck usa TCP para aguardar o servidor definitivo depois desse provisionamento.
2. Users executa sua preparação interna: migrations, chaves RSA e primeiro administrador. `Jwt__PublicKeyExport__Path=/data/jwt-publica/public.pem` ativa a exportação somente da chave pública no modo local. A privada continua em `/data/jwt/private.pem`, em volume exclusivo.
3. Catalog e Payments usam `DemonstracaoLocal__Habilitada=true` em `Development` para aplicar suas migrations antes de iniciar HTTP e consumidores. O histórico do Entity Framework e um lock de sessão do PostgreSQL permitem reiniciar sem recriar tabelas nem registros.
4. Catalog aguarda o Users ficar saudável e monta `jwt-publica` somente para leitura. Recebe o caminho do arquivo em `Jwt__PublicKeys__0__PublicKeyPath`. A validação do token continua local: o Catalog não chama o Users a cada operação.

O servidor PostgreSQL é compartilhado no ambiente de demonstração, mas cada API tem seu banco e usuário. Notifications possui seu banco provisionado; no fluxo de envio observado na imagem `1.0.3`, o envio é simulado no console.

O [Compose](docker-compose/docker-compose.yml) não contém SQL de tabelas, PEM ou scripts embutidos. O script de provisionamento de bancos em `init-db/` já fazia parte deste repositório.

## Conferir, parar e reiniciar

Na pasta `docker-compose`:

```powershell
docker compose logs --tail 80 usersapi catalogapi paymentsapi notificationsapi
docker compose down
docker compose up -d
```

`down` sem `-v` mantém bancos, mensagens e chaves. Reiniciar os containers não exige repetir o provisionamento nem gerar novas chaves.

## Atualizar as imagens publicadas

Depois de receber as novas tags no `.env`:

```powershell
docker compose pull
docker compose up -d
docker compose ps -a
```

Os volumes mantêm seus dados. O PostgreSQL não executa `init-db` novamente em um volume existente. Caso novos bancos sejam acrescentados no futuro, o provisionamento pode ser repetido uma vez:

```powershell
docker compose exec -T postgres bash /docker-entrypoint-initdb.d/01-create-databases.sh
```

Esse comando não faz parte da primeira execução nem dos reinícios normais. Alterações de tabelas pertencem às migrations de cada API.
