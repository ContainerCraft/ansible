#!/bin/bash -x
# ansible-playbook --user fedora -e ansible_ssh_pass=fedora -e ansible_sudo_pass=fedora --become ./cluster.yml

declare -a IPS="${HOSTS}"

cat <<EOF

Deployment Config:

  $KUBE_API_DNS=api.kargo.home.arpa
  $VRRP_IP=192.168.1.60
  $IPS

EOF
sleep 1

/root/kubespray/contrib/inventory_builder/inventory.py ${IPS[@]}

ansible-playbook $@ --become /root/.ansible/playbooks/kubespray-prep.yml || exit 1

ansible-playbook $@ --become ./cluster.yml || ansible-playbook $@ --become ./cluster.yml

cat /etc/ansible/artifacts/admin.conf > /root/.kube/config

kubectl apply -f /root/patch/multus-daemonset.yml

kubectl taint nodes --all --overwrite node-role.kubernetes.io/master-

kubectl label nodes node1 node2 node3 --overwrite node-role.kubernetes.io/master=''
kubectl label nodes node1 node2 node3 --overwrite node-role.kubernetes.io/control-plane=''

kubectl label nodes --all --overwrite node-role.kubernetes.io/worker=''

kubectl patch deployment -n kube-system coredns --patch='{"spec":{"template":{"spec":{"tolerations":[]}}}}'
kubectl -n kube-system rollout restart deployment/coredns

sleep 7

kubectl get po -A

cat /etc/ansible/artifacts/admin.conf | sed "s/$VRRP_IP/$KUBE_API_DNS/g" | tee /config
