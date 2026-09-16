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
├── .github/
│   ├── CODEOWNERS                                # Define quem revisa PRs em quais arquivos
│   └── workflows/
│       ├── ci.yml                                # Pipeline de CI: roda em PR/push com pytest, pip-audit, matrix e Trivy
│       ├── _reusable-test.yml                    # Workflow reutilizável (workflow_call) com os steps de teste
│       ├── cd-provision.yml                      # Provisiona AWS via Terraform e configura kind+ingress na EC2 via Ansible
│       ├── cd-rolling.yml                        # Build+push da imagem e deploy Rolling Update no namespace rolling
│       ├── cd-blue-green.yml                     # Build+push e deploy no slot blue ou green (cor inativa)
│       └── cd-blue-green-switch.yml              # Faz o cutover: patch do Service active (switch e rollback)
│
├── terraform/
│   ├── providers.tf                              # Declara provider AWS e versão do Terraform (state local no runner)
│   ├── variables.tf                              # Variáveis do Terraform: região, tipo da instância, key_name, CIDR
│   ├── main.tf                                   # Recursos AWS: VPC, subnet, IGW, route table, SG e EC2
│   ├── outputs.tf                                # Outputs consumidos pelo workflow: IP público, ID, URL
│   └── user_data.sh                              # Script de bootstrap da EC2: instala Docker e adiciona ec2-user ao grupo
│
├── ansible/
│   ├── ansible.cfg                               # Configuração do Ansible: inventory, usuário, chave SSH
│   ├── inventory.sh                              # Gera o inventory dinâmico a partir da variável EC2_IP
│   └── playbook.yml                              # Instala kind, kubectl, cria cluster e ingress-nginx, cria namespaces
│
├── k8s/
│   ├── rolling/
│   │   ├── deployment.yaml                       # Deployment do Rolling Update (3 réplicas, strategy RollingUpdate)
│   │   ├── service.yaml                          # Service ClusterIP interno do namespace rolling
│   │   └── ingress.yaml                          # Ingress que expõe rolling.local → Service todolist
│   └── blue-green/
│       ├── deployment-blue.yaml                  # Deployment do slot blue (APP_COLOR=blue, labels slot=blue)
│       ├── deployment-green.yaml                 # Deployment do slot green (APP_COLOR=green, labels slot=green)
│       ├── service-blue.yaml                     # Service ClusterIP do slot blue (usado pelo smoke test)
│       ├── service-green.yaml                    # Service ClusterIP do slot green (usado pelo smoke test)
│       ├── service-active.yaml                   # Service ativo — o switch de tráfego só troca o selector dele
│       └── ingress.yaml                          # Ingress aponta sempre para todolist-active em todolist.local
│
├── docs/
│   ├── ci-pipeline.md                            # Documentação do pipeline de CI (gates, matrix, reusable)
│   └── cd-pipeline.md                            # Documentação do pipeline de CD (arquitetura, deploy, rollback)
│
├── Dockerfile                                    # Build da imagem da aplicação Flask usada nos deploys
├── app.py                                        # Aplicação Flask com rotas / e /healthz usadas pelos gates
├── requirements.txt                              # Dependências de produção (alvo do pip-audit e Trivy)
├── requirements-dev.txt                          # Dependências de desenvolvimento (pytest, ruff, pip-audit)
├── test_app.py                                   # Testes unitários da aplicação
└── README.md                                     # Documentação do grupo: arquitetura, comandos, rollback
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
