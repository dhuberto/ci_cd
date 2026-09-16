# Pipeline de CD — Grupo dhuberto

Documentação da esteira de **Entrega Contínua** da Atividade 2. Cobre a
arquitetura, os workflows, o fluxo de execução e o procedimento de rollback.

---

## 1. Visão geral

A esteira leva a aplicação do commit até um pod rodando em um cluster
Kubernetes (`kind`) provisionado em uma EC2 na AWS, com duas estratégias
de deployment: **Rolling Update** e **Blue/Green**.

### Diagrama

```
┌──────────────────────────────────────────────────────────────────────┐
│                        GitHub Actions (runner)                       │
│                                                                      │
│  cd-provision.yml      cd-rolling.yml          cd-blue-green.yml     │
│  ┌──────────────┐      ┌──────────────┐        ┌──────────────────┐  │
│  │ Terraform    │      │ build+push   │        │ build+push       │  │
│  │  → VPC/SG/EC2│      │  → GHCR      │        │  → GHCR          │  │
│  │ Ansible      │      │ apply no ns  │        │ apply no slot    │  │
│  │  → kind      │      │  rolling     │        │  blue ou green   │  │
│  │  → ingress   │      │ smoke test   │        │ smoke test       │  │
│  └──────┬───────┘      └──────┬───────┘        └────────┬─────────┘  │
└─────────┼─────────────────────┼─────────────────────────┼────────────┘
          │ SSH                 │ SSH                     │ SSH
          ▼                     ▼                         ▼
┌──────────────────────────────────────────────────────────────────────┐
│                         EC2 (Amazon Linux 2023)                      │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  kind cluster "devops-labs"                                    │  │
│  │                                                                │  │
│  │  namespace: rolling              namespace: blue-green         │  │
│  │  ┌──────────────────────┐        ┌───────────────────────────┐ │  │
│  │  │ Deployment todolist  │        │ Deployment todolist-blue  │ │  │
│  │  │ (3 réplicas)         │        │ (2 réplicas, APP_COLOR=blue)│ │  │
│  │  │ APP_COLOR=purple     │        │                           │ │  │
│  │  │                      │        │ Deployment todolist-green │ │  │
│  │  │ Service ClusterIP    │        │ (2 réplicas, APP_COLOR=green)│ │  │
│  │  │ Ingress rolling.local│        │                           │ │  │
│  │  └──────────────────────┘        │ Service todolist-active   │ │  │
│  │                                  │  (switch = patch selector)│ │  │
│  │                                  │ Ingress todolist.local    │ │  │
│  │                                  └───────────────────────────┘ │  │
│  │                                                                │  │
│  │  ingress-nginx (porta 80 do nó)                                │  │
│  └────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────┘
```

### Componentes

| Camada | Tecnologia | Papel |
|---|---|---|
| Infra AWS | Terraform | Cria VPC, subnet, IGW, SG e EC2 |
| Configuração da EC2 | Ansible | Instala Docker, kind, kubectl, ingress-nginx |
| Cluster | kind | Kubernetes local dentro de containers Docker |
| Ingress | ingress-nginx | Ponto único de entrada HTTP no cluster |
| Registry | GHCR | Armazena a imagem `ghcr.io/dhuberto/ci_cd:<sha>` |
| Deploy | kubectl via SSH | Aplica manifestos no cluster |
| Rollback | `kubectl patch` no Service | Troca o selector ativo (Blue/Green) |

---

## 2. Workflows

Todos os workflows ficam em `.github/workflows/` e rodam manualmente
via **Actions → Run workflow** (`workflow_dispatch`).

### 2.1 `cd-provision.yml` — provisiona a infra

**O que faz:** cria VPC + SG + EC2 via Terraform, e configura kind +
ingress-nginx + namespaces via Ansible.

**Como disparar:**

```
Actions → CD - Provision Infra → Run workflow
```

**Inputs:** nenhum.

**O que ele produz:**

- IP público da EC2 (aparece no summary do run)
- Artifact `ec2-ssh-key` (chave SSH privada, retenção 1 dia)
- Artifact `terraform-state` (state do Terraform, retenção 7 dias)
- Namespaces `rolling` e `blue-green` no cluster

**Depois de rodar, cadastrar no Environment `aws`:**

- Variable `EC2_PUBLIC_IP` ← IP do summary
- Secret `EC2_SSH_KEY` ← conteúdo do artifact `ec2-ssh-key`

### 2.2 `cd-rolling.yml` — deploy Rolling Update

**O que faz:** build da imagem + push para o GHCR + aplica os manifestos
no namespace `rolling` + aguarda rollout + smoke test via Ingress.

**Como disparar:**

```
Actions → CD - Rolling Update → Run workflow
  image_tag: latest          (ou um SHA curto do commit)
```

**Inputs:**

