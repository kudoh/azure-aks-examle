# Azure AKS example

Azure AKSのExample。
クラウドリースの作成からアプリのビルドとデプロイを行って、アプリのモニタリングするところまでをカバーする。

- クラウドプロビジョニング: Terraform with Azure Storage
- コンテナレジストリ: ACR
- Backend Service: Spring Boot
- API Gateway: Node.js
- UI: Vue.js
- モニタリング: Azure Application Insights

## Terraformセットアップ

Azureリソースのプロビジョニングで利用するTerraformのセットアップを行う。

### Backend Storage作成

Terraformの状態管理ストレージとしてローカルではなくAzure Storageを利用する。

```bash
TF_RG_NAME=terraform
TF_STORAGE_ACCOUNT_NAME=terraform$RANDOM
TF_CONTAINER_NAME=tfstate
LOCATION=japaneast
TF_VAULT_NAME=tf-vault-$RANDOM

# Terraform状態管理専用リソースグループ
az group create --name $TF_RG_NAME --location $LOCATION

# Terraform状態管理用のストレージアカウントを作成
az storage account create --resource-group $TF_RG_NAME --name $TF_STORAGE_ACCOUNT_NAME --sku Standard_LRS --encryption-services blob
ACCOUNT_KEY=$(az storage account keys list --resource-group $TF_RG_NAME --account-name $TF_STORAGE_ACCOUNT_NAME --query [0].value -o tsv)
az storage container create --name $TF_CONTAINER_NAME --account-name $TF_STORAGE_ACCOUNT_NAME --account-key $ACCOUNT_KEY

# Storage Accountのアクセスキーは安全に Key Vault に保管しておく
az keyvault create --name $TF_VAULT_NAME --resource-group $TF_RG_NAME --location $LOCATION
az keyvault secret set --vault-name $TF_VAULT_NAME --name "terraform-backend-key" --value $ACCOUNT_KEY

# 環境変数に保存してTerraformにStorage Accountへのアクセスキーを認識させる
export ARM_ACCESS_KEY=$(az keyvault secret show --name terraform-backend-key --vault-name ${TF_VAULT_NAME} --query value -o tsv)
```

### Terraform環境変数

Terraformが自動でAzureと連携するように環境変数を指定する。

```bash
SUBSCRIPTION_NAME=<your-subsciption>
SUBSCRIPTION_ID=$(az account list --query "[?name=='${SUBSCRIPTION_NAME}'].id" -o tsv)

# Terraform用のServicePrincipal作成
TERRAFORM_SP_PASSWORD=$(az ad sp create-for-rbac --name=terraform --role="Contributor" --scopes="/subscriptions/${SUBSCRIPTION_ID}" --query "password" -o tsv)
TERRAFORM_SP_ID=$(az ad sp list --query "[?displayName=='terraform'].appId" --output tsv)

# Terrformが利用する環境変数指定
export ARM_SUBSCRIPTION_ID=$SUBSCRIPTION_ID
export ARM_CLIENT_ID=$TERRAFORM_SP_ID
export ARM_CLIENT_SECRET=$TERRAFORM_SP_PASSWORD
export ARM_TENANT_ID=$(az account list --query "[?name=='${SUBSCRIPTION_NAME}'].tenantId" -o tsv)
```

### Terraform init

TerraformのStateを初期化する。

```bash
cd $PROJECT_HOME/terraform

cat << EOF > backend.hcl
resource_group_name   = "${TF_RG_NAME}"
storage_account_name  = "${TF_STORAGE_ACCOUNT_NAME}"
container_name        = "${TF_CONTAINER_NAME}"
key                   = "dev.tfstate"
EOF

terraform init -backend-config backend.hcl
```

### AKS用の ServicePrincipal 作成

AKSが関連リソースを作成するためのServicePrincipalを作成する。

```bash
AKS_SP_PASSWORD=$(az ad sp create-for-rbac --name=aks --role="Contributor" --scopes="/subscriptions/${SUBSCRIPTION_ID}" --query "password" -o tsv)
AKS_SP_ID=$(az ad sp list --query "[?displayName=='aks'].appId" --output tsv)
```

