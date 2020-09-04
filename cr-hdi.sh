#!/bin/bash
#set -o nounset

BASE_DIR=$(cd $(dirname $0); pwd -L)

echo $BASE_DIR
display_usage() { 
    echo "
Usage:
    $(basename "$0") [--help or -h] <prefix> <location>
Description:
    Creates Azure resource group
Arguments:
    prefix:         prefix for your resource group (name <prefix>-hdi-rg)
    location:       region of your resource group
    --help or -h:   displays this help"

}

# check whether user had supplied -h or --help . If yes display usage 
if [[ ( ${1:-x} == "--help") ||  ${1:-x} == "-h" ]] 
then 
    display_usage
    exit 0
fi 

# Check the numbers of arguments
if [  $# -lt 3 ] 
then 
    echo "Not enough arguments!"  >&2
    display_usage
    exit 1
fi 

if [  $# -gt 3 ] 
then 
    echo "Too many arguments!"  >&2
    display_usage
    exit 1
fi 

hdi_rg="$1-hdinsightrg"
region=$2

#create resource group
result=$(az group exists -o json -g "$hdi_rg")
if [[ "$result" == "false"  ]]; then
   az group create --name ${hdi_rg} --location "${region}"
else
   echo "resource group exists"
fi

#create managed identity
hdi_mi="$1-hdinsightId"

chk_existing_id=$(az identity show --resource-group $hdi_rg --name $hdi_mi -o json | jq -r .name) 
if [[ $? -eq 0 && "$chk_existing_id" == "$hdi_mi" ]]; then
   echo "managed identity exists"
else
   az identity create -g $hdi_rg -n $hdi_mi 
fi

#create storage 
hdi_storage="$1hdinsightsan"

result=$(az storage account check-name -o json -n "$hdi_storage" | jq -r .nameAvailable | grep "false")
if [[ ${result} -eq "true" ]]; then
   az group deployment create \
     --resource-group ${hdi_rg} \
     --template-file "${BASE_DIR}/adls_gen2.json" \
     --parameters storageAccountName="$hdi_storage" location="$region" 
else
   echo "storage exists"
fi

#create sqlserver
hdi_metastore="$1-hdinsight-metastore"
azureservicesip="0.0.0.0"
login=hive
password="$3"

result=$(az sql server list --resource-group "$hdi_rg" | jq '.[] | select(.name=="$hdi_metastore") | .state')
if [[ ${result:=x} -eq "x" ]]; then
    az sql server create --name $hdi_metastore --resource-group "$hdi_rg" --location "$region" --admin-user $login --admin-password $password
    if [[ $? -ne 0 ]]; then
       echo "Hive metastore deployment failed! Check the error message and try again." 
       exit 1
    else
       az sql server firewall-rule create --resource-group $hdi_rg --server $hdi_metastore -n AllowYourIp --start-ip-address $azureservicesip --end-ip-address $azureservicesip
    fi
elif [[ "$result" -ne "Ready" ]]; then
    echo "Hive metastore exists but is not Ready! Restore the state and try again."
    exit 1
else
    echo "Hive metastore exists"
fi



