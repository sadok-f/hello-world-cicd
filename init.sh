#!/bin/bash

set -e

# Color constants
YELLOW='\033[0;33m'
PURPLE='\033[1;35m'
GREEN='\033[1;32m'
RED='\033[1;31m'
LIGHT_YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Clusters name
dev_cluster_name='helloworld-dev'
prod_cluster_name='helloworld-prod'

# To start a minikube cluster
start_cluster() {
  printinfo "Setting up minikube cluster: $1"
  minikube start \
    -p=$1 \
    --disk-size='10000mb' \
    --addons=ingress
  printinfo "Creating RBAC objects for helm in $1"
  kubectl apply -f ./minikube-manifest/helm-rbac.yml
}

# To deploy a Mysql instance via Helm chart
deploy_mysql(){
  printinfo "Deploying Mysql Chart to $1 cluster"

  kubectl config use-context $1
  if [[ $1 == *"dev"* ]]; then
    config_map_name="mysql-config-maps-dev"
  else
    config_map_name="mysql-config-maps-prod"
  fi
  kubectl apply -f minikube-manifest/$config_map_name.yml
  helm repo add bitnami https://charts.bitnami.com/bitnami
  helm install mysql bitnami/mysql \
    --set auth.database=hello-world-db \
    --set initdbScriptsConfigMap=configmapscripts  || true

  kubectl delete secret db-secret || true
  db_password=$(kubectl get secret --namespace default mysql -o jsonpath="{.data.mysql-root-password}" | base64 --decode)
  kubectl create secret generic db-secret \
                                       --from-literal=db_username=root \
                                       --from-literal=db_password=$db_password
}

# Deploy ArgoCD chart to dev cluster
deploy_argocd() {
  printinfo "Deploying ArgoCD Chart to dev cluster"

  kubectl config use-context $dev_cluster_name
  argo_endpoint="argo.dev.$(minikube ip --profile=$dev_cluster_name).nip.io"

  helm repo add argo https://argoproj.github.io/argo-helm
  helm install argo-cd argo/argo-cd -f minikube-manifest/argocd.yml \
    --set server.ingress.hosts[0]=$argo_endpoint \
    --set server.extraArg[0]="--insecure" || true
  
  printinfo "Wait until Argo CD is up and running:"
  while [[ "$(curl -s -o /dev/null -w ''%{http_code}'' -k https://$argo_endpoint/)" != "200" ]]; do echo "https://$argo_endpoint not reachable, sleep 5 sec";sleep 5; done
}

# Configure ArgoCD
configure_argocd_apps(){
  # ArgoCD endpoint
  argo_endpoint="argo.dev.$(minikube ip --profile=$dev_cluster_name).nip.io"

  # Get the inital password
  init_pwd=$(kubectl get pods -n default -l app.kubernetes.io/name=argocd-server -o name | cut -d'/' -f 2)

  # Login via cli
  argocd --insecure login $argo_endpoint --grpc-web --username=admin --password=$init_pwd

  # Create Hello-world-cicd app in dev cluster
  argocd app create hello-world-cicd-dev \
    --repo https://github.com/sadok-f/hello-world-cicd \
    --path kustomize/base \
    --dest-server https://kubernetes.default.svc \
    --dest-namespace default \
    --sync-policy automated
  
  # Add Prod Cluster
  argocd cluster add $prod_cluster_name

  # Create Hello-world-cicd app in prod cluster
  argocd app create hello-world-cicd-prod \
    --repo https://github.com/sadok-f/hello-world-cicd \
    --path kustomize/overlays/prod \
    --dest-server https://$(minikube ip --profile=$prod_cluster_name):8443 \
    --dest-namespace default \
    --sync-policy automated
}

# Check required tools
check_required_tools() {
  list_programs=$(echo "$*" | sort -u | tr "\n" " ")
  printinfo "Check if the following tools are installed: $list_programs"
  for prog in "$@"; do
    command -v $prog >/dev/null 2>&1 || { printf >&2 "${RED}*** $prog is not installed.  Aborting.${NC}"; exit 1; }
  done
  printinfo  "Check required tools OK"
}

# Print ArgoCD Access
print_argocd_access() {
  kubectl config use-context $dev_cluster_name
  printinfo "Argo CD URL: ${GREEN} https://argo.dev.$(minikube ip --profile=$dev_cluster_name).nip.io \
              \n ${PURPLE} username: ${GREEN} admin \
              \n ${PURPLE} initial password: ${GREEN} $(kubectl get pods -n default -l app.kubernetes.io/name=argocd-server -o name | cut -d'/' -f 2)"
}

# Format output
printinfo (){
  printf "${YELLOW}###################################################################################################### \n"
  printf "${LIGHT_YELLOW}### INFO: ${PURPLE} $1 \n${NC}"
}

# Check required tools
check_required_tools minikube kubectl helm argocd

# Starting up the Dev and Prod clusters
start_cluster $dev_cluster_name
start_cluster $prod_cluster_name

# Sleeping for 30 sec
printinfo "Sleeping 30 seconds while waiting for ingress controller to boot up in dev cluster"
sleep 30

# Deploying Mysql to Dev and Prod Clusters
deploy_mysql $dev_cluster_name
deploy_mysql $prod_cluster_name

# Deploying & Configuring Argo CD
deploy_argocd
configure_argocd_apps

# Printing Argo CD access Credentials
print_argocd_access

exit 0