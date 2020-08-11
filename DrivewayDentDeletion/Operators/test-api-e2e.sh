#!/bin/bash
#******************************************************************************
# Licensed Materials - Property of IBM
# (c) Copyright IBM Corporation 2019. All Rights Reserved.
#
# Note to U.S. Government Users Restricted Rights:
# Use, duplication or disclosure restricted by GSA ADP Schedule
# Contract with IBM Corp.
#******************************************************************************

# PREREQUISITES:
#   - Logged into cluster on the OC CLI (https://docs.openshift.com/container-platform/4.4/cli_reference/openshift_cli/getting-started-cli.html)
#
# PARAMETERS:
#   -n : <namespace> (string), Defaults to "cp4i"
#   -t : <imageTag> (string), Default is empty
#
#   With defaults values
#     ./test-api-e2e.sh -n <namesapce>

function usage {
    echo "Usage: $0 -n <namespace>"
}

namespace="cp4i"
os_sed_flag=""

if [[ $(uname) == Darwin ]]; then
  os_sed_flag="-e"
fi

while getopts "n:t:c" opt; do
  case ${opt} in
    n ) namespace="$OPTARG"
      ;;
    \? ) usage; exit
      ;;
  esac
done

# -------------------------------------- INSTALL JQ ---------------------------------------------------------------------

echo -e "\n----------------------------------------------------------------------------------------------------------------------------------------------------------\n"

echo -e "\nINFO: Checking if jq is pre-installed..."
jqInstalled=false
jqVersionCheck=$(jq --version)

if [ $? -ne 0 ]; then
  jqInstalled=false
else
  jqInstalled=true
fi

if [[ "$jqInstalled" == "false" ]]; then
  echo "INFO: JQ is not installed, installing jq..."
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "INFO: Installing on linux"
    wget -O jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
    chmod +x ./jq
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    echo "INFO: Installing on MAC"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
    brew install jq
  fi
fi

echo -e "\nINFO: Installed JQ version is $(./jq --version)"

echo -e "\n----------------------------------------------------------------------------------------------------------------------------------------------------------\n"

# -------------------------------------- TEST E2E API ------------------------------------------

export HOST=http://$(oc get routes -n ${namespace} | grep ace-api-int-srv-http | grep -v ace-api-int-srv-https | awk '{print $2}')/drivewayrepair
echo "INFO: Host: ${HOST}"

DB_NAME=$(echo $namespace | sed 's/-/_/g')
DB_NAME=db_${DB_NAME}
echo "INFO: Database name is: '${DB_NAME}'"

echo -e "\nINFO: Testing E2E API now..."

# ------- Post to the database -------
post_response=$(curl -s -w " %{http_code}" -X POST ${HOST}/quote -d "{\"Name\": \"Mickey Mouse\",\"EMail\": \"MickeyMouse@us.ibm.com\",\"Address\": \"30DisneyLand\",\"USState\": \"FL\",\"LicensePlate\": \"MMM123\",\"DentLocations\": [{\"PanelType\": \"Door\",\"NumberOfDents\": 2},{\"PanelType\": \"Fender\",\"NumberOfDents\": 1}]}")
post_response_code=$(echo "${post_response##* }")

if [ "$post_response_code" == "200" ]; then
  # The usage of sed here is to prevent an error caused between the -w flag of curl and jq not interacting well
  quote_id=$(echo "$post_response" | ./jq '.' | sed $os_sed_flag '$ d' | ./jq '.QuoteID')

  echo -e "INFO: SUCCESS - POST with response code: ${post_response_code}, QuoteID: ${quote_id}, and Response Body:\n"
  # The usage of sed here is to prevent an error caused between the -w flag of curl and jq not interacting well
  echo ${post_response} | ./jq '.' | sed $os_sed_flag '$ d'

  echo -e "\n----------------------------------------------------------------------------------------------------------------------------------------------------------"

  # ------- Get from the database -------
  echo -e "\nINFO: GET request..."
  get_response=$(curl -s -w " %{http_code}" -X GET ${HOST}/quote?QuoteID=${quote_id})
  get_response_code=$(echo "${get_response##* }")

  if [ "$get_response_code" == "200" ]; then
    echo -e "INFO: SUCCESS - GET with response code: ${get_response_code}, and Response Body:\n"
    # The usage of sed here is to prevent an error caused between the -w flag of curl and jq not interacting well
    echo ${get_response} | ./jq '.' | sed $os_sed_flag '$ d'
  else
    echo "ERROR: FAILED - Error code: ${get_response_code}"
    echo -e "\n----------------------------------------------------------------------------------------------------------------------------------------------------------\n"
    exit 1
  fi

  temp=$(oc auth can-i get pod -n postgres)
  echo $temp

  echo -e "\n----------------------------------------------------------------------------------------------------------------------------------------------------------"
  # ------- Delete from the database -------
  echo -e "\nINFO: Deleting row from database '${DB_NAME}'..."
  echo "INFO: Deleting the row with quote id $quote_id from the database"
  oc exec -n postgres -it $(oc get pod -n postgres -l name=postgresql -o jsonpath='{.items[].metadata.name}') \
    -- psql -U admin -d ${DB_NAME} -c \
    "DELETE FROM quotes WHERE quotes.quoteid=${quote_id};"

  echo -e "\n----------------------------------------------------------------------------------------------------------------------------------------------------------"

  #  ------- Get row to confirm deletion -------
  echo -e "\nINFO: Select and print the row from database '${DB_NAME}' with id '$quote_id' to confirm deletion"
  oc exec -n postgres -it $(oc get pod -n postgres -l name=postgresql -o jsonpath='{.items[].metadata.name}') \
    -- psql -U admin -d ${DB_NAME} -c \
    "SELECT * FROM quotes WHERE quotes.quoteid=${quote_id};"
  
else
  # Failure catch during POST
  echo "ERROR: Post request failed - Error code: ${post_response_code}"
  exit 1
fi
echo -e "----------------------------------------------------------------------------------------------------------------------------------------------------------"
