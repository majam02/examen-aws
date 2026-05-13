#!/bin/bash
#
# Mario Aja Moral
#



# Key pair SSH
KEY_NAME="examen-aws"
AMI_ID="ami-04b4f1a9cf54c11d0"          # Ubuntu 24.04 AMI ID



echo "--- Rango redes VPC ---"

printf "%s" "RED VPC principal (ej: 10.0.0.0/16): "
read VPC_main

printf "%s" "CIDR red Publico (ej: 10.0.1.0/24): "
read cidr_pub

printf "%s" "CIDR red Privado (ej: 10.0.2.0/24): "
read cidr_priv




echo "--- IP Maquinas EC2 ---"

printf "%s" "IP máquina proxy nginx (ej: 10.0.1.100, sin /): "
read ip_nginx

printf "%s" "IP máquina apache1 (ej: 10.0.2.100, sin /): "
read IP_APACHE1

printf "%s" "IP máquina apache2 (ej: 10.0.2.200, sin /): "
read IP_APACHE2




echo "-- Preguntas para domios --"

# The mail for certs and wordpress config
printf "%s" "Insert email: "
read EMAIL

printf "%s" "SubDominio aws: "
read subdomain_aws

printf "%s" "SubDominio aws2: "
read subdomain_aws2


echo "......Preparando todo......"


###########################################################################################################
###########################                      V P C                          ###########################
###########################################################################################################
export EDITOR=true

# VPC Variables
VPC_NAME="vpc-examen-${ALUMNO}"
REGION="us-east-1"
AVAILABILITY_ZONE1="${REGION}a"
AVAILABILITY_ZONE2="${REGION}b"
DESCRIPTION="Examen AWS"
MY_IP="0.0.0.0/0" # Replace with your public IP range or '0.0.0.0/0' for open access


# Create VPC and capture its ID
VPC_ID=$(aws ec2 create-vpc --cidr-block "${VPC_main}" --instance-tenancy "default" --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${VPC_NAME}-vpc}]" --query 'Vpc.VpcId' --output text)
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames

# Create subnets (Public and Private)
# Public Subnet 1
SUBNET_PUBLIC1=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block "${cidr_pub}" --availability-zone $AVAILABILITY_ZONE1 --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${VPC_NAME}-subnet-public1-${AVAILABILITY_ZONE1}}]" --query 'Subnet.SubnetId' --output text)
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_PUBLIC1 --map-public-ip-on-launch
# Private Subnet 1
SUBNET_PRIVATE1=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block "${cidr_priv}" --availability-zone $AVAILABILITY_ZONE1 --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${VPC_NAME}-subnet-private1-${AVAILABILITY_ZONE1}}]" --query 'Subnet.SubnetId' --output text)


# Create Internet Gateway and attach to the VPC
IGW_ID=$(aws ec2 create-internet-gateway --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${VPC_NAME}-igw}]" --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID

# Create public route table and associate public subnets
RTB_PUBLIC=$(aws ec2 create-route-table --vpc-id $VPC_ID --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${VPC_NAME}-rtb-public}]" --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id $RTB_PUBLIC --destination-cidr-block "0.0.0.0/0" --gateway-id $IGW_ID
aws ec2 associate-route-table --route-table-id $RTB_PUBLIC --subnet-id $SUBNET_PUBLIC1

# Create Elastic IP and NAT Gateway (Only ONE NAT in AZ1)
EIP_ALLOC_ID=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text)
NATGW_ID=$(aws ec2 create-nat-gateway --subnet-id $SUBNET_PUBLIC1 --allocation-id $EIP_ALLOC_ID --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=${VPC_NAME}-nat-public1-${AVAILABILITY_ZONE1}}]" --query 'NatGateway.NatGatewayId' --output text)

# Wait for the NAT Gateway to become available
aws ec2 wait nat-gateway-available --nat-gateway-ids $NATGW_ID

# Create a single private route table and associate both private subnets
RTB_PRIVATE=$(aws ec2 create-route-table --vpc-id $VPC_ID --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${VPC_NAME}-rtb-private}]" --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id $RTB_PRIVATE --destination-cidr-block "0.0.0.0/0" --nat-gateway-id $NATGW_ID
aws ec2 associate-route-table --route-table-id $RTB_PRIVATE --subnet-id $SUBNET_PRIVATE1

# Final verification (optional)
#aws ec2 describe-vpcs --vpc-ids $VPC_ID
#aws ec2 describe-nat-gateways --nat-gateway-ids $NATGW_ID
#aws ec2 describe-route-tables --route-table-ids $RTB_PRIVATE1 $RTB_PRIVATE2

