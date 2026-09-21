# CI/CD — dhuberto

[![CI](https://github.com/dhuberto/ci_cd/actions/workflows/ci.yml/badge.svg)](https://github.com/dhuberto/ci_cd/actions/workflows/ci.yml)

Repositório da disciplina **Pipelines de Entrega Contínua (CI/CD) e
Automação de Deployments**. Contém a aplicação (Go + Postgres), os
pipelines de CI e CD, a infraestrutura como código (Terraform) e a
configuração da EC2 (Ansible).

**Membros:**

- @dhuberto (Owner)

---

## Sumário

- [Visão geral](#visão-geral)
- [Arquitetura de deploy](#arquitetura-de-deploy)
- [Pipeline de CI (Atividade 1)](#pipeline-de-ci-atividade-1)
- [Pipeline de CD (Atividade 2)](#pipeline-de-cd-atividade-2)
- [Como fazer rollback](#como-fazer-rollback)
- [Acessando o ambiente](#acessando-o-ambiente)
- [Como rodar localmente](#como-rodar-localmente)
- [Estrutura do repositório](#estrutura-do-repositório)
- [Checklists das atividades](#checklists-das-atividades)

---

## Visão geral

A esteira cobre dois ciclos:

- **CI** — valida cada PR com testes (`go test`), análise estática
  (`go vet`) e auditoria de dependências (`govulncheck`) em matrix
  Go 1.22 / 1.23, além de scan de segurança com Trivy.
- **CD** — provisiona a infraestrutura na AWS via Terraform, configura
  o cluster `kind` na EC2 via Ansible, e faz deploy com duas
  estratégias: **Rolling Update** e **Blue/Green**.

A imagem da aplicação é publicada no **GHCR**
(`ghcr.io/dhuberto/ci_cd:<sha>`).

**Aplicação:** todo-list em Go + PostgreSQL com renderização no servidor
(SSR). O binário é estático (`CGO_ENABLED=0`), a imagem final tem cerca
de ~20 MB e o driver Postgres é compilado dentro do binário — zero
dependências em runtime.

---

## Arquitetura de deploy

```
GitHub Actions (runner hospedado)
 │
 ├── cd-provision.yml
 │     └── Terraform: VPC + subnet + IGW + SG + EC2 (Amazon Linux 2023)
 │     └── Ansible: Docker + kind + kubectl + ingress-nginx + namespaces
 │
 ├── cd-rolling.yml
 │     └── build+push GHCR → kubectl apply no namespace rolling → smoke test
 │
 ├── cd-blue-green.yml
 │     └── build+push GHCR → deploy no slot blue OU green (sem mexer no tráfego)
 │
 └── cd-blue-green-switch.yml
       └── kubectl patch no Service active → muda a cor da interface
 │
 ▼ (SSH)
EC2 Amazon Linux 2023
 └── cluster kind "devops-labs"
       ├── namespace: rolling
       │     ├── StatefulSet postgres   (1 réplica, PVC 1Gi, postgres:alpine)
       │     ├── Service postgres       (headless, para DNS estável)
       │     ├── Deployment todolist    (3 réplicas, APP_COLOR=purple)
       │     ├── Service todolist       (ClusterIP)
       │     └── Ingress rolling.local
       │
       └── namespace: blue-green
             ├── StatefulSet postgres       (1 réplica, PVC 1Gi)
             ├── Service postgres           (headless)
             ├── Deployment todolist-blue   (2 réplicas, APP_COLOR=blue)
             ├── Deployment todolist-green  (2 réplicas, APP_COLOR=green)
             ├── Service todolist-active    (selector trocável)
             └── Ingress todolist.local
```

### Componentes

| Camada | Tecnologia | Papel |
|---|---|---|
| Infra AWS | Terraform | VPC, subnet, IGW, SG, EC2 |
| Configuração da EC2 | Ansible | Docker, kind, kubectl, ingress-nginx |
| Cluster | kind | Kubernetes local dentro de Docker |
| Ingress | ingress-nginx | Ponto único de entrada HTTP |
| Banco de dados | Postgres (StatefulSet + PVC) | Persistência real (1Gi por namespace) |
| Aplicação | Go + `database/sql` + `lib/pq` | SSR, binário estático, sem runtime deps |
| Registry | GHCR | Imagem `ghcr.io/dhuberto/ci_cd:<sha>` |
| Deploy | kubectl via SSH | Aplica manifestos no cluster |
| Rollback | `kubectl patch` no Service | Troca o selector ativo (Blue/Green) |

---

## Pipeline de CI (Atividade 1)

**Workflow:** `.github/workflows/ci.yml`

**Gatilhos:** `pull_request` e `push` na `main`.

**O que roda:**

1. **Análise estática** com `go vet`
2. **Testes** com `go test` em matrix Go 1.22 / 1.23
3. **Auditoria de dependências** com `govulncheck` (bloqueia o PR se achar CVE)
4. **Scan de imagem** com Trivy (filesystem + image)

**Features de destaque:**

- **Reusable workflow** (`_reusable-test.yml`) extrai os steps de
  teste, evitando duplicação entre jobs.
- **Cache de módulos Go** (`go.sum`) — segundo run é ~3x mais rápido.
- **`permissions:` mínimo** — `contents: read` por padrão; jobs que
  precisam de mais pedem explicitamente.
- **Branch protection** — required checks (`Test (Go 1.22)`,
  `Test (Go 1.23)`, `Dependency audit`) bloqueiam o merge se qualquer
  um falhar.
- **CODEOWNERS** — revisores atribuídos automaticamente por arquivo.

### Como disparar o CI

Automático em qualquer PR ou push na `main`. Para rodar manualmente:
**Actions → CI → Run workflow**.

### Documentação detalhada

Ver [`docs/ci-pipeline.md`](docs/ci-pipeline.md).

---

## Pipeline de CD (Atividade 2)

**Documentação detalhada:** [`docs/cd-pipeline.md`](docs/cd-pipeline.md)

Todos os workflows de CD rodam **manualmente** via
**Actions → Run workflow**.

### 1. Provisionar a infra

```
Actions → CD - Provision Infra → Run workflow
```

**O que faz:**

- Cria VPC, subnet, IGW, SG e EC2 (Amazon Linux 2023) via Terraform
- Instala Docker via `user_data.sh`
- Instala kind, kubectl, ingress-nginx e cria os namespaces via Ansible
- Publica os artifacts `ec2-ssh-key` e `terraform-state`

**Depois de rodar:**

1. Baixe o artifact `ec2-ssh-key` e cadastre em
   **Settings → Environments → aws → Secrets → `EC2_SSH_KEY`**.
2. Copie o IP do summary e atualize a variable
   **`EC2_PUBLIC_IP`** no mesmo Environment.

### 2. Deploy Rolling

```
Actions → CD - Rolling Update → Run workflow
  image_tag: latest
```

**O que faz:**

- Build + push da imagem para o GHCR
- Aplica o Postgres (Secret + Service + StatefulSet) no namespace `rolling`
- Aguarda o rollout do Postgres
- Aplica o RBAC + a aplicação (Deployment + Service + Ingress)
- Aguarda o rollout dos 3 pods
- Smoke test via Ingress (`http://rolling.local/healthz`)

**Como acessar:**

Adicione ao arquivo `C:\Windows\System32\drivers\etc\hosts`
(Windows, como Administrador):

```
<IP_DA_EC2>   rolling.local
<IP_DA_EC2>   todolist.local
```

Depois abra `http://rolling.local/` — tema **roxo**.

### 3. Deploy Blue/Green — slot BLUE

```
Actions → CD - Blue/Green (deploy por cor) → Run workflow
  color:     blue
  image_tag: latest
```

**O que faz:**

- Build + push da imagem
- Aplica o Postgres do namespace `blue-green` (Secret + Service + StatefulSet)
- Aplica os Services (`todolist-blue`, `todolist-green`,
  `todolist-active`), o Ingress e o Deployment `todolist-blue`
- Smoke test direto no pod do slot blue
- **Não altera o tráfego** — o `todolist-active` já aponta para blue
  por default

**Como acessar:** `http://todolist.local/` — tema **azul**.

### 4. Deploy Blue/Green — slot GREEN

```
Actions → CD - Blue/Green (deploy por cor) → Run workflow
  color:     green
  image_tag: latest
```

**O que faz:**

- Deploya o slot green no cluster
- **Não altera o tráfego** — a interface continua azul

**Estado esperado no cluster:** 4 pods no namespace (`blue` + `green`).

### 5. Switch de tráfego para GREEN

```
Actions → CD - Blue/Green (switch de tráfego) → Run workflow
  color: green
```

**O que faz:** um único `kubectl patch` no Service `todolist-active`:

```bash
kubectl -n blue-green patch svc todolist-active \
  -p '{"spec":{"selector":{"app":"todolist","slot":"green"}}}'
```

**Resultado:** a interface em `http://todolist.local/` muda de **azul
para verde ao vivo**. Sem downtime, sem recriar pods, sem esperar rollout.

---

## Como fazer rollback

### Rollback do Blue/Green (recomendado)

Rode o mesmo workflow de switch com a **cor anterior**:

```
Actions → CD - Blue/Green (switch de tráfego) → Run workflow
  color: blue
```

O patch troca o selector de volta. A interface volta a azul em segundos.

**Validação:**

```bash
kubectl -n blue-green get svc todolist-active -o jsonpath='{.spec.selector}'
# → {"app":"todolist","slot":"blue"}
```

### Rollback do Rolling

Rode o `CD - Rolling Update` informando no input `image_tag` o SHA do
commit que estava em produção antes. O Deployment passa a usar aquela
imagem e o kubelet faz o rollout de volta.

```
Actions → CD - Rolling Update → Run workflow
  image_tag: a1b2c3d    # SHA curto do commit anterior
```

Não é instantâneo como o Blue/Green — o kubelet sobe pods novos com a
imagem antiga e derruba os atuais gradualmente.

### Rollback total (teardown)

```
Actions → CD - Destroy Infra → Run workflow
  confirm: DESTROY
```

Destrói VPC, subnet, IGW, SG e EC2. Preserva o Key Pair
(`ci-cd-deploy-key`), o artifact do state e os secrets.

Para limpar tudo (fim do curso):

```
Actions → CD - Destroy Full → Run workflow
  confirm: DESTROY-ALL
```

---

## Acessando o ambiente

Acessa via SSH:

```bash
ssh -i ~/.ssh/deploy_key ec2-user@<IP_DA_EC2>
```

Comandos úteis dentro da EC2:

```bash
# Pods da aplicação no rolling
/usr/local/bin/kubectl -n rolling get pods -o wide

# Postgres no rolling
/usr/local/bin/kubectl -n rolling get statefulset,pvc

# Pods no blue-green
/usr/local/bin/kubectl -n blue-green get pods -o wide

# Qual cor está ativa agora
/usr/local/bin/kubectl -n blue-green get svc todolist-active -o jsonpath='{.spec.selector}'
```

---

## Como rodar localmente

### Pré-requisitos

- **Go 1.22+** instalado (`go version`)
- **Docker** + **Docker Compose** (para a stack completa com Postgres)
- **git**

### Rodar os testes

```bash
go mod tidy
go test ./...
go vet ./...
```

### Rodar direto (sem Docker)

Precisa de um Postgres acessível e das envs `DB_*` exportadas:

```bash
export DB_HOST=localhost
export DB_PORT=5432
export DB_USER=appuser
export DB_PASSWORD=mudar123
export DB_NAME=appdb
export APP_PORT=5000
export APP_COLOR=purple

go run ./src
```

### Rodar com Docker

```bash
# Build da imagem
docker build -t app-go:dev .

# Rodar (precisa de um Postgres acessível)
docker run --rm -p 8080:5000 \
  -e DB_HOST=host.docker.internal \
  -e DB_PORT=5432 \
  -e DB_USER=appuser \
  -e DB_PASSWORD=mudar123 \
  -e DB_NAME=appdb \
  -e APP_COLOR=purple \
  app-go:dev
```

Acesse `http://localhost:8080/`.

**Rotas para testar:**

| Rota | Resposta esperada |
|---|---|
| `http://localhost:8080/` | Página da todo-list |
| `http://localhost:8080/healthz` | `ok` |

### Rodar os checks do CI localmente

```bash
# Análise estática
go vet ./...

# Testes
go test -v ./...

# Auditoria de dependências (precisa instalar govulncheck)
go install golang.org/x/vuln/cmd/govulncheck@latest
govulncheck ./...
```

---

## Estrutura do repositório

```
ci_cd/
├── .github/
│   ├── CODEOWNERS                          # Define quem revisa PRs (dono por arquivo/pasta)
│   └── workflows/
│       ├── ci.yml                          # CI: go vet, go test, govulncheck, Trivy
│       ├── _reusable-test.yml              # Workflow reutilizável (workflow_call) com steps de teste
│       ├── cd-provision.yml                # Provisiona AWS (Terraform) + configura kind/ingress (Ansible)
│       ├── cd-rolling.yml                  # Build+push e deploy Rolling (com Postgres)
│       ├── cd-blue-green.yml               # Build+push e deploy no slot blue ou green
│       ├── cd-blue-green-switch.yml        # Patch do Service active (switch e rollback)
│       ├── cd-destroy.yml                  # Teardown parcial
│       └── cd-destroy-full.yml             # Teardown total
│
├── terraform/                              # IaC da AWS (VPC, subnet, IGW, SG, EC2)
│   ├── providers.tf                        # Provider AWS + versão do Terraform
│   ├── variables.tf                        # Variáveis: região, tipo, key_name, CIDR, disco
│   ├── main.tf                             # Recursos AWS
│   ├── outputs.tf                          # Outputs consumidos pelo workflow
│   └── user_data.sh                        # Bootstrap da EC2 (Docker)
│
├── ansible/                                # Configuração da EC2 após o provision
│   ├── ansible.cfg                         # Configuração global
│   └── playbook.yml                        # kind, kubectl, ingress-nginx, namespaces
│
├── k8s/                                    # Manifestos Kubernetes
│   ├── rolling/
│   │   ├── postgres-secret.yaml            # Credenciais do Postgres
│   │   ├── postgres-service.yaml           # Service headless do StatefulSet
│   │   ├── postgres-statefulset.yaml       # StatefulSet + PVC 1Gi
│   │   ├── rbac.yaml                       # ServiceAccount + Role + RoleBinding
│   │   ├── deployment.yaml                 # Deployment Rolling (3 réplicas, APP_COLOR=purple)
│   │   ├── service.yaml                    # Service ClusterIP
│   │   └── ingress.yaml                    # Ingress rolling.local
│   └── blue-green/
│       ├── postgres-secret.yaml            # Credenciais do Postgres (namespace blue-green)
│       ├── postgres-service.yaml           # Service headless
│       ├── postgres-statefulset.yaml       # StatefulSet + PVC 1Gi
│       ├── rbac.yaml                       # ServiceAccount + Role + RoleBinding
│       ├── deployment-blue.yaml            # Slot blue (APP_COLOR=blue)
│       ├── deployment-green.yaml           # Slot green (APP_COLOR=green)
│       ├── service-blue.yaml               # ClusterIP do slot blue
│       ├── service-green.yaml              # ClusterIP do slot green
│       ├── service-active.yaml             # Service ativo (selector trocável)
│       └── ingress.yaml                    # Ingress todolist.local
│
├── docs/
│   ├── ci-pipeline.md                      # Documentação detalhada do CI
│   └── cd-pipeline.md                      # Documentação detalhada do CD
│
├── src/
│   ├── main.go                             # Aplicação Go (HTTP + Postgres)
│   └── main_test.go                        # Testes unitários dos handlers
│
├── go.mod                                  # Módulo Go e dependências
├── go.sum                                  # Checksums das dependências
├── Dockerfile                              # Build multi-stage (Go estático + Alpine)
└── README.md                               # Documentação oficial
```

---

## Checklists das atividades

### Atividade 1 — Lab de CI

- [x] Repositório privado no GitHub
- [x] `@HardSource` adicionado como collaborator (Read)
- [x] Branch `main` protegida com required status checks
- [x] `CODEOWNERS` configurado
- [x] `ci.yml` disparando em `pull_request` e `push` na `main`
- [x] Testes automatizados com `go test`
- [x] Auditoria de dependências com `govulncheck`
- [x] Matrix de Go (1.22, 1.23)
- [x] Cache de módulos Go
- [x] Reusable workflow (`_reusable-test.yml`)
- [x] `permissions:` explícito e mínimo
- [x] Badge do pipeline no README
- [x] Documentação em `docs/ci-pipeline.md`
- [x] `workflow_dispatch` para execução manual

### Atividade 2 — Lab de CD

- [x] Imagem publicada no GHCR com tag do commit
- [x] Cluster kind + ingress-nginx acessível pelo Actions
- [x] Manifestos com Deployment, Service ClusterIP e Ingress
- [x] Postgres com StatefulSet + PVC (persistência real)
- [x] `cd-rolling.yml` com `scp` + `kubectl apply` + `rollout status` + smoke test
- [x] `cd-blue-green.yml` (deploy por cor) + `cd-blue-green-switch.yml` (cutover)
- [x] Rollback do Blue/Green demonstrado (re-switch de tráfego)
- [x] Documentação em `docs/cd-pipeline.md`
- [x] README atualizado com arquitetura de deploy e rollback
- [x] Deploy via Terraform + Ansible (sem intervenção manual no Console AWS)
- [x] Dois workflows de teardown (`cd-destroy.yml` e `cd-destroy-full.yml`)

---

## Decisões técnicas

- **`kind` em vez de EKS:** custo zero (Learner Lab) e levanta em ~1 min.
- **Terraform em vez de Console AWS:** infra reproduzível, revisável e
  destruível por código.
- **Ansible em vez de user_data:** mantém a configuração do cluster no
  repositório, versionada e idempotente.
- **Um Environment `aws`** (não `dev`/`prod`): a Atividade 2 pede as
  duas estratégias no mesmo cluster, não dois ambientes isolados.
- **Go em vez de Python:** binário estático de ~20 MB, zero dependências
  em runtime, `govulncheck` como gate de segurança. A imagem final caiu
  de ~180 MB para ~20 MB.
- **Postgres como StatefulSet + PVC:** persistência real com 1Gi por
  namespace. O StorageClass `local-path` do kind já provisiona o volume.
- **GHCR em vez de Docker Hub:** autenticação nativa via `GITHUB_TOKEN`
  e sem rate limit.
- **Blue/Green com `APP_COLOR`:** torna o switch visualmente verificável
  (roxo/azul/verde), atendendo ao critério da rubrica.

---

## Referências

- [`docs/ci-pipeline.md`](docs/ci-pipeline.md) — documentação detalhada do CI
- [`docs/cd-pipeline.md`](docs/cd-pipeline.md) — documentação detalhada do CD
- [`src/main.go`](src/main.go) — código da aplicação (Go)
- [`src/main_test.go`](src/main_test.go) — testes unitários
- Rubrica da Atividade 1 e 2 (fornecidas pelo professor)
