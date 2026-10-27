# JWT da CatalogAPI no Kubernetes

O Catalog usa `Jwt__JwksUri=http://usersapi:8080/.well-known/jwks.json` para obter automaticamente as chaves públicas do Users. A chave privada permanece somente no Users. Não é necessário copiar PEM, criar `catalog-jwt-public-key` ou compartilhar PVC entre as APIs.

## Imagens

- Users: `fgcprojetofiap/users-api:1.5`.
- Catalog: `fgcprojetofiap/catalog-api:1.0.3`.

As imagens foram testadas e publicadas no Docker Hub em 27/10/2026. Uma instalação nova pode baixá-las diretamente pelos manifests; não é necessário compilar as APIs.

## Inicialização e cache

O Catalog inicia sua atualização de chaves em segundo plano, tentando novamente a cada 5 segundos quando o Users está indisponível. `/health` só fica saudável depois de obter chaves públicas válidas. A startup probe permite cerca de 300 segundos para a preparação.

O cache é atualizado normalmente a cada 60 segundos e vale por até 900 segundos. Um identificador desconhecido solicita nova atualização, limitada a uma tentativa a cada 5 segundos. As requisições são validadas localmente; não há consulta de rede por operação com uma chave conhecida. Uma falha temporária de rede conserva apenas o cache ainda válido. Sem chave válida, a autenticação é recusada.

O endereço é configurado no ambiente, nunca obtido do token. Redirecionamentos HTTP são desabilitados. HTTP é permitido em Development; fora desse ambiente, a URL precisa usar HTTPS. Assinatura RS256, `kid`, emissor, audiência, expiração e identidade continuam sendo validados. Emissor e audiência vêm do `fcg-config`.

`/health/live` verifica vida sem exigir cache válido; readiness/startup usam `/health`.

## Compatibilidade com o modo PEM

O código conserva o modo anterior `Jwt:PublicKeys`, usado por configurações que fornecem PEM ou arquivo local. As duas origens não devem ser configuradas simultaneamente. `catalog-jwt-public-key.example.yml` é somente um exemplo legado incompleto e fica fora do Kustomize; não o aplique sobre um ConfigMap real.

## Validação desta alteração

- 73 testes de autenticação/JWKS do Catalog aprovados, incluindo atualização, expiração do cache, indisponibilidade e rejeição de conjuntos inválidos.
- 40 testes de autorização/JWKS do Users aprovados.
- 15 verificações no cluster Docker Desktop aprovadas: endpoint público, login Users, criação de jogo protegida no Catalog, rejeição de token ausente/adulterado, leitura do jogo e ausência de volume de chave no Catalog.

Nenhum e-mail foi enviado nessa prova. Um jogo fictício foi criado no banco Catalog para comprovar a operação autenticada.