echo "VPC Created !"




###########################################################################################################
########################                    SECURITY GROUPS                        ########################
###########################################################################################################


# Create security group PROXYS
SG_ID_PROXY=$(aws ec2 create-security-group \
  --group-name "GR-Proxy-nginx" \
  --description "$DESCRIPTION" \
  --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value="Proxy-inverso"}]" \
  --query 'GroupId' \
  --output text)
# Add inbound rule to allow SSH
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID_PROXY \
  --protocol tcp \
  --port 22 \
  --cidr $MY_IP
# Add inbound rule to allow HTTP
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID_PROXY \
  --protocol tcp \
  --port 80 \
  --cidr $MY_IP
# Add inbound rule to allow HTTPS
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID_PROXY \
  --protocol tcp \
  --port 443 \
  --cidr $MY_IP






# Create security group APACHE
SG_ID_WORDPRESS=$(aws ec2 create-security-group \
  --group-name "GR-Apache" \
  --description "$DESCRIPTION" \
  --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value="Servidor-apache"}]" \
  --query 'GroupId' \
  --output text)
# Add inbound rule to allow SSH
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID_WORDPRESS \
  --protocol tcp \
  --port 22 \
  --cidr $MY_IP
# Add inbound rule to allow HTTP
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID_WORDPRESS \
  --protocol tcp \
  --port 80 \
  --cidr $MY_IP
# Add inbound rule to allow HTTPS
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID_WORDPRESS \
  --protocol tcp \
  --port 443 \
  --cidr $MY_IP
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID_WORDPRESS \
  --protocol -1 \
  --source-group $SG_ID_PROXY


echo "Security Groups !";





###########################################################################################################
#########################                      KEYS SSH                          ##########################
###########################################################################################################

aws ec2 create-key-pair \
  --key-name "${KEY_NAME}" \
  --query "KeyMaterial" \
  --output text > ${KEY_NAME}.pem

echo "SSH KEYS !";












# PROXY-NGINX
# ====== Variables ======
INSTANCE_NAME="PROXY-NGINX"                 # Tag: Name of the EC2 instance
SUBNET_ID="${SUBNET_PUBLIC1}"           # Subnet ID
SECURITY_GROUP_ID="${SG_ID_PROXY}"  # Security Group ID
PRIVATE_IP="${ip_nginx}"                # Private IP for the instance

INSTANCE_TYPE="t2.micro"                # EC2 Instance Type
KEY_NAME="${KEY_NAME}"                  # Name of the SSH Key Pair
VOLUME_SIZE=8                           # Size of the root EBS volume (in GB)

USER_DATA_SCRIPT=$(cat <<'EOF'
#!/bin/bash
# Update and install necessary packages
apt-get update -y
apt-get install -y curl certbot

sleep 30
# Obtain SSL certificate in standalone mode (non-interactive)
echo "Obtaining SSL certificate using certbot..."

certbot certonly --standalone \
  --non-interactive \
  --agree-tos \
  --email $EMAIL \
  -d "$subdomain_aws.alisal09.com.es"
certbot certonly --standalone \
  --non-interactive \
  --agree-tos \
  --email $EMAIL \
  -d "$subdomain_aws2.alisal09.com.es"





apt-get install nginx -y
apt install nginx-extras -y
cat <<CONFIG > /etc/nginx/sites-available/proxy_site
#upstream backend_servers {
#    server 10.0.2.100:443;
#    server 10.0.2.200:443;
#}

server {
    listen 80;
    server_name $subdomain_aws.alisal09.com.es;
    return 301 https://\$host\$request_uri;  # Redirect HTTP to HTTPS
}
server {
    listen 80;
    server_name $subdomain_aws2.alisal09.com.es;
    return 301 https://\$host\$request_uri;  # Redirect HTTP to HTTPS
}




server {
    listen 443 ssl;
    server_name $subdomain_aws.alisal09.com.es;

    ssl_certificate /etc/letsencrypt/live/$subdomain_aws.alisal09.com.es/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$subdomain_aws.alisal09.com.es/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        proxy_pass https://IP_APACHE1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}


server {
    listen 443 ssl;
    server_name $subdomain_aws2.alisal09.com.es;

    ssl_certificate /etc/letsencrypt/live/$subdomain_aws.alisal09.com.es/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$subdomain_aws.alisal09.com.es/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        proxy_pass https://IP_APACHE2;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}


CONFIG
ln -s /etc/nginx/sites-available/proxy_site /etc/nginx/sites-enabled/
rm /etc/nginx/sites-enabled/default
systemctl restart nginx
systemctl enable nginx
echo "Got Proxied !!!"
EOF
)


# ====== Create EC2 Instance ======
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$VOLUME_SIZE,VolumeType=gp3,DeleteOnTermination=true}" \
    --network-interfaces "SubnetId=$SUBNET_ID,AssociatePublicIpAddress=true,DeviceIndex=0,PrivateIpAddresses=[{Primary=true,PrivateIpAddress=$PRIVATE_IP}],Groups=[$SECURITY_GROUP_ID]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --user-data "$(echo "$USER_DATA_SCRIPT" | sed "s/\$EMAIL/$EMAIL/g" | sed "s/\$subdomain_aws/$subdomain_aws/g" | sed "s/\$subdomain_aws2/$subdomain_aws2/g" | sed "s/IP_APACHE1/${IP_APACHE1}/g" | sed "s/IP_APACHE2/${IP_APACHE2}/g")" \
    --query "Instances[0].InstanceId" \
    --output text)

