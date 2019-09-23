#!/bin/bash

set -euo pipefail

OUTPUT_DIR=output
# Create output directory
echo 'Creating output directory'
mkdir -p $OUTPUT_DIR

# Generate CA
echo 'Generating CA...'
cat > $OUTPUT_DIR/ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "kubernetes": {
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "expiry": "8760h"
      }
    }
  }
}
EOF

read -p "CN: " cacn
read -p "C: " c
read -p "L: " l
read -p "O: " o
read -p "OU: " ou
read -p "ST: " st

cat > $OUTPUT_DIR/ca-csr.json <<EOF
{
  "CN": "$cacn",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "$c",
      "L": "$l",
      "O": "$o",
      "OU": "$ou",
      "ST": "$st"
    }
  ]
}
EOF

cfssl gencert -initca $OUTPUT_DIR/ca-csr.json | cfssljson -bare $OUTPUT_DIR/ca

# Generate server cert for API-Servers
echo 'Generating server cert for API servers...'

cat > $OUTPUT_DIR/kubernetes-csr.json <<EOF
{
  "CN": "kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "$c",
      "L": "$l",
      "O": "$o",
      "OU": "$ou",
      "ST": "$st"
    }
  ]
}
EOF


read -p "IP adresses (public and private) of the API servers (separated by commas) " apiAddresses

sanitizedApiAddresses=$(echo $apiAddresses | tr -d [:blank:])
echo $sanitizedApiAddresses

cfssl gencert \
  -ca=$OUTPUT_DIR/ca.pem \
  -ca-key=$OUTPUT_DIR/ca-key.pem \
  -config=$OUTPUT_DIR/ca-config.json \
  -hostname=127.0.0.1,10.32.0.1,kubernetes.default,${sanitizedApiAddresses} \
  -profile=kubernetes \
  $OUTPUT_DIR/kubernetes-csr.json | cfssljson -bare $OUTPUT_DIR/kubernetes

# Generate cert for kube-scheduler
echo 'Generating cert for kube-scheduler...'
cat > $OUTPUT_DIR/kube-scheduler-csr.json <<EOF
{
  "CN": "system:kube-scheduler",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "$c",
      "L": "$l",
      "O": "system:kube-scheduler",
      "OU": "$ou",
      "ST": "$st"
    }
  ]
}
EOF

cfssl gencert \
  -ca=$OUTPUT_DIR/ca.pem \
  -ca-key=$OUTPUT_DIR/ca-key.pem \
  -config=$OUTPUT_DIR/ca-config.json \
  -profile=kubernetes \
  $OUTPUT_DIR/kube-scheduler-csr.json | cfssljson -bare $OUTPUT_DIR/kube-scheduler

# Generate cert for controller-manager
echo 'Generating cert for controller-manager...'
cat > $OUTPUT_DIR/kube-controller-manager-csr.json <<EOF
{
  "CN": "system:kube-controller-manager",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "$c",
      "L": "$l",
      "O": "system:kube-controller-manager",
      "OU": "$ou",
      "ST": "$st"
    }
  ]
}
EOF

cfssl gencert \
  -ca=$OUTPUT_DIR/ca.pem \
  -ca-key=$OUTPUT_DIR/ca-key.pem \
  -config=$OUTPUT_DIR/ca-config.json \
  -profile=kubernetes \
  $OUTPUT_DIR/kube-controller-manager-csr.json | cfssljson -bare $OUTPUT_DIR/kube-controller-manager


read -p "Number of worker nodes " numWorkers
read -p "Name prefix for worker nodes (the generated names will be '\$prefix-0 ... \$prefix-\$n-1', where \$n is the number of worker nodes) " workerNamePrefix
# Generate certs for workers
echo 'Generating certs for workers...'
for i in `seq 0 $((numWorkers-1))`; do
  cat > $OUTPUT_DIR/${workerNamePrefix}-${i}-csr.json <<EOF
  {
    "CN": "system:node:${workerNamePrefix}-${i}",
    "key": {
      "algo": "rsa",
      "size": 2048
    },
    "names": [
      {
        "C": "$c",
        "L": "$l",
        "O": "system:nodes",
        "OU": "$ou",
        "ST": "$st"
      }
    ]
  }
EOF
done

for i in `seq 0 $((numWorkers-1))`; do
  workerId="${workerNamePrefix}-${i}"
  read -p "Internal address of ${workerId} " internalIP
  read -p "External address of ${workerId} " externalIP
  cfssl gencert \
    -ca=$OUTPUT_DIR/ca.pem \
    -ca-key=$OUTPUT_DIR/ca-key.pem \
    -config=$OUTPUT_DIR/ca-config.json \
    -hostname=${workerId},${externalIP},${internalIP} \
    -profile=kubernetes \
    $OUTPUT_DIR/${workerId}-csr.json | cfssljson -bare $OUTPUT_DIR/${workerId}
done

# Generate cert for kube-proxy
echo 'Generating cert for kube-proxy...'
cat > $OUTPUT_DIR/kube-proxy-csr.json <<EOF
{
  "CN": "system:kube-proxy",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "$c",
      "L": "$l",
      "O": "system:node-proxier",
      "OU": "$ou",
      "ST": "$st"
    }
  ]
}
EOF

cfssl gencert \
  -ca=$OUTPUT_DIR/ca.pem \
  -ca-key=$OUTPUT_DIR/ca-key.pem \
  -config=$OUTPUT_DIR/ca-config.json \
  -profile=kubernetes \
  $OUTPUT_DIR/kube-proxy-csr.json | cfssljson -bare $OUTPUT_DIR/kube-proxy

# Generate certs for service accounts
echo 'Generating cert for service accounts...'
cat > $OUTPUT_DIR/service-account-csr.json <<EOF
{
  "CN": "service-accounts",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "$c",
      "L": "$l",
      "O": "$o",
      "OU": "$ou",
      "ST": "$st"
    }
  ]
}
EOF

cfssl gencert \
  -ca=$OUTPUT_DIR/ca.pem \
  -ca-key=$OUTPUT_DIR/ca-key.pem \
  -config=$OUTPUT_DIR/ca-config.json \
  -profile=kubernetes \
  $OUTPUT_DIR/service-account-csr.json | cfssljson -bare $OUTPUT_DIR/service-account

# Generate client cert for admin account
echo 'Generating cert for admin account...'
cat > $OUTPUT_DIR/admin-csr.json <<EOF
{
  "CN": "admin",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "$c",
      "L": "$l",
      "O": "system:masters",
      "OU": "$ou",
      "ST": "$st"
    }
  ]
}
EOF

cfssl gencert \
  -ca=$OUTPUT_DIR/ca.pem \
  -ca-key=$OUTPUT_DIR/ca-key.pem \
  -config=$OUTPUT_DIR/ca-config.json \
  -profile=kubernetes \
  $OUTPUT_DIR/admin-csr.json | cfssljson -bare $OUTPUT_DIR/admin


