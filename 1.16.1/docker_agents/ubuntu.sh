#!/bin/bash
set -ex

# Note: Templated items (e.g '<bracket>foo<bracket>') will be replaced by Kasm when provisioning the system
GIVEN_HOSTNAME='{server_hostname}'
GIVEN_FQDN='{server_external_fqdn}'
MANAGER_TOKEN='{manager_token}'
# Ensure the Upstream Auth Address in the Zone is set to an actual DNS name or IP and NOT $request_host$
MANAGER_ADDRESS='{upstream_auth_address}'
SERVER_ID='{server_id}'
PROVIDER_NAME='{provider_name}'
# Swap size in MB, adjust appropriately depending on the size of your Agent VMs
SWAP_SIZE_GB='8'
KASM_BUILD_URL='https://kasm-static-content.s3.us-east-1.amazonaws.com/kasm_release_1.16.1.6efdbd.tar.gz'


apt_wait () {{
  while sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1 ; do
    sleep 1
  done
  while sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1 ; do
    sleep 1
  done
  if [ -f /var/log/unattended-upgrades/unattended-upgrades.log ]; then
    while sudo fuser /var/log/unattended-upgrades/unattended-upgrades.log >/dev/null 2>&1 ; do
      sleep 1
    done
  fi
}}


# Create a swap file
if [[ $(sudo swapon --show) ]]; then
  echo 'Swap Exists'
else
  fallocate -l ${{SWAP_SIZE_GB}}G /var/swap.1
  /sbin/mkswap /var/swap.1
  chmod 600 /var/swap.1
  /sbin/swapon /var/swap.1
  echo '/var/swap.1 swap swap defaults 0 0' | tee -a /etc/fstab
fi


# Default Route IP
IP=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+')

#AWS Internal IP
#IP=(`curl -s http://169.254.169.254/latest/meta-data/local-ipv4`)

#AWS Public IP
#IP=(`curl -s http://169.254.169.254/latest/meta-data/public-ipv4`)

#GCP Internal IP
#IP=(`curl -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/ip`)

#GCP Public IP
#IP=(`curl -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip`)

# Digital Ocean Public IP
#IP=(`hostname -I | cut -d  ' ' -f1 |  tr -d '\\n'`)

# Public IP from 3rd Party Service
#IP=(`curl api.ipify.org`)

# OCI Internal IP
#IP=(`hostname -I | cut -d  ' ' -f1 |  tr -d '\\n'`)

# Azure Private IP
#IP=(`curl -H Metadata:true "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/privateIpAddress?api-version=2017-04-02&format=text"`)

# Azure Public IP
#IP=(`curl -H Metadata:true "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2017-04-02&format=text"`)

#VSphere IP
# Replace ens33 with the appropriate network adapter name.
#IP=$(/sbin/ip -o -4 addr list ens33 | awk '{{print $4}}' | cut -d/ -f1)

# If the AutoScaling is configured to create DNS records for the new agents, this value will be populated, and used
#   in the agent's config
if [ -z "$GIVEN_FQDN" ] ||  [ "$GIVEN_FQDN" == "None" ]  ;
then
    AGENT_ADDRESS=$IP
else
    AGENT_ADDRESS=$GIVEN_FQDN
fi

cd /tmp
wget $KASM_BUILD_URL -O kasm.tar.gz
tar -xf kasm.tar.gz

apt_wait
sleep 10
apt_wait

# Install Quemu Agent - Required for Kubevirt environment, optional for others
#apt-get update
#apt install -y qemu-guest-agent
#systemctl enable --now qemu-guest-agent.service

bash kasm_release/install.sh -e -S agent -p $AGENT_ADDRESS -m $MANAGER_ADDRESS -i $SERVER_ID -r $PROVIDER_NAME -M $MANAGER_TOKEN


echo -e "{nginx_cert_in}" > /opt/kasm/current/certs/kasm_nginx.crt
echo -e "{nginx_key_in}" > /opt/kasm/current/certs/kasm_nginx.key

docker exec kasm_proxy nginx -s reload

# Cleanup the downloaded and extracted files
rm kasm.tar.gz
rm -rf kasm_release