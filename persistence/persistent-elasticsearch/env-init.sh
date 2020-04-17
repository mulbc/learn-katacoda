#!/bin/bash


export OCS_IMAGE=quay.io/mulbc/ocs-operator
export REGISTRY_NAMESPACE=mulbc
export IMAGE_TAG=katacoda

oc label "$(oc get no -o name)" cluster.ocs.openshift.io/openshift-storage=''

oc create ns openshift-storage
oc create ns local-storage
oc project openshift-storage

cat <<EOF | oc create -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-storage-group
  namespace: openshift-storage
spec:
  targetNamespaces:
  - openshift-storage
---
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ocs-catalogsource
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: quay.io/$REGISTRY_NAMESPACE/ocs-registry:$IMAGE_TAG
  displayName: OpenShift Container Storage
  publisher: Red Hat
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ocs-operator
  namespace: openshift-storage
spec:
  channel: alpha
  installPlanApproval: Automatic
  name: ocs-operator
  source: ocs-catalogsource
  sourceNamespace: openshift-marketplace
  startingCSV: ocs-operator.v4.3.0
EOF

# LSO install
cat <<EOF | oc create -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: local-storage-group
  namespace: local-storage
spec:
  targetNamespaces:
  - local-storage
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: local-storage-operator
  namespace: local-storage
spec:
  channel: "4.2"
  installPlanApproval: Automatic
  name: local-storage-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  startingCSV: local-storage-operator.4.2.23-202003090920
EOF

echo "let operators settle in" && sleep 1m

cat <<EOF | oc create -f -
apiVersion: local.storage.openshift.io/v1
kind: LocalVolume
metadata:
  name: local-block
  namespace: local-storage
spec:
  nodeSelector:
    nodeSelectorTerms:
    - matchExpressions:
        - key: cluster.ocs.openshift.io/openshift-storage
          operator: In
          values:
          - ""
  storageClassDevices:
    - storageClassName: localblock
      volumeMode: Block
      devicePaths:
        - /dev/vdb
        - /dev/vdc
        - /dev/vdd
EOF

seq 20 30 | xargs -n1 -P0 -t -I {} oc patch pv/pv00{} -p '{"metadata":{"annotations":{"volume.beta.kubernetes.io/storage-class": "localfile"}}}'

cat <<EOF | oc create -f -
apiVersion: ocs.openshift.io/v1
kind: StorageCluster
metadata:
  name: ocs-storagecluster
  namespace: openshift-storage
spec:
  manageNodes: false
  monPVCTemplate:
    spec:
      accessModes:
      - ReadWriteOnce
      resources:
        requests:
          storage: 1
      storageClassName: localfile
      volumeMode: Filesystem
  storageDeviceSets:
  - count: 1
    dataPVCTemplate:
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 1
        storageClassName: localblock
        volumeMode: Block
    name: ocs-deviceset
    placement: {}
    portable: false
    replica: 1
    resources: {}
EOF

curl -s https://raw.githubusercontent.com/rook/rook/release-1.1/cluster/examples/kubernetes/ceph/toolbox.yaml | sed 's/namespace: rook-ceph/namespace: openshift-storage/g'| oc apply -f -

watch oc -n openshift-storage get po,pvc