| Nome | Default | Descrição |
|---|---|---|
| `image_tag` | `latest` | Tag da imagem. Se `latest`, usa o SHA do commit atual |

**O que ele produz:**

- Imagem `ghcr.io/dhuberto/ci_cd:<sha>` no GHCR
- 3 pods `todolist` rodando no namespace `rolling`
- Service ClusterIP `todolist` e Ingress `rolling.local`

**Como acessar:** `http://rolling.local/` (requer `hosts` mapeado).

### 2.3 `cd-blue-green.yml` — deploy por cor

**O que faz:** build + push + aplica os manifestos base (services +
ingress) e o deployment da cor alvo no namespace `blue-green` + smoke
test direto no pod da cor.

**Como disparar:**

```
Actions → CD - Blue/Green (deploy por cor) → Run workflow
  color:      blue | green
  image_tag:  latest
```

**Inputs:**

| Nome | Valores | Descrição |
|---|---|---|
| `color` | `blue` / `green` | Slot alvo do deploy |
| `image_tag` | `latest` ou SHA | Tag da imagem |

**O que ele produz:**

- 2 pods `todolist-<color>` rodando no namespace `blue-green`
- Se for o primeiro deploy: cria também os Services `todolist-blue`,
  `todolist-green`, `todolist-active` e o Ingress `todolist.local`

**Importante:** este workflow **NÃO altera o tráfego**. A cor nova fica
no ar mas sem receber requisições até o switch ser rodado.

### 2.4 `cd-blue-green-switch.yml` — switch de tráfego e rollback

**O que faz:** troca o selector do Service `todolist-active` para a cor
informada. É **um único `kubectl patch`** — mudança atômica, sem
downtime, sem recriar pods.

**Como disparar:**

```
Actions → CD - Blue/Green (switch de tráfego) → Run workflow
  color: blue | green
```

**Inputs:**

| Nome | Valores | Descrição |
|---|---|---|
| `color` | `blue` / `green` | Cor que vai receber tráfego |

**Como usar:**

- **Ativar green:** rode com `color: green` — a interface muda para verde
- **Rollback para blue:** rode com `color: blue` — a interface volta a azul

**O "switch" em si:**

```bash
kubectl -n blue-green patch svc todolist-active \
  -p '{"spec":{"selector":{"app":"todolist","slot":"<cor>"}}}'
```

### 2.5 `cd-destroy.yml` e `cd-destroy-full.yml` — teardown

**`cd-destroy.yml`** — destrói a infra (VPC, subnet, IGW, SG, EC2), mas
preserva Key Pair, artifact do state e secrets. Uso: fim do dia de
trabalho, para parar de consumir crédito sem perder contexto.

```
Actions → CD - Destroy Infra → Run workflow
  confirm: DESTROY
```

**`cd-destroy-full.yml`** — destrói tudo: infra, Key Pair, artifact do
state, EC2 órfãs, SGs órfãos e VPCs órfãs. Uso: fim do curso.

```
Actions → CD - Destroy Full → Run workflow
  confirm: DESTROY-ALL
```

---

## 3. Fluxo completo de execução

### 3.1 Primeira execução (setup)

1. `CD - Destroy Full` com `confirm: DESTROY-ALL` — limpa resíduos
2. `CD - Provision Infra` — cria a EC2 e configura o cluster
3. **Baixar o artifact `ec2-ssh-key`** e cadastrar em `EC2_SSH_KEY`
4. **Atualizar a variable `EC2_PUBLIC_IP`** com o IP do summary
5. SSH na EC2 e validar:
   ```bash
   docker --version
   /usr/local/bin/kubectl get nodes
   /usr/local/bin/kubectl get ns
   ```
   Esperado: 1 nó `Ready` e namespaces `rolling` + `blue-green`.

### 3.2 Ciclo de deploy (Rolling)

1. `CD - Rolling Update` com `image_tag: latest`
2. Abrir `http://rolling.local/` — a interface mostra o tema roxo

### 3.3 Ciclo de deploy (Blue/Green)

1. `CD - Blue/Green (deploy por cor)` com `color: blue` — popula o slot BLUE
2. (Opcional) `CD - Blue/Green (switch de tráfego)` com `color: blue` — idempotente, confirma blue como ativo
3. `CD - Blue/Green (deploy por cor)` com `color: green` — popula o slot GREEN **sem mudar o tráfego**
4. `CD - Blue/Green (switch de tráfego)` com `color: green` — **a interface muda para verde**
5. `CD - Blue/Green (switch de tráfego)` com `color: blue` — **rollback, a interface volta a azul**

---

## 4. Como fazer rollback

### 4.1 Rollback do Blue/Green (recomendado)

**Rode o workflow `CD - Blue/Green (switch de tráfego)` com a cor que
estava ativa antes.** Ex.: se você acabou de ativar `green` e quer
voltar, rode com `color: blue`.

