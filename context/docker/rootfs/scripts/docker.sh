#!/bin/bash
# Copyright © 2021 Alibaba Group Holding Ltd.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
set -e
set -x

rootfs=$(dirname "$(pwd)")
image_dir="$rootfs/images"
command_exists() {
  command -v "$@" >/dev/null 2>&1
}
get_distribution() {
  lsb_dist=""
  # Every system that we officially support has /etc/os-release
  if [ -r /etc/os-release ]; then
    lsb_dist="$(. /etc/os-release && echo "$ID")"
  fi
  # Returning an empty string here should be alright since the
  # case statements don't act unless you provide an actual value
  echo "$lsb_dist"
}
disable_selinux() {
  if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
    setenforce 0
  fi
}
load_images() {
  for image in "$image_dir"/*; do
    if [ -f "${image}" ]; then
      docker load -q -i "${image}"
    fi
  done
}

storage=${1:-/var/lib/docker}
mkdir -p $storage
if ! command_exists docker; then
  lsb_dist=$(get_distribution)
  lsb_dist="$(echo "$lsb_dist" | tr '[:upper:]' '[:lower:]')"
  echo "current system is $lsb_dist"
  case "$lsb_dist" in
  ubuntu | deepin | debian | raspbian | kylin)
    cp ../etc/docker.service /lib/systemd/system/docker.service
    ;;
  centos | rhel | ol | sles | kylin | neokylin)
    cp ../etc/docker.service /usr/lib/systemd/system/docker.service
    ;;
  alios)
    docker0=$(ip addr show docker0 | head -1 | tr " " "\n" | grep "<" | grep -iwo "UP" | wc -l)
    if [ "$docker0" != "1" ]; then
      ip link add name docker0 type bridge
      ip addr add dev docker0 172.17.0.1/16
    fi
    cp ../etc/docker.service /usr/lib/systemd/system/docker.service
    ;;
  *)
    echo "unknown system to use /lib/systemd/system/docker.service"
    cp ../etc/docker.service /lib/systemd/system/docker.service
    ;;
  esac

  [ -d /etc/docker/ ] || mkdir /etc/docker/ -p

  chmod -R 755 ../cri
  tar -zxvf ../cri/docker.tar.gz -C /usr/bin
  chmod a+x /usr/bin
  chmod a+x /usr/bin/docker
  chmod a+x /usr/bin/dockerd
  systemctl enable docker.service
  systemctl restart docker.service
  cp ../etc/daemon.json /etc/docker
  if [[ -n $1 && -n $2 ]]; then
    sed -i "s/sea.hub:5000/$2:$3/g" /etc/docker/daemon.json
  fi
fi
disable_selinux
systemctl daemon-reload
systemctl restart docker.service
load_images
