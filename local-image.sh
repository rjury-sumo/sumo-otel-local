#!/bin/bash

podman pull kindest/node:v1.32.2@sha256:f226345927d7e348497136874b6d207e0b32cc52154ad8323129352923a3142f

podman save -o kind-node-v1.32.2.tar kindest/node:v1.32.2@sha256:f226345927d7e348497136874b6d207e0b32cc52154ad8323129352923a3142f

podman load -i kind-node-v1.32.2.tar

podman image tag kindest/node:v1.32.2@sha256:f226345927d7e348497136874b6d207e0b32cc52154ad8323129352923a3142f kindest/node:v1.32.2
podman image ls

kind create cluster --name ${CLUSTER_NAME} --image kindest/node:v1.32.2