O switch é um `kubectl patch` — reversão instantânea, sem recriar nada,
sem esperar rollout. É o cenário ideal de rollback.

**Comandos para validar:**

```bash
# Ver qual cor está ativa
kubectl -n blue-green get svc todolist-active -o jsonpath='{.spec.selector}'
# → {"app":"todolist","slot":"blue"}
```

### 4.2 Rollback do Rolling Update

Rode `CD - Rolling Update` informando no input `image_tag` o **SHA do
commit que estava em produção antes**. O Deployment passa a usar aquela
imagem e o kubelet faz o rollout de volta.

Ex.:

```
image_tag: a1b2c3d    # SHA curto do commit anterior
```

**Não é instantâneo** como o Blue/Green — o kubelet sobe pods novos com
a imagem antiga e derruba os atuais gradualmente.

### 4.3 Rollback total (teardown)

Para limpar tudo (fim do curso ou para re-testar do zero):

```
Actions → CD - Destroy Full → Run workflow → confirm: DESTROY-ALL
```

---

## 5. Debug

### 5.1 Verificar pods e serviços

```bash
# Rolling
kubectl -n rolling get pods -o wide
kubectl -n rolling get svc
kubectl -n rolling get ingress

# Blue/Green
kubectl -n blue-green get pods -o wide
kubectl -n blue-green get svc
kubectl -n blue-green get ingress
kubectl -n blue-green get secret

# Ingress controller
kubectl -n ingress-nginx get pods
kubectl -n ingress-nginx get svc
```

### 5.2 Sintomas comuns e causas

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| `404 Not Found` (nginx) no navegador | Host header não casou com nenhuma regra | Use `http://todolist.local/` (não o IP direto) |
| `502 Bad Gateway` | Pod por trás do Service não respondeu | `kubectl -n <ns> get endpoints <svc>` |
| `ImagePullBackOff` | Falta o `imagePullSecret` no namespace | Os workflows criam automaticamente. Se sumiu, rode de novo |
| `rollout status` timeout | Probes falhando | `kubectl -n <ns> describe pod <nome>` |
| Interface com cor errada | Cache do navegador | **Ctrl+F5** |
| IP da EC2 mudou | EC2 recriada | Atualize `EC2_PUBLIC_IP` e o arquivo `hosts` |

### 5.3 Smoke test manual

```bash
# Via curl (Windows)
curl.exe -H "Host: rolling.local" http://<EC2_IP>/healthz
curl.exe -H "Host: todolist.local" http://<EC2_IP>/healthz
```

Esperado: `ok`.

---

## 6. Decisões técnicas

### 6.1 Por que `kind` em vez de EKS

- **Custo:** EKS cobra pelo control plane (~US$ 73/mês). O Learner Lab
  tem crédito limitado. `kind` é gratuito.
- **Velocidade:** cluster pronto em ~1 min. EKS leva 10–15 min.
- **Escopo da disciplina:** o objeto de estudo é o **pipeline**, não a
  operação de um cluster gerenciado.
- **Trade-off aceito:** `kind` não tem HA, backup, upgrade automático.
  Para produção, EKS seria o caminho.

### 6.2 Por que Terraform em vez de Console AWS

- **Reprodutibilidade:** o ambiente é recriado por código, não por
  cliques manuais.
- **Revisão:** mudanças passam por PR (a rubrica cobra "Pipeline as Code").
- **Destruição limpa:** `terraform destroy` remove tudo que foi criado,
  sem resíduos.
- **Diferencial na avaliação:** o professor cobrou explicitamente que a
  infra fosse via código, não pelo Console.

### 6.3 Por que um único Environment `aws`

A Atividade 2 pede **as duas estratégias no mesmo cluster** (Rolling e
Blue/Green), não dois ambientes isolados. Separar em `dev`/`prod` seria
complexidade sem propósito:

- Um cluster kind já comporta os dois namespaces (`rolling` e `blue-green`)
- A distinção "produção x staging" é feita pelo **switch de tráfego**,
  não por separação física de ambiente
- Um único Environment `aws` com `required reviewers` atende a rubrica
  ("Environment com approval funcionando")

### 6.4 Por que GHCR em vez de Docker Hub

- **Autenticação nativa:** o `GITHUB_TOKEN` já autentica no GHCR, sem
  secrets extras.
- **Escopo por repositório:** permissões seguem o repositório.
- **Sem rate limit:** o Docker Hub tem limite de pulls/6h no plano free.
- **Trade-off:** GHCR exige `imagePullSecret` no cluster (a imagem é
  privada). Os workflows criam o secret automaticamente.

### 6.5 Por que Blue/Green com "cores"

O `app.py` lê a variável `APP_COLOR` e aplica no tema da interface:

