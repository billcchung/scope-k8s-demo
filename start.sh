#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

whitespace() {
  echo ""
  echo ""
  echo ""
}

kubernetes() {
  echo "Creating Kubernetes Cluster with Kind..."
  cat <<EOF | kind create cluster --name scope-k8s-demo --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30000
    hostPort: 30000
    protocol: TCP
  - containerPort: 30001
    hostPort: 30001
    protocol: TCP
  - containerPort: 30002
    hostPort: 30002
    protocol: TCP
  - containerPort: 30003
    hostPort: 30003
    protocol: TCP
  - containerPort: 30004
    hostPort: 30004
    protocol: TCP
EOF
  whitespace
}

scope() {
  echo "Installing scope"
  if [[ $1 == "cribl" ]]; then
    docker run -it --rm cribl/scope:0.6.0 \
      scope k8s --cribldest cribl-internal:10090 | kubectl apply -f -
  else
    docker run -it --rm cribl/scope:0.6.0 \
      scope k8s --metricdest tcp://telegraf:8125 --metricformat statsd --eventdest tcp://fluentd:10001 | kubectl apply -f -
  fi
  
  while [ $(kubectl get po | grep scope | grep Running | wc -l) == 0 ]; do
      echo "Waiting on scope..."
      sleep 5
  done

  kubectl label namespace default scope=enabled
}

elasticsearch() {
  echo "Installing Elasticsearch & Kibana..."
  kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
  helm repo add elastic https://helm.elastic.co
  helm install elasticsearch elastic/elasticsearch --values ${DIR}/elasticsearch.values.yml
  if [[ $1 == "cribl" ]]; then
    cd ${DIR}/cribl && kubectl create secret generic kibana-config --from-file=kibana.config.ndjson && cd -
  else
    cd ${DIR}/fluentd && kubectl create secret generic kibana-config --from-file=kibana.config.ndjson && cd -
  fi
  helm install kibana elastic/kibana --values ${DIR}/kibana.values.yml
}

fluentd() {
  echo "Installing Fluentd..."
  kubectl apply -f fluentd.k8s.yml
  whitespace
}

prometheus() {
  echo "Installing Prometheus..."
  kubectl apply -f prometheus.k8s.yml
  whitespace
}

telegraf() {
  echo "Installing Telegraf..."
  kubectl apply -f telegraf.k8s.yml
  whitespace
}

grafana() {
  echo "Installing Grafana..."
  helm repo add grafana https://grafana.github.io/helm-charts
  helm install grafana grafana/grafana -f grafana.values.yml
}

allall() {
  kubernetes
  scope $1
  elasticsearch $1
  prometheus
  grafana
}

oss() {
  echo "Running OSS Demo..."
  allall "oss"
  fluentd
  telegraf
}

cribl() {
  echo "Running Cribl LogStream Demo..."
  allall "cribl"
  echo "Installing Cribl..."
  # helm repo add cribl https://criblio.github.io/helm-charts/
  # helm install logstream-master cribl/logstream-master -f ${DIR}/cribl.values.yml 
  kubectl apply -f ${DIR}/cribl-configs.k8s.yml
  kubectl apply -f ${DIR}/cribl.k8s.yml
}

if [[ $# -gt 0 ]]; then
  eval $1
else
  cribl
fi