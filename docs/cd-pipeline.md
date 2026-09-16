## Provision e Destroy

### Provision — criar a infra
**Actions → CD - Provision Infra → Run workflow**

Provisiona: VPC, subnet, IGW, SG, EC2. Instala Docker (via user_data)
e kind + kubectl + ingress-nginx + namespaces (via Ansible).

Outputs no summary:
- IP público → cole na variable `EC2_PUBLIC_IP`
- Artifact `ec2-ssh-key` → baixe e cadastre em secret `EC2_SSH_KEY`

### Destroy Infra — fim do dia de trabalho
**Actions → CD - Destroy Infra → Run workflow → confirm: DESTROY**

Destrói: VPC, subnet, IGW, SG, EC2.
Mantém: Key Pair `ci-cd-deploy-key`, artifact `terraform-state`, secrets/variables.

Depois é só rodar `cd-provision` — a mesma chave SSH continua valendo.
Atualize apenas a variable `EC2_PUBLIC_IP` (o IP muda a cada provision).

### Destroy Full — fim do curso / entrega
**Actions → CD - Destroy Full → Run workflow → confirm: DESTROY-ALL**

Destrói: tudo o que o Destroy Infra destrói, MAIS:
- Key Pair `ci-cd-deploy-key`
- Artifact `terraform-state`
- EC2 órfãs com a tag `ci-cd-app-ec2`
- Security Groups órfãos com o nome `ci-cd-app-sg`

Depois é preciso recadastrar o secret `EC2_SSH_KEY` com a nova chave
gerada pelo próximo `cd-provision`, e atualizar `EC2_PUBLIC_IP`.

### Por que o state fica num artifact

Sem backend remoto (Learner Lab não permite S3/DynamoDB custom),
o state do Terraform é salvo como artifact entre execuções. Isso permite:
- `cd-provision` reconciliar em vez de criar EC2 nova a cada run
- `cd-destroy` e `cd-destroy-full` saberem exatamente o que destruir
