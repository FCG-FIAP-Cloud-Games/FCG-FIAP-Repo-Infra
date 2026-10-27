# UsersAPI no Kubernetes

A configuração segue o padrão do Payments publicado em `feature/payments`, atualizado no commit `7957d7d` e com as alterações da `main` até `1e93514`. Users e Payments usam o mesmo namespace, ConfigMap, Secret, servidor PostgreSQL, RabbitMQ e forma de aplicação dos manifestos.

A imagem do Users continua `fgcprojetofiap/users-api:1.4`. Não é necessário compilar a aplicação, publicar outra imagem ou executar migrations manualmente.

## Executar

O roteiro parte de uma instalação local nova, com Docker Desktop aberto e Kubernetes ativado. Na raiz do repositório Infra, confira o cluster e o armazenamento:

```powershell
kubectl config use-context docker-desktop
kubectl get nodes
kubectl get storageclass
```

Prossiga quando o nó estiver `Ready` e existir um StorageClass padrão para os volumes. Aplique o conjunto:

```powershell
kubectl apply -k ./k8s
kubectl -n fcg-demo rollout status deployment/usersapi --timeout=300s
kubectl -n fcg-demo port-forward service/usersapi 5089:8080
```

Mantenha o terminal do port-forward aberto. Acesse:

- Swagger: http://localhost:5089/swagger
- Health: http://localhost:5089/health
- Administrador sintético: `admin@fcg.local` / `Admin_Demo_2026!`.

No Postman, use `http://localhost:5089` como `baseUrl` na collection do Users, ou `usersUrl` na collection de integração. A porta 5089 evita ocupar a 5088 que pode estar sendo usada pelo Compose. Dentro do cluster, a API continua na porta 8080.

O arquivo [kustomization.yaml](../kustomization.yaml) reúne os manifestos de **Users, Payments, PostgreSQL, RabbitMQ e configurações compartilhadas**. O recurso já vem integrado ao `kubectl`; não acrescenta instalação de ferramenta ou serviço preparador. Catalog e Notifications ficam fora desse conjunto enquanto seus manifestos deste branch não estiverem preparados. A criação dos Pods acontece em paralelo; o comando de rollout aguarda a prontidão do Users. Se a primeira tentativa da API ocorrer antes de o banco estar disponível, o Kubernetes tentará reiniciar o container.

Para conferir todos os serviços incluídos:

```powershell
kubectl -n fcg-demo get pods,pvc,svc
kubectl -n fcg-demo rollout status deployment/paymentsapi --timeout=300s
```

Se alguma etapa falhar, use o diagnóstico ao final antes de continuar. Este guia descreve o procedimento; o resultado de uma execução Kubernetes real depende do teste no cluster.

## O que acontece automaticamente

1. O Kubernetes obtém as imagens publicadas e entrega as variáveis aos containers.
2. O PostgreSQL usa o ConfigMap [postgres-init-script.yml](../key-vault/postgres-init-script.yml), já publicado pelo grupo, para criar os quatro bancos e seus usuários quando o volume está vazio. A fonte do Bash fica em [01-create-databases.sh](../init-db/01-create-databases.sh).
3. A própria imagem do Users prepara/reutiliza chaves RSA, aplica migrations e cria o primeiro administrador quando necessário.
4. A API abre HTTP. As probes verificam `/health`, e o Service disponibiliza o endereço interno `http://usersapi:8080`.
5. O cadastro grava usuário e evento na Outbox na mesma transação. O publicador entrega o `UserCreatedEvent` ao RabbitMQ; a inicialização do administrador também gera esse evento quando ele é criado pela primeira vez.

O script de criação dos bancos não é executado novamente em volume já inicializado. Nomes de banco e senhas precisam corresponder ao que já existe nesse volume; mudar um Secret não troca a senha dentro do PostgreSQL. As tabelas continuam sendo responsabilidade das migrations de cada API.

## O que é igual ao Payments

| Ponto | Padrão compartilhado |
|---|---|
| Organização | Um arquivo de Deployment e Service por API, com uma réplica e Service ClusterIP. |
| Configuração | `envFrom` importa `fcg-config`; as credenciais são obtidas por referências explícitas a `fcg-secrets`. |
| Banco | Nome, usuário e senha são definidos antes da connection string. Cada API usa seu banco. |
| Porta | HTTP 8080, com porta nomeada `http`. |
| Saúde | Startup, readiness e liveness probes. |
| Recursos | Requests de `100m` de CPU e `128Mi`; limits de `500m` e `512Mi`. |
| Execução | As imagens publicadas fazem a preparação interna; o Kubernetes gerencia os containers. |
| Aplicação | O mesmo comando `kubectl apply -k ./k8s` aplica os serviços configurados. |

O manifesto Users mantém a mesma disposição de campos e variáveis do Payments. O RabbitMQ e o ConfigMap de criação dos bancos são os publicados pelo grupo, sem uma segunda definição local desses recursos.

## Diferenças necessárias do Users

**Banco de demonstração.** A preparação automática da imagem `1.4` exige Host `postgres`, Database `fcg_users_demo`, ambiente Development e `DemonstracaoLocal__Habilitada=true`. O ConfigMap compartilhado usa `USERS_DB_NAME: "fcg_users_demo"`, conforme a decisão do grupo nesta preparação. O usuário continua `users_user`. Esse ajuste não renomeia um banco existente.

