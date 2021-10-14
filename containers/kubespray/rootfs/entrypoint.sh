#!/bin/bash -x
kubespray-prep $@  
ansible-playbook $@ --become ./cluster.yml 
cat /etc/ansible/artifacts/admin.conf > /root/.kube/config 
cat /etc/ansible/artifacts/admin.conf > /config 
