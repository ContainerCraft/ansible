#!/bin/bash -x
declare -a IPS="${HOSTS}"
/root/kubespray/contrib/inventory_builder/inventory.py ${IPS[@]}
ansible-playbook $@ --become /root/.ansible/playbooks/kubespray-prep.yml
ansible-playbook $@ --become ./cluster.yml 
cat /etc/ansible/artifacts/admin.conf > /root/.kube/config 
cat /etc/ansible/artifacts/admin.conf > /config 
kubectl apply -f /root/patch/multus-daemonset.yml
