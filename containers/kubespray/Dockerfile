# docker run -it --rm -v /tmp/kube:/root/.kube:z -v ${PWD}/doc/hosts.example.yml:/etc/ansible/hosts:z local/ansible --user usrbinkat -e ansible_ssh_pass=changeme -e ansible_sudo_pass=changeme
#################################################################################
# Builder Image
FROM docker.io/library/centos:8 as rpm
FROM registry.access.redhat.com/ubi8/ubi as builder

#################################################################################
# DNF Package Install List
ARG DNF_LIST="\
  openssl \
  coreutils-single \
  glibc-minimal-langpack \
  vim \
  tar \
  pigz \
  bash \
  curl \
  rsync \
  unzip \
  bsdtar \
  sshpass \
  python3 \
  python3-pip \
"

ARG PIP_LIST="\
  k8s \
  passlib \
  ansible \
  openshift \
  github3.py \
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
     && dnf install git -y \
     && git clone https://github.com/kubernetes-sigs/kubespray.git ${BUILD_PATH}/root/kubespray \
     && chmod +x ${BUILD_PATH}/bin/kubectl \
     && dnf clean all ${DNF_FLAGS} \
     && rm -rf \
           ${BUILD_PATH}/var/cache/* \
     && du -sh ${BUILD_PATH} \
    && echo

#################################################################################
# Create image from rootfs
FROM scratch
COPY --from=builder /rootfs /
ADD ./rootfs /
RUN set -ex                                                                     \
     && python3 -m pip install --upgrade pip                                    \
     && pip3 install --upgrade ${PIP_LIST}                                      \
          k8s \
          passlib \
          openshift \
          github3.py \
          kubernetes \
          ansible==3.4.0 \
          ansible-base==2.10.11 \
          cryptography==2.8 \
          jinja2==2.11.3 \
          netaddr==0.7.19 \
          pbr==5.4.4 \
          jmespath==0.9.5 \
          ruamel.yaml==0.16.10 \
          ruamel.yaml.clib==0.2.4 \
          MarkupSafe==1.1.1 \
     && ansible-galaxy collection install -r /root/.ansible/requirements.yml    \
     && mkdir -p /root/.kube \
    && echo
WORKDIR /root/kubespray
ENTRYPOINT ["/entrypoint.sh"]
CMD ["--become", "--ask-pass", "--ask-become-pass", "--user", "fedora"]

#################################################################################
# Finalize image
MAINTAINER ContainerCraft.io
LABEL \
  license=GPLv3                                                                 \
  name="minimal"                                                                \
  distribution-scope="public"                                                   \
  io.openshift.tags="minimal"                                                   \
  io.k8s.display-name="ubi:minimal"                                             \
  summary="Minimal Base Image | Red Hat UBI Supportable Image"            \
  description="Minimal Base Image | Red Hat UBI Supportable Image"        \
  io.k8s.description="Minimal Base Image | Red Hat UBI Supportable Image"
