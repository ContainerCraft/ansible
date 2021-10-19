#!/bin/bash -x
# ansible-playbook --user fedora -e ansible_ssh_pass=fedora -e ansible_sudo_pass=fedora --become ./cluster.yml
# /entrypoint.sh --user fedora -e ansible_ssh_pass=fedora -e ansible_sudo_pass=fedora

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
kubectl apply -f /root/patch/multus-daemonset.yml
kubectl taint nodes --all --overwrite node-role.kubernetes.io/master-
kubectl label nodes node1 node2 node3 --overwrite node-role.kubernetes.io/master=''
kubectl label nodes node1 node2 node3 --overwrite node-role.kubernetes.io/control-plane=''
kubectl label nodes --all --overwrite node-role.kubernetes.io/worker=''
kubectl patch deployment -n kube-system coredns --patch='{"spec":{"template":{"spec":{"tolerations":[]}}}}'
kubectl -n kube-system rollout restart deployment/coredns
sleep 7
kubectl get po -A
cat /etc/ansible/artifacts/admin.conf | sed "s/$VRRP_IP/$KUBE_API_FQDN/g" | tee /config
