#!/bin/bash

dev_cluster_name='dev'
prod_cluster_name='prod'

main() {
  check_required_tools minikube kubectl helm argocd
  start_cluster $dev_cluster_name
  start_cluster $prod_cluster_name
  dev_cluster_ip=$(minikube ip --profile=$dev_cluster_name)
  echo "Setup: sleeping 30 seconds while waiting for ingress controller to boot up in dev cluster"
  sleep 30
  deploy_argocd
  deploy_mysql $dev_cluster_name
  deploy_mysql $prod_cluster_name
  print_links
}

start_cluster() {
  echo "Setup: setting up $1"
  minikube start \
    -p=$1 \
    --driver=virtualbox \
    --disk-size='10000mb' \
    --addons=ingress,ingress-dns \
    --embed-certs=true
  echo "Setup: creating RBAC objects for helm in $1"
  kubectl apply -f ./minikube-manifest/rbac.yaml
}

deploy_mysql(){
  kubectl config use-context $1
  kubectl apply -f minikube-manifest/mysql-config-maps-$1.yml
  helm repo add bitnami https://charts.bitnami.com/bitnami
  helm install mysql bitnami/mysql \
    --set auth.database=hello-world-db \
    --set initdbScriptsConfigMap=configmapscripts

  kubectl delete secret db-secret
  db_password=$(kubectl get secret --namespace default mysql -o jsonpath="{.data.mysql-root-password}" | base64 --decode)
  kubectl create secret generic db-secret \
                                       --from-literal=db_username=root \
                                       --from-literal=db_password=$db_password
}

# Deploy argocd chart to dev cluster
deploy_argocd() {
  
  kubectl config use-context $dev_cluster_name
  argo_endpoint="argo.dev.$(minikube ip --profile=$dev_cluster_name).nip.io"

  echo "Setup: deploying ArgoCD Chart to dev cluster"
  helm repo add argo https://argoproj.github.io/argo-helm
  helm install argo-cd argo/argo-cd -f minikube-manifest/argocd.yaml \
    --set server.ingress.hosts[0]=$argo_endpoint \
    --set server.extraArg[0]="--insecure"
  
  echo "Wait until ArgoCD is up and running:"
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
  echo "Setup: running:"
  list_programs=$(echo "$*" | sort -u | tr "\n" " ")
  echo "Setup: verify $list_programs"
  programs_ok=1
  for prog in "$@"; do
    if [[ -z $(which "$prog") ]]; then
      echo "Tool $prog cannot be found on this machine"
      programs_ok=0
    fi
  done
  if [[ $programs_ok -eq 1 ]]; then
    echo "Setup: check required programs OK"
  fi
}

print_links() {
  kubectl config use-context $dev_cluster_name
  echo "##############################################"
  echo "Argo CD URL: https://argo.dev.$(minikube ip --profile=$dev_cluster_name).nip.io"
  echo "Crdentials:"
  echo "username: admin"
  echo "password: $(kubectl get pods -n default -l app.kubernetes.io/name=argocd-server -o name | cut -d'/' -f 2)"
  echo "##############################################"
}

# Run main function
main

exit 0