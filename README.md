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
│   ├── CODEOWNERS
│   └── workflows/
│       ├── ci.yml
│       ├── _reusable-test.yml
│       ├── cd-provision.yml
│       ├── cd-rolling.yml
│       ├── cd-blue-green.yml
│       └── cd-blue-green-switch.yml
│
├── terraform/
│   ├── providers.tf
│   ├── variables.tf
│   ├── main.tf
│   ├── outputs.tf
│   └── user_data.sh
│
├── ansible/
│   ├── ansible.cfg
│   ├── inventory.sh
│   └── playbook.yml
│
├── k8s/
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
│   ├── ci-pipeline.md
│   └── cd-pipeline.md
│
├── Dockerfile
├── app.py
├── requirements.txt
├── requirements-dev.txt
├── test_app.py
└── README.md                     # Testes unitários da aplicação
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
