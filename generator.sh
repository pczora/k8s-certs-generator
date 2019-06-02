#!/bin/bash

set -euo pipefail

# Generate CA
echo 'Generating CA...'
cat > ca-config.json <<EOF
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

cat > ca-csr.json <<EOF
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

cfssl gencert -initca ca-csr.json | cfssljson -bare ca

# Generate server cert for API-Servers
echo 'Generating server cert for API servers...'

cat > kubernetes-csr.json <<EOF
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

# TODO: insert correct addresses
API_SERVER_ADDRESSES=""

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname=127.0.0.1,10.32.0.1,kubernetes.default,$API_SERVER_ADDRESSES \
  -profile=kubernetes \
  kubernetes-csr.json | cfssljson -bare kubernetes

# Generate cert for kube-scheduler
echo 'Generating cert for kube-scheduler...'
cat > kube-scheduler-csr.json <<EOF
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
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  kube-scheduler-csr.json | cfssljson -bare kube-scheduler

# Generate cert for controller-manager
echo 'Generating cert for controller-manager...'
cat > kube-controller-manager-csr.json <<EOF
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
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  kube-controller-manager-csr.json | cfssljson -bare kube-controller-manager

# Generate certs for workers
echo 'Generating certs for workers...'
for instance in worker-0 worker-1 worker-2; do
  cat > ${instance}-csr.json <<EOF
  {
    "CN": "system:node:${instance}",
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

#TODO: Insert correct addresses
WORKER_EXTERNAL_IPS=(1.2.3.4 4.3.2.1 3.3.3.3)
WORKER_INTERNAL_IPS=(10.0.0.10 10.0.0.11 10.0.0.12)

for i in 0 1 2; do
  EXTERNAL_IP=${WORKER_EXTERNAL_IPS[${i}]}
  INTERNAL_IP=${WORKER_INTERNAL_IPS[${i}]}

  cfssl gencert \
    -ca=ca.pem \
    -ca-key=ca-key.pem \
    -config=ca-config.json \
    -hostname=worker-${i},${EXTERNAL_IP},${INTERNAL_IP} \
    -profile=kubernetes \
    worker-${i}-csr.json | cfssljson -bare worker-${i}
done

# Generate cert for kube-proxy
echo 'Generating cert for kube-proxy...'
cat > kube-proxy-csr.json <<EOF
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
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  kube-proxy-csr.json | cfssljson -bare kube-proxy

# Generate certs for service accounts
echo 'Generating cert for service accounts...'
cat > service-account-csr.json <<EOF
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
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  service-account-csr.json | cfssljson -bare service-account

# Generate client cert for admin account
echo 'Generating cert for admin account...'
cat > admin-csr.json <<EOF
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
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  admin-csr.json | cfssljson -bare admin


