#!/bin/bash 

urls=(
    "https://github.com/tosin2013/sno-quickstarts/gitops/cluster-config/openshift-local-storage/operator/overlays/stable-4.14"
    "https://github.com/tosin2013/sno-quickstarts/gitops/cluster-config/openshift-local-storage/instance/overlays/demo-redhat"
    "https://github.com/tosin2013/sno-quickstarts/gitops/cluster-config/openshift-data-foundation-operator/instance/overlays/equinix-cnv"
)

for url in "${urls[@]}"
do
    oc apply -k "$url"
done
