echo -e "\nDeleting Network...\n"

KUBECONFIG_FOLDER=${PWD}/configFiles

kubectl delete -f ${KUBECONFIG_FOLDER}/chaincode_instantiate_node.yaml
kubectl delete -f ${KUBECONFIG_FOLDER}/chaincode_install_node.yaml

kubectl delete -f ${KUBECONFIG_FOLDER}/chaincode_instantiate.yaml
kubectl delete -f ${KUBECONFIG_FOLDER}/chaincode_install.yaml

kubectl delete -f ${KUBECONFIG_FOLDER}/join_channel.yaml
kubectl delete -f ${KUBECONFIG_FOLDER}/create_channel.yaml

kubectl delete -f ${KUBECONFIG_FOLDER}/couchdb_deployment.yaml
kubectl delete -f ${KUBECONFIG_FOLDER}/peersDeployment2.yaml
kubectl delete -f ${KUBECONFIG_FOLDER}/peersDeployment.yaml

kubectl delete -f ${KUBECONFIG_FOLDER}/blockchain-services.yaml

kubectl delete -f ${KUBECONFIG_FOLDER}/configtxgen.yaml
kubectl delete -f ${KUBECONFIG_FOLDER}/cryptogen.yaml
kubectl delete -f ${KUBECONFIG_FOLDER}/create_channeltx.yaml
kubectl delete -f ${KUBECONFIG_FOLDER}/copyArtifactsJob.yaml

kubectl delete -f ${KUBECONFIG_FOLDER}/createVolume.yaml

sleep 15

echo -e "\npv:" 
kubectl get pv
echo -e "\npvc:"
kubectl get pvc
echo -e "\njobs:"
kubectl get jobs 
echo -e "\ndeployments:"
kubectl get deployments
echo -e "\nservices:"
kubectl get services
echo -e "\npods:"
kubectl get pods

echo -e "\nNetwork Deleted!!\n"

