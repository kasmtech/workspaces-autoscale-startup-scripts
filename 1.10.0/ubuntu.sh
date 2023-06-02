#!/bin/bash
set -ex

# Note: Templated items (e.g '<bracket>foo<bracket>') will be replaced by Kasm when provisioning the system
GIVEN_HOSTNAME='{server_hostname}'
MANAGER_TOKEN='{manager_token}'
# Ensure the Upstream Auth Address in the Zone is set to an actual DNS name or IP and NOT $request_host$
MANAGER_ADDRESS='{upstream_auth_address}'
SERVER_ID='{server_id}'
# Provider Options are aws, oci, gcp, or digital_ocean
PROVIDER_NAME='aws'
# Swap size in MB, adjust appropriately depending on the size of your Agent VMs
SWAP_SIZE_GB='2'
KASM_BUILD_URL='https://kasm-static-content.s3.amazonaws.com/kasm_release_1.10.0.238225.tar.gz'



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
fallocate -l ${SWAP_SIZE_GB}G /var/swap.1
/sbin/mkswap /var/swap.1
chmod 600 /var/swap.1
/sbin/swapon /var/swap.1
echo '/var/swap.1 swap swap defaults 0 0' | tee -a /etc/fstab

# Choose an appropriate way to detect the IP of the sysetm

#AWS Internal IP
IP=(`curl -s http://169.254.169.254/latest/meta-data/local-ipv4`)

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



# If the AutoScaling is configured to create DNS records for the new agents, this value will be populated, and used
#   in the agent's config
if [ -z "$GIVEN_HOSTNAME" ] ||  [ "$GIVEN_HOSTNAME" == "None" ]  ;
then
    AGENT_ADDRESS=$IP
else
    AGENT_ADDRESS=$GIVEN_HOSTNAME
fi

cd /tmp
wget $KASM_BUILD_URL -O kasm.tar.gz
tar -xf kasm.tar.gz

apt_wait
sleep 20
apt_wait
bash kasm_release/install.sh -e -S agent -p $AGENT_ADDRESS -m $MANAGER_ADDRESS -i $SERVER_ID -r $PROVIDER_NAME -M $MANAGER_TOKEN


echo -e "{nginx_cert_in}" > /opt/kasm/current/certs/kasm_nginx.crt
echo -e "{nginx_key_in}" > /opt/kasm/current/certs/kasm_nginx.key

docker exec -it kasm_proxy nginx -s reload

# Cleanup the downloaded and extracted files
rm kasm.tar.gz
rm -rf kasm_release
