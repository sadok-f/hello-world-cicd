# hello-world-cicd

Retrieves a string from a MYSQL database and returns it as an HTTP response.

## Required tools:
These tools need to be present on the system before running init script:

- [Kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
- [Minikube](https://kubernetes.io/docs/tasks/tools/install-minikube/)
- [Helm](https://helm.sh/docs/intro/install/)
- [ArgoCD](https://argoproj.github.io/argo-cd/cli_installation/)

## How to setup:

1. Clone this repo locally
2. Run the setup script like the following:

```sh
./minikube-init.sh
```

## Environment Variables for the NodeJs app
- DB_HOSTNAME
- DB_USERNAME
- DB_PASSWORD
- DB_NAME
