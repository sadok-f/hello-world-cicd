#!/bin/bash

set -e

dev_cluster_name='helloworld-dev'
prod_cluster_name='helloworld-prod'

YELLOW='\033[1;33m'
PURPLE='\033[1;35m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

main() {
  check_required_tools minikube kubectl helm argocd
  start_cluster $dev_cluster_name
  start_cluster $prod_cluster_name
  printinfo "sleeping 30 seconds while waiting for ingress controller to boot up in dev cluster"
  sleep 30
  deploy_mysql $dev_cluster_name
  deploy_mysql $prod_cluster_name
  deploy_argocd
  print_links
}

start_cluster() {
  printinfo "Setting up minikube cluster: $1"
  minikube start \
    -p=$1 \
    --disk-size='10000mb' \
    --addons=ingress,ingress-dns \
    --embed-certs=true
  printinfo "Creating RBAC objects for helm in $1"
  kubectl apply -f ./minikube-manifest/rbac.yaml
}

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

# Deploy argocd chart to dev cluster
deploy_argocd() {
  printinfo "Deploying ArgoCD Chart to dev cluster"

  kubectl config use-context $dev_cluster_name
  argo_endpoint="argo.dev.$(minikube ip --profile=$dev_cluster_name).nip.io"

  helm repo add argo https://argoproj.github.io/argo-helm
  helm install argo-cd argo/argo-cd -f minikube-manifest/argocd.yaml \
    --set server.ingress.hosts[0]=$argo_endpoint \
    --set server.extraArg[0]="--insecure" || true
  
  printinfo "Wait until ArgoCD is up and running:"
  while [[ "$(curl -s -o /dev/null -w ''%{http_code}'' -k https://$argo_endpoint/)" != "200" ]]; do echo "https://$argo_endpoint not reachable, sleep 5 sec";sleep 5; done

  init_pwd=$(kubectl get pods -n default -l app.kubernetes.io/name=argocd-server -o name | cut -d'/' -f 2)
  argocd --insecure login $argo_endpoint --grpc-web --username=admin --password=$init_pwd
  argocd app create hello-world-cicd-dev \
    --repo https://github.com/sadok-f/hello-world-cicd \
    --path kustomize/base \
    --dest-server https://kubernetes.default.svc \
    --dest-namespace default \
    --sync-policy automated
  
  argocd cluster add $prod_cluster_name
  argocd app create hello-world-cicd-prod \
    --repo https://github.com/sadok-f/hello-world-cicd \
    --path kustomize/base \
    --dest-server https://$(minikube ip --profile=$prod_cluster_name):8443 \
    --dest-namespace default \
    --sync-policy automated
}

check_required_tools() {
  printinfo "running:"
  list_programs=$(echo "$*" | sort -u | tr "\n" " ")
  printinfo "verify $list_programs"
  programs_ok=1
  for prog in "$@"; do
    if [[ -z $(which "$prog") ]]; then
      printinfo "Tool $prog cannot be found on this machine"
      programs_ok=0
    fi
  done
  if [[ $programs_ok -eq 1 ]]; then
    printinfo "check required programs OK"
  fi
}

print_links() {
  kubectl config use-context $dev_cluster_name
  printinfo "Argo CD URL: ${BLUE} https://argo.dev.$(minikube ip --profile=$dev_cluster_name).nip.io \
              \n ${PURPLE} username: ${BLUE} admin \
              \n ${PURPLE} password: ${BLUE} $(kubectl get pods -n default -l app.kubernetes.io/name=argocd-server -o name | cut -d'/' -f 2)"
}

printinfo (){
  printf "${YELLOW}############################################################ \n"
  printf "${PURPLE}### INFO: $1 \n${NC}"
}

# Run main function
main

exit 0