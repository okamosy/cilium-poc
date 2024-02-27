alias ba := build_all
alias ca := clusters_all
alias ha := helm_all

build_all:
  #!/usr/bin/env bash
  set -euxo pipefail

  just clusters_all
  just helm_all
  just mesh "false"

clusters_all:
  #!/usr/bin/env bash
  set -euxo pipefail

  for file in ./clusters/*.yaml; do
    name=$(basename $file .yaml)
    index=$(echo $name | cut -d "-" -f 2)
    index=$((index))

    if [[ $index -eq 4 ]]; then
      continue
    fi

    just cluster $name
  done

cluster name:
  kind create cluster --config clusters/{{name}}.yaml --name {{name}}

helm_all:
  #!/usr/bin/env bash
  set -euxo pipefail

  for file in ./clusters/*.yaml; do
    name=$(basename $file .yaml)
    index=$(echo $name | cut -d "-" -f 2)
    index=$((index))

    if [[ $index -eq 4 ]]; then
      continue
    fi

    just helm $name $index
  done

helm name id:
  #!/usr/bin/env bash
  set -uxo pipefail

  helm repo add cilium https://helm.cilium.io/

  if [[ {{id}} -ne 1 ]]; then
    kubectl --context kind-cilium-01 get secret -n kube-system cilium-ca -o yaml | \
    kubectl --context kind-{{name}} create -f -
  fi

  helm upgrade -i cilium cilium/cilium --version 1.15.1 \
    --kube-context kind-{{name}} \
    --namespace kube-system \
    --set cluster.id={{id}} \
    --set cluster.name={{name}} \
    --set clustermesh.useAPIServer=true \
    --set clustermesh.apiserver.service.type=NodePort \
    --set hubble.relay.enabled=true \
    --set hubble.ui.enabled=true \
    --set image.pullPolicy=IfNotPresent \
    --set ipam.mode=kubernetes

  cilium status --context kind-{{name}} --wait

mesh full="true":
  #!/usr/bin/env bash
  set -uexo pipefail

  args=()
  for file in ./clusters/*.yaml; do
    name=$(basename $file .yaml)
    index=$(echo $name | cut -d "-" -f 2)
    index=$((index - 1))

    if [[ {{full}} -eq "false" ]] && [[ $index -eq 3 ]]; then
      continue
    fi

    ip=$(kubectl get pod --context kind-$name -n kube-system -l component=kube-apiserver -o 'jsonpath={.items[0].status.podIP}')
    args+=(
      --set clustermesh.config.clusters[$index].name=$name
      --set clustermesh.config.clusters[$index].ips[0]=$ip
      --set clustermesh.config.clusters[$index].port=32379
    )
  done

  for file in ./clusters/*.yaml; do
    name=$(basename $file .yaml)
    index=$(echo $name | cut -d "-" -f 2)
    index=$((index))

    if [[ {{full}} -eq "false" ]] && [[ $index -eq 4 ]]; then
      continue
    fi

    helm upgrade cilium cilium/cilium --version 1.15.1 \
      --kube-context kind-$name \
      -n kube-system \
      --reuse-values \
      --set clustermesh.config.enabled=true \
      "${args[@]}"
  done

delete:
  kind delete clusters -A
