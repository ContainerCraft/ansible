#!/bin/bash

declare -a IPS="${HOSTS}"

cat <<EOF

Deployment Config:

  KUBE_API_FQDN = $KUBE_API_FQDN
  VRRP_IP       = $VRRP_IP
  IPS           = $IPS

EOF
sleep 1

/root/kubespray/contrib/inventory_builder/inventory.py ${IPS[@]}

ansible-playbook $@ --extra-vars @/etc/ansible/vars.yml --become /root/.ansible/playbooks/kubespray-prep.yml || exit 1
ansible-playbook $@ --extra-vars @/etc/ansible/vars.yml --become ./cluster.yml || ansible-playbook $@ --extra-vars @/etc/ansible/vars.yml --become ./cluster.yml

cat /etc/ansible/artifacts/admin.conf > /root/.kube/config
kubectl scale deployment --replicas=0 dns-autoscaler --namespace=kube-system
kubectl apply -f /root/patch/multus-daemonset.yml
#kubectl patch deployment -n kube-system coredns --patch='{"spec":{"template":{"spec":{"tolerations":[]}}}}'
#kubectl -n kube-system rollout restart deployment/coredns
sleep 7
kubectl apply -f /root/patch/multus-daemonset.yml || kubectl apply -f /root/patch/multus-daemonset.yml
cat /etc/ansible/artifacts/admin.conf > /config
kubectl get po -A