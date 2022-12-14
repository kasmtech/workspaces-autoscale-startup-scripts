#!/bin/bash
set -ex

# Note: Templated items (e.g '<bracket>foo<bracket>') will be replaced by Kasm when provisioning the system
GIVEN_HOSTNAME='{server_hostname}'
MANAGER_TOKEN='{manager_token}'
# Ensure the Upstream Auth Address in the Zone is set to an actual DNS name or IP and NOT $request_host$
MANAGER_ADDRESS='{upstream_auth_address}'
SERVER_ID='{server_id}'
PROVIDER_NAME='{provider_name}'
SWAP_SIZE_MB='2048'
KASM_BUILD_URL='https://kasmweb-build-artifacts.s3.amazonaws.com/kasm_backend/branches/develop/kasm_workspaces_develop.tar.gz'




# Create a swap file
/usr/bin/dd if=/dev/zero of=/var/swap.1 bs=1M count=$SWAP_SIZE_MB
/sbin/mkswap /var/swap.1
chmod 600 /var/swap.1
/sbin/swapon /var/swap.1
echo '/mnt/1GiB.swap swap swap defaults 0 0' | tee -a /etc/fstab

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
IP=(`curl api.ipify.org`)

# OCI Internal IP
#IP=(`hostname -I | cut -d  ' ' -f1 |  tr -d '\\n'`)


# If the AutoScaling is configured to create DNS records for the new agents, this value will be populated, and used
#   in the agent's config
if [ -z "$GIVEN_HOSTNAME" ]
then
    AGENT_ADDRESS=$IP
else
    AGENT_ADDRESS=$GIVEN_HOSTNAME
fi

cd /tmp
wget $KASM_BUILD_URL -O kasm.tar.gz
tar -xf kasm.tar.gz

#apt_wait
bash kasm_release/install.sh -e -S agent -p $AGENT_ADDRESS -m $MANAGER_ADDRESS -i $SERVER_ID -r $PROVIDER_NAME -M $MANAGER_TOKEN


echo -e "{nginx_cert_in}" > /opt/kasm/current/certs/kasm_nginx.crt
echo -e "{nginx_key_in}" > /opt/kasm/current/certs/kasm_nginx.key

docker exec -it kasm_proxy nginx -s reload

# Cleanup the downloaded and extracted files
rm kasm.tar.gz
rm -rf kasm_release
/usr/libexec/oci-growfs -y