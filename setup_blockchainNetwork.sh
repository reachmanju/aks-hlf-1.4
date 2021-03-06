#!/bin/bash

if [ -d "${PWD}/configFiles" ]; then
    KUBECONFIG_FOLDER=${PWD}/configFiles
else
    echo "Configuration files are not found."
    exit
fi


# Creating Persistant Volume
echo -e "\nCreating volume"
if [ "$(kubectl get pvc | grep shared-pvc | awk '{print $2}')" != "Bound" ]; then
    echo "The Persistant Volume does not seem to exist or is not bound"
    echo "Creating Persistant Volume"

    echo "Running: kubectl create -f ${KUBECONFIG_FOLDER}/createVolume.yaml"
    kubectl create -f ${KUBECONFIG_FOLDER}/createVolume.yaml
    sleep 5

    if [ "kubectl get pvc | grep shared-pvc | awk '{print $3}'" != "shared-pv" ]; then
        echo "Success creating Persistant Volume"
    else
        echo "Failed to create Persistant Volume"
    fi
else
    echo "The Persistant Volume exists, not creating again"
fi

# Copy the required files(configtx.yaml, cruypto-config.yaml, sample chaincode etc.) into volume
echo -e "\nCreating Copy artifacts job."
echo "Running: kubectl create -f ${KUBECONFIG_FOLDER}/copyArtifactsJob.yaml"
kubectl create -f ${KUBECONFIG_FOLDER}/copyArtifactsJob.yaml
sleep 10

pod=$(kubectl get pods --selector=job-name=copyartifacts --output=jsonpath={.items..metadata.name})
podSTATUS=$(kubectl get pods --selector=job-name=copyartifacts --output=jsonpath={.items..phase})

while [ "${podSTATUS}" != "Running" ]; do
    echo "Wating for container of copy artifact pod to run. Current status of ${pod} is ${podSTATUS}"
    sleep 5;
    if [ "${podSTATUS}" == "Error" ]; then
        echo "There is an error in copyartifacts job. Please check logs."
        exit 1
    fi
    podSTATUS=$(kubectl get pods --selector=job-name=copyartifacts --output=jsonpath={.items..phase})
done

echo -e "${pod} is now ${podSTATUS}"
echo -e "\nStarting to copy artifacts in persistent volume."

#fix for this script to work on icp and ICS
kubectl cp ./artifacts $pod:/shared/

echo "Waiting for 10 more seconds for copying artifacts to avoid any network delay"
sleep 15
JOBSTATUS=$(kubectl get jobs |grep "copyartifacts" |awk '{print $2}')
while [ "${JOBSTATUS}" != "1/1" ]; do
    echo "Waiting for copyartifacts job to complete"
    sleep 1;
    PODSTATUS=$(kubectl get pods | grep "copyartifacts" | awk '{print $3}')
        if [ "${PODSTATUS}" == "Error" ]; then
            echo "There is an error in copyartifacts job. Please check logs."
            exit 1
        fi
    JOBSTATUS=$(kubectl get jobs |grep "copyartifacts" |awk '{print $2}')
done
echo "Copy artifacts job completed"


# Generate Network artifacts using configtx.yaml and crypto-config.yaml
# Crypto Config
echo -e "\nGenerating the required artifacts for Blockchain network"

echo "Running: kubectl create -f ${KUBECONFIG_FOLDER}/cryptogen.yaml"
kubectl create -f ${KUBECONFIG_FOLDER}/cryptogen.yaml
sleep 25
JOBSTATUS=$(kubectl get jobs |grep cryptogen|awk '{print $2}')
while [ "${JOBSTATUS}" != "1/1" ]; do
    echo "Waiting for cryptogen job to complete"
    sleep 1;
    # UTILSLEFT=$(kubectl get pods | grep utils | awk '{print $2}')
    UTILSSTATUS=$(kubectl get pods | grep "cryptogen" | awk '{print $3}')
    if [ "${UTILSSTATUS}" == "Error" ]; then
            echo "There is an error in configtxgen job. Please check logs."
            exit 1
    fi
    # UTILSLEFT=$(kubectl get pods | grep cryptogen | awk '{print $2}')
    JOBSTATUS=$(kubectl get jobs |grep cryptogen|awk '{print $2}')
done

# Genesis Block
echo "Running: kubectl create -f ${KUBECONFIG_FOLDER}/configtxgen.yaml"
kubectl create -f ${KUBECONFIG_FOLDER}/configtxgen.yaml
sleep 15
JOBSTATUS=$(kubectl get jobs |grep configtxgen|awk '{print $2}')
while [ "${JOBSTATUS}" != "1/1" ]; do
    echo "Waiting for configtxgen job to complete"
    sleep 1;
    # UTILSLEFT=$(kubectl get pods | grep utils | awk '{print $2}')
    UTILSSTATUS=$(kubectl get pods | grep "configtxgen" | awk '{print $3}')
    if [ "${UTILSSTATUS}" == "Error" ]; then
            echo "There is an error in configtxgen job. Please check logs."
            exit 1
    fi
    # UTILSLEFT=$(kubectl get pods | grep configtxgen | awk '{print $2}')
    JOBSTATUS=$(kubectl get jobs |grep configtxgen|awk '{print $2}')
done

