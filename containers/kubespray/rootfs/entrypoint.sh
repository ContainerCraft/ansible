#!/bin/bash -x

declare -a IPS="${HOSTS}"
/root/kubespray/contrib/inventory_builder/inventory.py ${IPS[@]}

ansible-playbook $@ --become /root/.ansible/playbooks/kubespray-prep.yml
ansible-playbook $@ --become ./cluster.yml 

cat /etc/ansible/artifacts/admin.conf > /root/.kube/config 
cat /etc/ansible/artifacts/admin.conf > /config 

kubectl apply -f /root/patch/multus-daemonset.yml

kubectl taint nodes --all --overwrite node-role.kubernetes.io/master-

kubectl label nodes node1 node2 node3 --overwrite node-role.kubernetes.io/master=''
kubectl label nodes node1 node2 node3 --overwrite node-role.kubernetes.io/control-plane=''

kubectl label nodes --all --overwrite node-role.kubernetes.io/worker=''

sleep 6

kubectl get po -A
