# FCG — infraestrutura local

Esta composição inicia as quatro APIs, PostgreSQL e RabbitMQ com o nome de projeto `fcg-demo`. O PostgreSQL cria os quatro bancos e seus usuários. Users, Catalog e Payments preparam suas próprias tabelas antes de iniciar as operações. O Users disponibiliza a chave pública automaticamente para o Catalog, em um volume separado; a chave privada permanece exclusiva do Users.

## Imagens

As imagens estão publicadas no Docker Hub. As versões usadas pelo Compose ficam em [docker-compose/.env](docker-compose/.env):

| Serviço | Imagem |
|---|---|
| Users | `fgcprojetofiap/users-api:1.5` |
| Catalog | `fgcprojetofiap/catalog-api:1.0.3` |
| Payments | `fgcprojetofiap/payments-api:1.2` |
| Notifications | `fgcprojetofiap/notifications-api:1.0.7` |

Para a execução integrada no Kubernetes, siga a seção **Executar no Kubernetes** deste documento. O Secret SMTP e as chaves públicas são preparados pela configuração do conjunto.

No Docker Compose, preencha também `SMTP_USER`, `SMTP_PASSWORD` e `SMTP_FROM` no `docker-compose/.env` com os valores acordados pelo grupo antes de executar os comandos abaixo. O Secret Kubernetes não é lido automaticamente pelo Docker Compose.

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

## Executar no Kubernetes

Com o cluster local do Docker Desktop ativo e selecionado, execute na raiz deste repositório:

```powershell
kubectl apply -k ./k8s
kubectl -n fcg-demo rollout status deployment/usersapi --timeout=300s
kubectl -n fcg-demo port-forward service/usersapi 5089:8080
```

Acesse o Users em http://localhost:5089/swagger, mantendo o terminal do port-forward aberto. O conjunto atual inclui Users, Payments, PostgreSQL, RabbitMQ, ConfigMaps, Secret e volumes. Catalog e Notifications também estão incluídos. O Catalog obtém automaticamente as chaves públicas no Users por JWKS. Notifications depende do Secret SMTP descrito abaixo.

O [guia do Users no Kubernetes](k8s/users-api/README.md) explica os pré-requisitos, a inicialização automática e os testes. O [kustomization.yaml](k8s/kustomization.yaml) apenas reúne os manifestos já organizados por serviço e usa o Kustomize integrado ao kubectl. O deploy real precisa ser validado no cluster; a criação de todos os Pods não significa que todos já estejam prontos.

## Correção JWKS e SMTP no Kubernetes

O Kubernetes usa Users `1.5` e Catalog `1.0.3` nesta alteração. As imagens foram testadas e publicadas no Docker Hub em 27/10/2026 e podem ser baixadas em outras máquinas. O Compose também referencia essas versões e preserva o modo PEM anterior, que continua compatível.

O [guia do Catalog](k8s/catalog-api/README.md) explica a obtenção automática de chaves e o cache. A chave privada continua exclusiva do Users. O ConfigMap `catalog-jwt-public-key` não é necessário nesse modo.

### Credenciais Notifications

Por definição do grupo, as credenciais SMTP ficam no manifesto [notifications-api-secrets.yml](k8s/key-vault/notifications-api-secrets.yml), já incluído no Kustomize. Host, porta, remetente e TLS ficam no ConfigMap do Notifications. O Deployment lê `Smtp__User` e `Smtp__Password` desse Secret. Não é necessário criar um arquivo privado adicional nem executar um comando separado para provisioná-lo.

O Secret local já foi configurado e a autenticação TLS/SMTP foi aceita pelo provedor. Nenhum e-mail foi enviado na validação. O consumidor Notifications não foi iniciado nessa prova: ao iniciá-lo, ele poderá processar mensagens pendentes conforme a configuração do grupo.

A imagem Notifications foi atualizada para `fgcprojetofiap/notifications-api:1.0.7`, já disponível no Docker Hub. A versão foi conferida na API do Hub e testada em rede temporária isolada: HTTP 200 em `/health` e consumidores de UserCreatedEvent e PaymentProcessedEvent conectados. Nenhum evento foi publicado nem e-mail enviado nessa prova; os recursos temporários foram removidos. Users `1.5` e Catalog `1.0.3` também estão publicados no Hub. Os códigos das APIs ficam nos respectivos repositórios e os manifests deste Infra selecionam as versões da entrega.

Para executar em uma máquina nova, obtenha a versão atualizada do Infra, ative o Kubernetes no Docker Desktop e execute:

```powershell
kubectl config use-context docker-desktop
kubectl apply -k ./k8s
kubectl -n fcg-demo get pods,pvc
```

O Kustomize aplica os quatro microserviços, banco, broker, configurações e Secrets. O Catalog obtém automaticamente as chaves públicas do Users; o Secret SMTP é aplicado pelo mesmo comando. Aguarde os Deployments ficarem disponíveis antes dos testes funcionais.
