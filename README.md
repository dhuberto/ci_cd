# CI/CD — Grupo dhuberto

[![CI](https://github.com/dhuberto/ci_cd/actions/workflows/ci.yml/badge.svg)](https://github.com/dhuberto/ci_cd/actions/workflows/ci.yml)

Repositório da disciplina **Pipelines de Entrega Contínua (CI/CD) e
Automação de Deployments**. Contém a aplicação, os pipelines de CI e
CD, a infraestrutura como código (Terraform) e a configuração da EC2
(Ansible).

**Membros:**

- @dhuberto (Owner)

---

## Sumário

- [Visão geral](#visão-geral)
- [Arquitetura de deploy](#arquitetura-de-deploy)
- [Pipeline de CI (Atividade 1)](#pipeline-de-ci-atividade-1)
- [Pipeline de CD (Atividade 2)](#pipeline-de-cd-atividade-2)
- [Como fazer rollback](#como-fazer-rollback)
- [Como rodar localmente](#como-rodar-localmente)
- [Estrutura do repositório](#estrutura-do-repositório)
- [Checklists das atividades](#checklists-das-atividades)

---

## Visão geral

A esteira cobre dois ciclos:

- **CI** — valida cada PR com testes, auditoria de dependências e
  análise estática (matrix Python + cache + reusable workflow).
- **CD** — provisiona a infraestrutura na AWS via Terraform, configura
  o cluster `kind` na EC2 via Ansible, e faz deploy com duas
  estratégias: **Rolling Update** e **Blue/Green**.

A imagem da aplicação é publicada no **GHCR**
(`ghcr.io/dhuberto/ci_cd:<sha>`).

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
       │     ├── Deployment todolist (3 réplicas, APP_COLOR=purple)
       │     ├── Service ClusterIP todolist
       │     └── Ingress rolling.local
       │
       └── namespace: blue-green
             ├── Deployment todolist-blue  (2 réplicas, APP_COLOR=blue)
             ├── Deployment todolist-green (2 réplicas, APP_COLOR=green)
             ├── Service todolist-active   (selector trocável)
             └── Ingress todolist.local
```

### Componentes

| Camada | Tecnologia | Papel |
|---|---|---|
| Infra AWS | Terraform | VPC, subnet, IGW, SG, EC2 |
| Configuração da EC2 | Ansible | Docker, kind, kubectl, ingress-nginx |
| Cluster | kind | Kubernetes local dentro de Docker |
| Ingress | ingress-nginx | Ponto único de entrada HTTP |
| Registry | GHCR | Imagem `ghcr.io/dhuberto/ci_cd:<sha>` |
| Deploy | kubectl via SSH | Aplica manifestos no cluster |
| Rollback | `kubectl patch` no Service | Troca o selector ativo (Blue/Green) |

---

## Pipeline de CI (Atividade 1)

**Workflow:** `.github/workflows/ci.yml`

**Gatilhos:** `pull_request` e `push` na `main`.

**O que roda:**

1. **Lint** com `ruff`
2. **Testes** com `pytest` em matrix Python 3.10 / 3.11 / 3.12
3. **Auditoria de dependências** com `pip-audit` (bloqueia o PR se achar CVE)
4. **Scan de imagem** com Trivy (via reusable workflow)

**Features de destaque:**

- **Reusable workflow** (`_reusable-test.yml`) extrai os steps de
  teste, evitando duplicação entre jobs.
- **Cache de dependências** (pip) — segundo run é ~3x mais rápido.
- **`permissions:` mínimo** — `contents: read` por padrão; jobs que
  precisam de mais pedem explicitamente.
- **Branch protection** — required checks (`Test (Python 3.10/3.11/3.12)`,
  `Dependency audit`) bloqueiam o merge se qualquer um falhar.
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
- Aplica manifestos no namespace `rolling`
- Aguarda rollout dos 3 pods
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

## Como rodar localmente

### Pré-requisitos

- Python 3.10+
- git

### Subir a aplicação

```bash
# Clonar
git clone https://github.com/dhuberto/ci_cd.git
cd ci_cd

# Ambiente virtual
python3 -m venv venv

# Ativar (Linux/Mac)
source venv/bin/activate

# Ativar (Windows PowerShell)
.\venv\Scripts\Activate.ps1

# Instalar dependências
pip install -r requirements.txt -r requirements-dev.txt

# Rodar o servidor
python app.py -v
```

**Rotas para testar:**

| Rota | Resposta esperada |
|---|---|
| `http://localhost:5000/` | Página da todo-list |
| `http://localhost:5000/healthz` | `ok` |

### Rodar os checks do CI localmente

```bash
# Testes
pytest -v

# Lint
ruff check .

# Auditoria de dependências
pip-audit -r requirements.txt -r requirements-dev.txt
```

### Rodar com Docker

```bash
docker build -t todolist:dev .
docker run --rm -p 8080:5000 \
  -e APP_COLOR=blue \
  -e SESSION_KEY=local \
  todolist:dev
```

Acesse `http://localhost:8080/`.

---

## Estrutura do repositório

```
ci_cd/
├── .github/
│   ├── CODEOWNERS
│   └── workflows/
│       ├── ci.yml                        # CI (Atividade 1)
│       ├── _reusable-test.yml            # Reusable workflow (workflow_call)
│       ├── cd-provision.yml              # Provisiona AWS + kind + ingress
│       ├── cd-rolling.yml                # Deploy Rolling
│       ├── cd-blue-green.yml             # Deploy Blue/Green por cor
│       ├── cd-blue-green-switch.yml      # Switch de tráfego + rollback
│       ├── cd-destroy.yml                # Teardown parcial
│       └── cd-destroy-full.yml           # Teardown total
│
├── terraform/                            # IaC da AWS
│   ├── providers.tf
│   ├── variables.tf
│   ├── main.tf
│   ├── outputs.tf
│   └── user_data.sh
│
├── ansible/                              # Configuração da EC2
│   ├── ansible.cfg
│   └── playbook.yml
│
├── k8s/                                  # Manifestos Kubernetes
│   ├── rolling/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── ingress.yaml
│   └── blue-green/
│       ├── deployment-blue.yaml
│       ├── deployment-green.yaml
│       ├── service-blue.yaml
│       ├── service-green.yaml
│       ├── service-active.yaml
│       └── ingress.yaml
│
├── docs/
│   ├── ci-pipeline.md                    # Documentação detalhada do CI
│   └── cd-pipeline.md                    # Documentação detalhada do CD
│
├── Dockerfile                            # Build da imagem
├── app.py                                # Aplicação Flask
├── test_app.py                           # Testes pytest
├── requirements.txt                      # Deps de produção
├── requirements-dev.txt                  # Deps de dev
├── pyproject.toml                        # Config do ruff
└── README.md                             # Este arquivo
```

---

## Checklists das atividades

### Atividade 1 — Lab de CI

- [x] Repositório privado no GitHub
- [x] `@HardSource` adicionado como collaborator (Read)
- [x] Branch `main` protegida com required status checks
- [x] `CODEOWNERS` configurado
- [x] `ci.yml` disparando em `pull_request` e `push` na `main`
- [x] Testes automatizados com pytest
- [x] Auditoria de dependências com `pip-audit`
- [x] Matrix de Python (3.10, 3.11, 3.12)
- [x] Cache de dependências (pip)
- [x] Reusable workflow (`_reusable-test.yml`)
- [x] `permissions:` explícito e mínimo
- [x] Badge do pipeline no README
- [x] Documentação em `docs/ci-pipeline.md`
- [x] `workflow_dispatch` para execução manual

### Atividade 2 — Lab de CD

- [x] Imagem publicada no GHCR com tag do commit
- [x] Cluster kind + ingress-nginx acessível pelo Actions
- [x] Manifestos com Deployment, Service ClusterIP e Ingress
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
- **GHCR em vez de Docker Hub:** autenticação nativa via `GITHUB_TOKEN`
  e sem rate limit.
- **Blue/Green com `APP_COLOR`:** torna o switch visualmente verificável
  (roxo/azul/verde), atendendo ao critério da rubrica.

---

## Referências

- [`docs/ci-pipeline.md`](docs/ci-pipeline.md) — documentação detalhada do CI
- [`docs/cd-pipeline.md`](docs/cd-pipeline.md) — documentação detalhada do CD
- Rubrica da Atividade 1 e 2 (fornecidas pelo professor)