### Azureリソース作成

```bash
cat << EOF > terraform.tfvars
k8s_vm_count      = 2
k8s_client_id     = "${AKS_SP_ID}"
k8s_client_secret = "${AKS_SP_PASSWORD}"
EOF
terraform apply

# デフォルトでkubectlが利用するkubeconfigを変更
export KUBECONFIG=$HOME/.kube/aksconfig
echo "$(terraform output kube_config)" > $KUBECONFIG

kubectl cluster-info

# ACRログインサーバーのURL
ACR_LOGIN_SVR=$(terraform output acr_login_server)
# Public IP
APP_PUBLIC_IP=$(terraform output public_ip)
# FQDN
APP_FQDN=$(terraform output public_ip_fqdn)
# Redis Access Key
REDIS_PASS=$(terraform output redis_primary_key)
# Application Insights Key
APP_INSIGHTS_KEY=$(terraform output app_insights_instrumentation_key)
# => 以下のkeyを書き換え
# kustomize/overlays/aks/github-service/appinsights-key_patch.yaml
# kustomize/overlays/aks/api-gateway/appinsights-key_patch.yaml
# repo-search-ui/src/main.js
```

---

## アプリビルド

各アプリケーションのコンテナイメージのビルドとACR(プライベートレジストリ)へのPushを行う。

```bash
cd $PROJECT_HOME

# コンテナイメージビルド
docker build -t $ACR_LOGIN_SVR/github-service:v1 ./github-service
docker build -t $ACR_LOGIN_SVR/api-gateway:v1 ./api-gateway
docker build -t $ACR_LOGIN_SVR/repo-search-ui:v1 -f ./repo-search-ui/Dockerfile.multi-env --build-arg TARGET=prod ./repo-search-ui

# ACRにイメージプッシュ
az acr login --name $ACR_REGISTRY
docker push $ACR_LOGIN_SVR/github-service:v1
docker push $ACR_LOGIN_SVR/api-gateway:v1
docker push $ACR_LOGIN_SVR/repo-search-ui:v1
```

## アプリデプロイ

AKSに対してアプリをデプロイする。リソースマニフェストはKustomizeのOverlayで構成する。

```bash
# Helm
cat << EOF > tiller-rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tiller
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
 name: tiller
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: tiller
    namespace: kube-system
EOF
kubectl apply -f tiller-rbac.yaml
helm init --service-account tiller --wait
# Nginx Ingress controller
helm upgrade nginx-ingress --install stable/nginx-ingress \
   --set controller.service.loadBalancerIP="${APP_PUBLIC_IP}" \
   --set nodeSelector."beta.kubernetes.io/os"=linux \
   --wait
# check external ip
kubectl get svc -l app=nginx-ingress

cd $PROJECT_HOME/kustomize
# github-apiアクセスするためgithubのアカウント
GITHUB_USER=<your-github-userid>
GITHUB_PASSWORD=<your-github-password>
mkdir -p overlays/aks/.env
echo -n "$GITHUB_USER" > overlays/aks/.env/github-user
echo -n "$GITHUB_PASSWORD" > overlays/aks/.env/github-pass

# AzureからRedisのパスワードを取得
echo -n $REDIS_PASS > overlays/aks/.env/redis-pass

# アプリケーションのデプロイ
kubectl apply -k overlays/aks

# 全てのPodがRunningしたらブラウザでアクセス
open http://$APP_FQDN
```

---

## Clean up

```bash
helm delete --purge nginx-ingress
terraform destroy

TERRAFORM_SP_ID=$(az ad sp list --query "[?displayName=='terraform'].appId" -o tsv)
az ad sp delete --id $TERRAFORM_SP_ID
AKS_SP_ID=$(az ad sp list --query "[?displayName=='aks'].appId" -o tsv)
az ad sp delete --id $AKS_SP_ID

az group delete -g $TF_RG_NAME --yes
unset KUBECONFIG
```
