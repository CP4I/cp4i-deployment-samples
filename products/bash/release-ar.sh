#!/bin/bash
#******************************************************************************
# Licensed Materials - Property of IBM
# (c) Copyright IBM Corporation 2020. All Rights Reserved.
#
# Note to U.S. Government Users Restricted Rights:
# Use, duplication or disclosure restricted by GSA ADP Schedule
# Contract with IBM Corp.
#******************************************************************************

#******************************************************************************
# PREREQUISITES:
#   - Logged into cluster on the OC CLI (https://docs.openshift.com/container-platform/4.4/cli_reference/openshift_cli/getting-started-cli.html)
#
# PARAMETERS:
#   -n : <namespace> (string), Defaults to "cp4i"
#   -r : <release-name> (string), Defaults to "demo"
#
# USAGE:
#   With defaults values
#     ./release-ar.sh
#
#   Overriding the namespace and release-name
#     ./release-ar.sh -n cp4i-prod -r prod

function usage() {
  echo "Usage: $0 -n <namespace> -r <release-name> -a <assets storage class (file)> -c <couch storage class (block)>"
}

CURRENT_DIR=$(dirname $0)
source $CURRENT_DIR/utils.sh
namespace="cp4i"
release_name="demo"
assetDataVolume="cp4i-file-performance-gid"
couchVolume="ibmc-block-gold"

while getopts "n:r:a:c:" opt; do
  case ${opt} in
  n)
    namespace="$OPTARG"
    ;;
  r)
    release_name="$OPTARG"
    ;;
  a)
    assetDataVolume="$OPTARG"
    ;;
  c)
    couchVolume="$OPTARG"
    ;;
  \?)
    usage
    exit
    ;;
  esac
done

source $CURRENT_DIR/license-helper.sh
echo "[DEBUG] AR license: $(getARLicense $namespace)"

json=$(oc get configmap -n $namespace operator-info -o json 2> /dev/null)
if [[ $? == 0 ]]; then
  METADATA_NAME=$(echo $json | tr '\r\n' ' ' | jq -r '.data.METADATA_NAME')
  METADATA_UID=$(echo $json | tr '\r\n' ' ' | jq -r '.data.METADATA_UID')
fi

YAML=$(cat <<EOF
apiVersion: integration.ibm.com/v1beta1
kind: AssetRepository
metadata:
  name: ${release_name}
  namespace: ${namespace}
  $(if [[ ! -z ${METADATA_UID} && ! -z ${METADATA_NAME} ]]; then
  echo "ownerReferences:
    - apiVersion: integration.ibm.com/v1beta1
      kind: Demo
      name: ${METADATA_NAME}
      uid: ${METADATA_UID}"
  fi)
spec:
  designerAIFeatures:
    enabled: true
  license:
    accept: true
    license: $(getARLicense $namespace)
  replicas: 1
  storage:
    assetDataVolume:
      class: ${assetDataVolume}
    couchVolume:
      class: ${couchVolume}
  version: 2022.2.1
EOF)
OCApplyYAML "$namespace" "$YAML"