**Endereço do RabbitMQ.** O Users recebe `rabbitmq`, enquanto o Payments usa `rabbitmq://rabbitmq`. Os parsers das aplicações aceitam formatos diferentes; ambos apontam para o mesmo Service.

**Probes.** O Users usa HTTP em `/health`, com startup de aproximadamente 180 segundos para concluir chaves, migrations e administrador. Readiness e liveness têm os mesmos intervalos do Payments. O `/health` confirma resposta da API e não valida banco ou RabbitMQ; cadastro, login e publicação precisam ser testados funcionalmente.

**Chaves JWT.** O PVC `users-jwt-pvc` é montado no diretório pai `/data`. O processo usa UID/GID `1654`, com `fsGroup: 1654`, para criar os subdiretórios com as permissões apropriadas:

```text
/data/jwt/private.pem         assinatura dos tokens
/data/jwt/public.pem          validação no próprio Users
/data/jwt-publica/public.pem  cópia somente da chave pública para integração
```

O tipo de armazenamento precisa suportar as permissões do volume. O entrypoint original da imagem permanece ativo. Não há initContainer nem serviço preparador adicional.

**Atualização do Pod.** A estratégia `Recreate` mantém uma única instância acessando o volume `ReadWriteOnce`, preservando chaves entre recriações. Uma atualização pode causar um breve intervalo sem API. A integração futura do Catalog deve distribuir somente a chave pública; a raiz desse volume contém a chave privada e não deve ser compartilhada com ele.

## Recursos compartilhados

O RabbitMQ segue integralmente a versão atual do colega, com credenciais do Secret, probes e limites de recursos. O ConfigMap de inicialização do PostgreSQL fica em `key-vault`, seguindo a organização publicada pelo grupo. A antiga cópia local em `postgres/postgres-init-configmap.yml` foi retirada para evitar dois recursos com o mesmo nome.

O [Deployment PostgreSQL](../postgres/postgres-deployment.yml) mantém dois pequenos ajustes locais que atendem a todas as APIs: probes por TCP, para aguardar o servidor definitivo após criar os bancos, e `Recreate`, para evitar dois Pods usando o mesmo diretório de dados durante uma atualização.

## Conferir o evento

Em outro terminal:

```powershell
kubectl -n fcg-demo port-forward service/rabbitmq 15673:15672
```

Abra http://localhost:15673 com os valores `RABBITMQ_USER` e `RABBITMQ_PASSWORD` do Secret compartilhado. Crie um usuário pelo Swagger/Postman e confira a fila `notifications-user-created`.

Sem consumidor Notifications ativo, o evento deve permanecer em `Ready`. A presença na fila comprova publicação, não envio de e-mail. Com consumidor ativo, confirme o processamento pelos logs dele.

## Conferir persistência e recuperação

Depois de cadastrar um usuário e confirmar o login, recrie o Pod:

```powershell
kubectl -n fcg-demo delete pod -l app=usersapi
kubectl -n fcg-demo rollout status deployment/usersapi --timeout=300s
```

Reabra o port-forward se ele encerrar e confirme que o usuário continua conseguindo entrar. O Deployment recria o Pod; PostgreSQL e PVC de chaves conservam os dados.

## Diagnóstico

```powershell
kubectl -n fcg-demo get pods,pvc
kubectl -n fcg-demo get events --sort-by=.metadata.creationTimestamp
kubectl -n fcg-demo describe pods -l app=usersapi
kubectl -n fcg-demo logs deployment/postgres --tail=80
kubectl -n fcg-demo logs deployment/rabbitmq --tail=80
kubectl -n fcg-demo logs deployment/usersapi --tail=80
```

Os recursos de CPU e memória seguem o Payments e precisam ser conferidos no cluster. Um encerramento por `OOMKilled` indica que o limite de memória foi excedido. PVC em `Pending` exige conferir o StorageClass e os eventos de provisionamento.

## Validação

A preparação anterior aprovou 40 verificações isoladas em Docker: bancos/usuários, health, Swagger, login, cadastro, eventos na Outbox/RabbitMQ e persistência após recriar o Users. O teste não incluiu consumidor Notifications nem envio de e-mail.

Na atualização de 27/10/2026, o `kubectl kustomize` montou os 14 recursos do conjunto, validados contra o schema oficial do Kubernetes. Uma nova prova isolada em Docker aprovou **45 verificações**, com as variáveis dos manifestos atuais, limite de meio núcleo e 512 MiB aplicado a Users e RabbitMQ. Foram conferidos cadastro, login, Outbox, payload dos eventos na fila, migrations e persistência de chaves/dados após recriar o Users. Não houve encerramento do Users por OOM no teste. Os recursos temporários foram removidos, preservando os containers existentes.

Essa prova executou Users, PostgreSQL e RabbitMQ; o Payments foi validado na composição e no schema, sem repetir seu teste funcional. As permissões de volume correspondentes a `fsGroup` foram emuladas em Docker. Ainda não há contexto Kubernetes configurado nesta máquina: provisionamento de PVC, DNS, scheduling e probes pelo kubelet precisam ser confirmados no cluster real. Os limites também precisam ser observados sob a carga da apresentação.

- [Kustomize integrado ao kubectl](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/).
- [Probes e inicialização](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/).
- [Permissões de volumes com fsGroup](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/).
- [Requests e limits](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/).
