#!/bin/bash -x
ansible-playbook $@ --become /root/.ansible/playbooks/kubespray-prep.yml
ansible-playbook $@ --become ./cluster.yml 
cat /etc/ansible/artifacts/admin.conf > /root/.kube/config 
cat /etc/ansible/artifacts/admin.conf > /config 
