# JWT da CatalogAPI

O Deployment espera o ConfigMap `catalog-jwt-public-key` no namespace
`fcg-demo`, com a chave `public.pem`. Somente esse arquivo e montado, para
leitura, em `/data/jwt-publica/public.pem`.

O arquivo `catalog-jwt-public-key.example.yml` e um exemplo incompleto, sem
PEM. Nao o aplique e nao aplique este diretorio inteiro: isso poderia criar
ou sobrescrever o ConfigMap real com dados vazios.

## Provisionamento anterior ao deploy

1. Obtenha com o responsavel pela UsersAPI o PEM publico correspondente a
   chave privada usada para assinar tokens com `kid=users-demo-v1`.
   Guarde o arquivo fora do repositorio. Nao gere outro par RSA e nao use
   uma chave privada neste procedimento.
2. Garanta que o namespace `fcg-demo` exista. Provisione o ConfigMap a partir
   do arquivo real, substituindo o caminho abaixo. Execute somente quando
   o provisionamento no cluster estiver autorizado:

   ```powershell
   kubectl create configmap catalog-jwt-public-key --namespace fcg-demo --from-file=public.pem="C:\caminho-fora-do-repositorio\public.pem" --dry-run=client -o yaml | kubectl apply -f -
   ```

   O manifesto real e transmitido diretamente ao kubectl, sem ser salvo no Git.

3. Antes do deploy da CatalogAPI, tambem devem existir `fcg-config` e
   `fcg-secrets` no mesmo namespace, alem das dependencias PostgreSQL e RabbitMQ
   ja referenciadas pelo Deployment.

## Comportamento e verificacao

- `Jwt__PublicKeys__0__Kid` usa `users-demo-v1`.
- `Jwt__PublicKeys__0__PublicKeyPath` aponta para o arquivo montado.
- Nao configure `Jwt__PublicKeys__0__PublicKeyPem` simultaneamente: a API
  exige exatamente uma origem por chave.
- O codigo de autenticacao le e importa o PEM na inicializacao. ConfigMap
  ou chave `public.pem` ausente impede a montagem; PEM invalido impede a
  inicializacao. O exemplo vazio nao satisfaz essa dependencia.
- Emissor e audiencia continuam vindo de `fcg-config` e precisam coincidir
  com os tokens da UsersAPI.
- Ao substituir a chave, reinicie os Pods da CatalogAPI para recarrega-la.
- A verificacao funcional exige um token emitido pela UsersAPI e uma rota
  protegida da CatalogAPI. O endpoint `/health` nao valida esse fluxo.

Nenhuma chave privada deve ser disponibilizada a CatalogAPI. O fornecimento
do PEM correto e a disponibilidade da UsersAPI sao dependencias externas a
esta configuracao.
