# docker run -it --rm -v /tmp/kube:/root/.kube:z -e KUBE_API_FQDN="api.kargo.home.arpa" -e HOSTS="192.168.1.71 192.168.1.72 192.168.1.73" -e VRRP_IP="192.168.1.70" local/kubespray:latest --user fedora -e ansible_ssh_pass=fedora -e ansible_sudo_pass=fedora
#################################################################################
# Builder Image
FROM docker.io/library/centos:8 as rpm
FROM registry.access.redhat.com/ubi8/ubi as builder

#################################################################################
# DNF Package Install List
ARG DNF_LIST="\
  vi \
  git \
  curl \
  bash \
  openssl \
  sshpass \
  python3 \
  python3-pip \
  openssh-clients \
  coreutils-single \
  libselinux-python3 \
  glibc-minimal-langpack \
"

ARG PIP_LIST="\
  k8s \
  selinux \
  passlib \
  ansible \
  kubernetes \
"

#################################################################################
# DNF Package Install Flags
ARG DNF_FLAGS="\
  -y \
  --nogpgcheck \
  --releasever 8 \
  --installroot /rootfs \
"
ARG DNF_FLAGS_EXTRA="\
  --nodocs \
  --setopt=install_weak_deps=false \
  ${DNF_FLAGS} \
"

#################################################################################
# Add CentOS 8 repos to rootfs
COPY --from=rpm     /etc/pki            /rootfs/etc/pki
COPY --from=rpm     /etc/os-release     /rootfs/etc/os-release
COPY --from=rpm     /etc/yum.repos.d    /rootfs/etc/yum.repos.d
COPY --from=rpm     /etc/redhat-release /rootfs/etc/redhat-release

#################################################################################
# Build UBI8 Rootfs
ARG BUILD_PATH='/rootfs'
RUN set -ex \
     && mkdir -p ${BUILD_PATH} \
     && cp -r /etc/pki            /rootfs/etc/ \
     && cp -r /etc/yum.repos.d    /rootfs/etc/ \
     && cp -r /etc/os-release     /rootfs/etc/os-release \
     && cp -r /etc/redhat-release /rootfs/etc/redhat-release \
     && dnf install ${DNF_FLAGS_EXTRA} \
        https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm \
     && dnf install ${DNF_FLAGS_EXTRA} ${DNF_LIST} \
     && export KUBECTL_VERSION=$(curl --silent -L https://storage.googleapis.com/kubernetes-release/release/stable.txt | sed 's/v//g') \
     && export KUBECTL_URL="https://storage.googleapis.com/kubernetes-release/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
     && curl --output ${BUILD_PATH}/bin/kubectl -L ${KUBECTL_URL} \
     && chmod +x ${BUILD_PATH}/bin/kubectl \
     && mkdir -p ${BUILD_PATH}/root/patch \
     && curl --output ${BUILD_PATH}/root/patch/multus-daemonset.yml \
             -L https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset.yml \
     && dnf install git -y \
     && dnf clean all ${DNF_FLAGS} \
     && rm -rf \
           ${BUILD_PATH}/var/cache/* \
     && du -sh ${BUILD_PATH} \
    && echo

RUN set -ex \
     && export RELEASE=$(curl -s https://api.github.com/repos/kubernetes-sigs/kubespray/releases/latest | awk -F '["v,]' '/tag_name/{print $5}') \
     && git clone https://github.com/kubernetes-sigs/kubespray.git --branch v${RELEASE} ${BUILD_PATH}/root/kubespray \
     && chmod +x ${BUILD_PATH}/root/kubespray/contrib/inventory_builder/inventory.py \
    && echo

# Disable tagged git clone temporarily to gain fedora 35 support before release
#    && git clone https://github.com/kubernetes-sigs/kubespray.git --branch v${RELEASE} ${BUILD_PATH}/root/kubespray \

#################################################################################
# Create image from rootfs
FROM scratch
COPY --from=builder /rootfs /
ADD ./rootfs /
WORKDIR /root/kubespray
RUN set -ex                                                                     \
     && python3 -m pip install --upgrade pip                                    \
     && pip3 install --upgrade $PIP_LIST                                        \
          k8s \
          selinux \
          passlib \
          ansible \
          kubernetes \
     && python3 -m pip install --upgrade -r /root/kubespray/requirements.txt    \
     && ansible-galaxy collection install -r /root/.ansible/requirements.yml    \
     && mkdir -p /root/.kube \
    && echo
ENTRYPOINT ["/entrypoint.sh", "--become", "--extra-vars", "@/etc/ansible/vars.yml"]
CMD ["--ask-pass", "--user", "kc2admin"]

#################################################################################
# Finalize image
ENV \
  CONFIG_FILE=/etc/ansible/hosts \
  PATH=/root/platform/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/root/platform/bin:/root/kubespray/contrib/inventory_builder/

LABEL \
  license=GPLv3                                                                     \
  name="konductor-kubespray"                                                        \
  author="ContainerCraft.io | github.com/containercraft/ansible"                    \
  distribution-scope="public"                                                       \
  io.openshift.tags="konductor-kubespray"                                           \
  io.k8s.display-name="ubi8:micro"                                                  \
  summary="CCIO Kubespray Deployment Tools | Red Hat UBI Micro Distroless Image"    \
  description="CCIO Kubespray Deployment Tools | Red Hat UBI Micro Distroless Image"\
  io.k8s.description="CCIO Kubespray Deployment Tools | Red Hat UBI Micro Distroless Image"