# Generate Channel Transaction
echo "Running: kubectl create -f ${KUBECONFIG_FOLDER}/create_channeltx.yaml"
kubectl create -f ${KUBECONFIG_FOLDER}/create_channeltx.yaml
sleep 25

JOBSTATUS=$(kubectl get jobs |grep createchanneltx|awk '{print $2}')
while [ "${JOBSTATUS}" != "1/1" ]; do
    echo "Waiting for createchanneltx job to complete"
    sleep 1;
    # UTILSLEFT=$(kubectl get pods | grep utils | awk '{print $2}')
    UTILSSTATUS=$(kubectl get pods | grep "createchanneltx" | awk '{print $3}')
    if [ "${UTILSSTATUS}" == "Error" ]; then
            echo "There is an error in createchanneltx job. Please check logs."
            exit 1
    fi
    # UTILSLEFT=$(kubectl get pods | grep utils | awk '{print $2}')
    JOBSTATUS=$(kubectl get jobs |grep createchanneltx|awk '{print $2}')
done

# Create peers, ca, orderer using Kubernetes Deployments
echo -e "\nCreating new Deployment to create four peers in network"
echo "Running: kubectl create -f ${KUBECONFIG_FOLDER}/peersDeployment.yaml"
kubectl create -f ${KUBECONFIG_FOLDER}/peersDeployment2.yaml
sleep 30

kubectl create -f ${KUBECONFIG_FOLDER}/couchdb_deployment.yaml
sleep 30

echo "Checking if all deployments are ready"

NUMPENDING=$(kubectl get deployments | grep blockchain | awk '{print $5}' | grep 0 | wc -l | awk '{print $1}')
while [ "${NUMPENDING}" != "0" ]; do
    echo "Waiting on pending deployments. Deployments pending = ${NUMPENDING}"
    NUMPENDING=$(kubectl get deployments | grep blockchain | awk '{print $5}' | grep 0 | wc -l | awk '{print $1}')
    sleep 1
done

echo "Waiting for 15 seconds for peers and orderer to settle"
sleep 10


# Create services for all peers, ca, orderer
echo -e "\nCreating Services for blockchain network"
echo "Running: kubectl create -f ${KUBECONFIG_FOLDER}/blockchain-services.yaml"
kubectl create -f ${KUBECONFIG_FOLDER}/blockchain-services.yaml
sleep 10


# Generate channel artifacts using configtx.yaml and then create channel
echo -e "\nCreating channel transaction artifact and a channel"
echo "Running: kubectl create -f ${KUBECONFIG_FOLDER}/create_channel.yaml"
kubectl create -f ${KUBECONFIG_FOLDER}/create_channel.yaml
sleep 25


# Join all peers on a channel
echo -e "\nCreating joinchannel job"
echo "Running: kubectl create -f ${KUBECONFIG_FOLDER}/join_channel.yaml"
kubectl create -f ${KUBECONFIG_FOLDER}/join_channel.yaml
sleep 25

JOBSTATUS=$(kubectl get jobs |grep joinchannel |awk '{print $2}')
while [ "${JOBSTATUS}" != "1/1" ]; do
    echo "Waiting for joinchannel job to be completed"
    sleep 1;
    if [ "$(kubectl get pods | grep joinchannel | awk '{print $3}')" == "Error" ]; then
        echo "Join Channel Failed"
        exit 1
    fi
    JOBSTATUS=$(kubectl get jobs |grep joinchannel |awk '{print $2}')
done
echo "Join Channel Completed Successfully"

# Install chaincode on each peer
echo -e "\nCreating installchaincode job"
echo "Running: kubectl create -f ${KUBECONFIG_FOLDER}/chaincode_install.yaml"
kubectl create -f ${KUBECONFIG_FOLDER}/chaincode_install_node.yaml
sleep 30

JOBSTATUS=$(kubectl get jobs |grep chaincodeinstallnode |awk '{print $2}')
while [ "${JOBSTATUS}" != "1/1" ]; do
    echo "Waiting for chaincodeinstall job to be completed"
    sleep 1;
    if [ "$(kubectl get pods | grep chaincodeinstallnode | awk '{print $3}')" == "Error" ]; then
        echo "Chaincode Install Failed"
        exit 1
    fi
    JOBSTATUS=$(kubectl get jobs |grep chaincodeinstallnode |awk '{print $2}')
done
echo "Chaincode Install Completed Successfully"

# Instantiate chaincode on channel
echo -e "\nCreating chaincodeinstantiate job"
echo "Running: kubectl create -f ${KUBECONFIG_FOLDER}/chaincode_instantiate.yaml"
kubectl create -f ${KUBECONFIG_FOLDER}/chaincode_instantiate_node.yaml
sleep 30

JOBSTATUS=$(kubectl get jobs |grep chaincodeinstantiatenode |awk '{print $2}')
while [ "${JOBSTATUS}" != "1/1" ]; do
    echo "Waiting for chaincodeinstantiate job to be completed"
    sleep 1;
    if [ "$(kubectl get pods | grep chaincodeinstantiatenode | awk '{print $3}')" == "Error" ]; then
        echo "Chaincode Instantiation Failed"
        exit 1
    fi
    JOBSTATUS=$(kubectl get jobs |grep chaincodeinstantiatenode |awk '{print $2}')
done
echo "Chaincode Instantiation Completed Successfully"

echo -e "\nNetwork Setup Completed !!"