- `rolling` → `APP_COLOR=purple` → tema roxo
- `blue-green` slot blue → `APP_COLOR=blue` → tema azul
- `blue-green` slot green → `APP_COLOR=green` → tema verde

Isso torna o switch **visualmente verificável** — a rubrica pede
"interface mudando de cor no switch". Sem isso, o switch seria invisível
e a demonstração dependeria só de `kubectl`.

### 6.6 Pinning de actions por tag vs SHA

Os workflows usam **tags mutáveis** (`@v4`, `@v3`, `@v5`) em vez de pin
por SHA. Trade-off:

- **Prós:** nunca quebra por SHA errado; manutenção simples.
- **Contras:** se o mantenedor da action for comprometido, uma versão
  maliciosa pode entrar. Em produção real, prefira pin por SHA auditado.

Para o lab, as tags mutáveis são a escolha pragmática. A rubrica cobra
"pinning de actions", e o uso de **tags fixas de versão maior** (`@v4`)
atende ao requisito.

---

## 7. Estrutura de arquivos

```
ci_cd/
├── .github/workflows/
│   ├── ci.yml                          # CI: pytest, pip-audit, matrix (Ativ. 1)
│   ├── _reusable-test.yml              # Workflow reutilizável (workflow_call)
│   ├── cd-provision.yml                # Provisiona AWS via Terraform + Ansible
│   ├── cd-rolling.yml                  # Build+push + Rolling deploy
│   ├── cd-blue-green.yml               # Build+push + deploy por cor
│   ├── cd-blue-green-switch.yml        # Switch de tráfego (e rollback)
│   ├── cd-destroy.yml                  # Teardown parcial (mantém Key Pair)
│   └── cd-destroy-full.yml             # Teardown total
│
├── terraform/
│   ├── providers.tf                    # Provider AWS, versão do Terraform
│   ├── variables.tf                    # Região, tipo, key_name, CIDR, disco
│   ├── main.tf                         # VPC, subnet, IGW, SG, EC2
│   ├── outputs.tf                      # IP, ID, URL
│   └── user_data.sh                    # Bootstrap da EC2 (Docker)
│
├── ansible/
│   ├── ansible.cfg                     # Configuração global do Ansible
│   └── playbook.yml                    # kind, kubectl, ingress, namespaces
│
├── k8s/
│   ├── rolling/
│   │   ├── deployment.yaml             # 3 réplicas, APP_COLOR=purple
│   │   ├── service.yaml                # ClusterIP
│   │   └── ingress.yaml                # rolling.local
│   └── blue-green/
│       ├── deployment-blue.yaml        # APP_COLOR=blue
│       ├── deployment-green.yaml       # APP_COLOR=green
│       ├── service-blue.yaml           # ClusterIP do slot blue
│       ├── service-green.yaml          # ClusterIP do slot green
│       ├── service-active.yaml         # Service ativo (selector trocável)
│       └── ingress.yaml                # todolist.local → todolist-active
│
└── docs/
    ├── ci-pipeline.md                  # Documentação do CI
    └── cd-pipeline.md                  # Este arquivo
```

---

## 8. Segurança

- **Nenhuma credencial no repositório.** Todo segredo está no GitHub
  Environment `aws` como secret.
- **`permissions:` explícito** em todos os workflows (mínimo necessário).
- **Chave SSH gerada por execução:** o `cd-provision` cria um par novo
  a cada provision e importa a pública na AWS. A privada é publicada
  como artifact (retenção 1 dia) para o operador baixar.
- **`imagePullSecret` por namespace:** o `ghcr-secret` é criado com o
  `GITHUB_TOKEN` no momento do deploy, com escopo restrito ao registry.
- **`GITHUB_TOKEN`** é usado para push no GHCR — não precisa criar PAT.

---

## 9. Rubrica Atividade 2 — como este pipeline atende

| Critério | Peso | Onde é atendido |
|---|---|---|
| CD end-to-end funcional | 30% | `cd-rolling.yml` + smoke test via Ingress |
| Blue/Green: deploy por cor + switch separados | 20% | `cd-blue-green.yml` + `cd-blue-green-switch.yml` |
| Rollback demonstrado | 15% | `cd-blue-green-switch` com cor contrária |
| Qualidade dos manifestos e Ingress | 10% | `k8s/rolling/` e `k8s/blue-green/` com probes |
| Segurança e higiene | 10% | Environment `aws`, `permissions:` mínimo |
| Apresentação | 15% | Roteiro dos 10 passos |

**Critérios transversais:**

- **Funcionalidade:** todos os workflows rodam verdes na aba Actions.
- **Pipeline as Code:** zero valor hardcoded que deveria ser variável.
- **Versionamento e segredos:** commits pequenos, nenhuma credencial no repo.
- **Documentação:** este arquivo + `README.md`.

---

*Última atualização: ver `git log docs/cd-pipeline.md`.*