echo "${INSTANCE_NAME} created"





###########################################################################################################
#########################                 COPY SSH KEY TO NGINX                  ##########################
###########################################################################################################

echo "Esperando que la instancia esté lista..."

# Esperar a que la instancia esté en estado running
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

# Obtener IP pública de nginx (DESPUÉS de running)
NGINX_PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text)

echo "NGINX Public IP: ${NGINX_PUBLIC_IP}"

echo "Esperando SSH en NGINX..."

# Esperar SSH disponible
until ssh -o StrictHostKeyChecking=no \
          -o ConnectTimeout=5 \
          -i "${KEY_NAME}.pem" \
          ubuntu@"${NGINX_PUBLIC_IP}" "echo SSH OK" >/dev/null 2>&1
do
    echo "SSH aún no disponible..."
    sleep 10
done

echo "SSH disponible en NGINX!"

# Permisos clave local
chmod 700 "${KEY_NAME}.pem"

# Crear directorio .ssh en nginx
ssh -o StrictHostKeyChecking=no \
    -i "${KEY_NAME}.pem" \
    ubuntu@"${NGINX_PUBLIC_IP}" \
    "mkdir -p ~/.ssh && chmod 700 ~/.ssh"

# Copiar clave privada al nginx
scp -o StrictHostKeyChecking=no \
    -i "${KEY_NAME}.pem" \
    "${KEY_NAME}.pem" \
    ubuntu@"${NGINX_PUBLIC_IP}":~/

# Permisos dentro nginx
ssh -o StrictHostKeyChecking=no \
    -i "${KEY_NAME}.pem" \
    ubuntu@"${NGINX_PUBLIC_IP}" \
    "chmod 400 ~/${KEY_NAME}.pem"

# Añadir hosts privados automáticamente
ssh -o StrictHostKeyChecking=no \
    -i "${KEY_NAME}.pem" \
    ubuntu@"${NGINX_PUBLIC_IP}" <<EOF
ssh-keyscan ${IP_APACHE1} >> ~/.ssh/known_hosts
ssh-keyscan ${IP_APACHE2} >> ~/.ssh/known_hosts
EOF

echo "SSH key copied to NGINX!"













####### APACHE

# APACHE-1
# ====== Variables ======
INSTANCE_NAME="APACHE-1"                 # Tag: Name of the EC2 instance
SUBNET_ID="${SUBNET_PRIVATE1}"           # Subnet ID
SECURITY_GROUP_ID="${SG_ID_WORDPRESS}"  # Security Group ID
PRIVATE_IP="${IP_APACHE1}"                # Private IP for the instance

