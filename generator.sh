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


read -p "IP Adresses (public and private) of the API servers (separated by commas, no spaces!) " apiAddresses
cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname=127.0.0.1,10.32.0.1,kubernetes.default,${apiAddresses} \
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


read -p "Number of worker nodes " numWorkers
read -p "Name for worker nodes " workerName
# Generate certs for workers
echo 'Generating certs for workers...'
for i in `seq 0 $((numWorkers-1))`; do
  cat > ${workerName}-${i}-csr.json <<EOF
  {
    "CN": "system:node:${workerName}-${i}",
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
  workerId="${workerName}-${i}"
  read -p "External address of ${workerId} " externalIP
  read -p "Internal address of ${workerId} " internalIP
  cfssl gencert \
    -ca=ca.pem \
    -ca-key=ca-key.pem \
    -config=ca-config.json \
    -hostname=${workerId},${externalIP},${internalIP} \
    -profile=kubernetes \
    ${workerId}-csr.json | cfssljson -bare ${workerId}
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


