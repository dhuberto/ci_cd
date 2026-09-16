[![CI](https://github.com/dhuberto/ci_cd/actions/workflows/ci.yml/badge.svg)](https://github.com/dhuberto/ci_cd/actions/workflows/ci.yml)

Configurações feitas no github:

## 1) Tornar o repositório privado
```
Settings > General > Danger Zone > Change visibility > Change to private
```

## 2) Adicionar @HardSource como collaborator (Read)
```
Settings > Collaborators and teams > Add people 
```

Atribuir permissão Read
Enviar o convite (o professor precisa aceitar)

## 3) Configurar a branch protection da main
```   
Settings > Branches > Add branch protection rule para main
```
Marque: Require a pull request before merging, 

## 4) Editar o .github/CODEOWNERS
```
.github/CODEOWNERS
*                        @emcsmalone @tiagocamilos
```

### Resumo das configurações:
```
Settings > Collaborators	Todos os 5 membros com permissão Write
Settings > Collaborators	@HardSource com permissão Read
.github/CODEOWNERS		* @emcsmalone (ou * @emcsmalone @tiagocamilos como fallback)
Settings > Branches		Regra para main com: Require PR + 1 approval
+ Require review from Code Owners + required checks + up to date
```

# Estrutura:
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
    └── cd-pipeline.md                  # Documentação do CD
```
# CI/CD - Grupo dhuberto


## Checklist da Atividade 1

- [x] Repositório privado no GitHub
- [x] @HardSource adicionado como collaborator (Read)
- [x] Branch `main` protegida com required status checks
- [x] CODEOWNERS configurado
- [x] `ci.yml` disparando em `pull_request` e `push` para `main`
- [x] Testes automatizados com pytest
- [x] Auditoria de dependências com pip-audit
- [x] Matrix de Python (3.10 e 3.11)
- [x] Cache de dependências (pip)
- [x] Reusable workflow (`_reusable-test.yml`)
- [x] `permissions:` explícito e mínimo
- [x] Badge do pipeline no README
- [x] Documentação em `docs/ci-pipeline.md`
- [x] `workflow_dispatch` para execução manual

## Como rodar localmente


# Clonar para a maquina local o repositorio
```bash
git clone https://github.com/dhuberto/ci_cd.git
cd ci_cd
```

# Criar o ambiente virtual
```bash
python3 -m venv venv
```

# Ativar o ambiente virtual
# No Linux/Mac:
```bash
source venv/bin/activate
```

# Instalar as dependências
```bash
pip install -r requirements.txt -r requirements-dev.txt
```
# Rodar pip-audit verificaçaõ manual de seguraça
```bash
pip-audit -r requirements.txt -r requirements-dev.txt
```

# Iniciar o servidor
```bash
python app.py -v
```

# Testar rota raiz
```bash
http://localhost:5000/
```
# Deve retornar: {"message":"Hello, DevOps!"}

# Testar health check
```bash
http://localhost:5000/healthz
```

# Deve retornar: {"status":"healthy"}