INSTANCE_TYPE="t2.micro"                # EC2 Instance Type
KEY_NAME="${KEY_NAME}"                  # Name of the SSH Key Pair
VOLUME_SIZE=8                           # Size of the root EBS volume (in GB)
USER_DATA_SCRIPT=$(cat <<'EOF'
#!/bin/bash
set -e
sleep 60
sudo apt update
sudo apt install apache2 mysql-client mysql-server php php-mysql -y


sudo a2enmod ssl
sudo a2ensite default-ssl
sudo a2dissite 000-default
sudo systemctl restart apache2

sudo rm -rf /var/www/html/*
sudo chmod -R 755 /var/www/html
sudo chown -R ubuntu:ubuntu /var/www/html

sudo a2enmod ssl
sudo a2ensite default-ssl
sudo a2dissite 000-default
sudo systemctl restart apache2
EOF
)

# ====== Create EC2 Instance ======
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$VOLUME_SIZE,VolumeType=gp3,DeleteOnTermination=true}" \
    --network-interfaces "SubnetId=$SUBNET_ID,AssociatePublicIpAddress=false,DeviceIndex=0,PrivateIpAddresses=[{Primary=true,PrivateIpAddress=$PRIVATE_IP}],Groups=[$SECURITY_GROUP_ID]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --query "Instances[0].InstanceId" \
    --user-data "$USER_DATA_SCRIPT" \
    --output text)
echo "${INSTANCE_NAME} created";







# APACHE-2
# ====== Variables ======
INSTANCE_NAME="APACHE-2"                 # Tag: Name of the EC2 instance
SUBNET_ID="${SUBNET_PRIVATE1}"           # Subnet ID
SECURITY_GROUP_ID="${SG_ID_WORDPRESS}"  # Security Group ID
PRIVATE_IP="${IP_APACHE2}"               # Private IP for the instance

INSTANCE_TYPE="t2.micro"                # EC2 Instance Type
KEY_NAME="${KEY_NAME}"                  # Name of the SSH Key Pair
VOLUME_SIZE=8                           # Size of the root EBS volume (in GB)
USER_DATA_SCRIPT=$(cat <<'EOF'
#!/bin/bash
set -e
sleep 60
sudo apt update
sudo apt install apache2 mysql-client mysql-server php php-mysql -y


sudo a2enmod ssl
sudo a2ensite default-ssl
sudo a2dissite 000-default
sudo systemctl restart apache2

sudo rm -rf /var/www/html/*
sudo chmod -R 755 /var/www/html
sudo chown -R ubuntu:ubuntu /var/www/html

sudo a2enmod ssl
sudo a2ensite default-ssl
sudo a2dissite 000-default
sudo systemctl restart apache2
EOF
)

# ====== Create EC2 Instance ======
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$VOLUME_SIZE,VolumeType=gp3,DeleteOnTermination=true}" \
    --network-interfaces "SubnetId=$SUBNET_ID,AssociatePublicIpAddress=false,DeviceIndex=0,PrivateIpAddresses=[{Primary=true,PrivateIpAddress=$PRIVATE_IP}],Groups=[$SECURITY_GROUP_ID]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --query "Instances[0].InstanceId" \
    --user-data "$USER_DATA_SCRIPT" \
    --output text)
echo "${INSTANCE_NAME} created";






echo "                                                                                            ";
echo "▄▄▄▄▄   ▄▄▄                    ▄▄▄▄▄▄▄                        ▄▄▄▄       ██  ██  ██  ▄▄▄▄   ";
echo " ███    ███                    ███▀▀███▄                    ▄██████▄    ██  ██  ██ ▄██████▄ ";
echo " ███    ███      ▄███▄ ██ ██   ███▄▄███▀ ▀▀█▄ ▄████ ▄███▄   ███  ███   ██  ██  ██  ███  ███ ";
echo " ███    ███      ██ ██ ██▄██   ███▀▀▀▀  ▄█▀██ ██    ██ ██   ███▄▄███  ██  ██  ██   ███▄▄███ ";
echo "▄███▄   ████████ ▀███▀  ▀█▀    ███      ▀█▄██ ▀████ ▀███▀    ▀████▀  ██  ██  ██     ▀████▀  ";
echo "                                                                                            ";
echo "                                                                                            ";
echo "======================================================"
echo "DEPLOY COMPLETADO"
echo "======================================================"
echo ""
echo "PROXY NGINX:"
echo "ssh -i ${KEY_NAME}.pem ubuntu@${NGINX_PUBLIC_IP}"
echo ""
echo "DOMINIOS:"
echo "https://${subdomain_aws}.alisal09.com.es"
echo "https://${subdomain_aws2}.alisal09.com.es"
echo ""
echo "IPs:"
echo "NGINX   : ${ip_nginx}"
echo "APACHE1 : ${IP_APACHE1}"
echo "APACHE2 : ${IP_APACHE2}"
echo ""
echo "IP pública NGINX:"
echo "${NGINX_PUBLIC_IP}"
echo ""
echo ""
echo "-- Made  with love by Paco <3 --"
echo ""
echo "======================================================"


echo ""
echo "======================================================"
echo "Descarga la clave ssh al equipo <3"
echo "======================================================"
echo ""
echo "Actions -> Downlod file"
echo "${KEY_NAME}.pem"
echo "Si no tendras que usar la cloudshell :c"
echo "======================================================"
