#!/bin/bash

set -e

###########################################################################################################
######################################### VARIABLES #######################################################
###########################################################################################################

echo "================ AWS WORDPRESS + MARIADB ================"

printf "%s" "Nombre alumno/proyecto: "
read ALUMNO

AMI_ID="ami-04b4f1a9cf54c11d0"
KEY_NAME="${ALUMNO}-key"

echo ""
echo "--- RED ---"

printf "%s" "CIDR VPC (ej: 10.0.0.0/16): "
read VPC_MAIN

printf "%s" "CIDR PUBLICA (ej: 10.0.1.0/24): "
read CIDR_PUBLIC

printf "%s" "CIDR PRIVADA (ej: 10.0.2.0/24): "
read CIDR_PRIVATE

echo ""
echo "--- IPS PRIVADAS ---"

printf "%s" "IP Wordpress (ej: 10.0.1.100): "
read IP_WORDPRESS

printf "%s" "IP MariaDB (ej: 10.0.2.100): "
read IP_MARIADB

echo ""
echo "--- WORDPRESS ---"

printf "%s" "Dominio Wordpress (ej: wp.midominio.com): "
read WP_DOMAIN

printf "%s" "Email admin Wordpress: "
read EMAIL

printf "%s" "Nombre Base Datos: "
read DB_NAME

printf "%s" "Usuario Base Datos: "
read DB_USER

printf "%s" "Password Base Datos: "
read DB_PASS

###########################################################################################################
######################################### VARIABLES AWS ###################################################
###########################################################################################################

export EDITOR=true

REGION="us-east-1"
AZ1="${REGION}a"

DESCRIPTION="Practica Wordpress AWS"

MY_IP="0.0.0.0/0"

VPC_NAME="vpc-${ALUMNO}"

###########################################################################################################
############################################# VPC #########################################################
###########################################################################################################

echo ""
echo "================ CREANDO VPC ================"

VPC_ID=$(aws ec2 create-vpc \
--cidr-block "${VPC_MAIN}" \
--tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${VPC_NAME}}]" \
--query 'Vpc.VpcId' \
--output text)

aws ec2 modify-vpc-attribute \
--vpc-id $VPC_ID \
--enable-dns-hostnames

echo "VPC: $VPC_ID"

###########################################################################################################
######################################## SUBRED PUBLICA ###################################################
###########################################################################################################

SUBNET_PUBLIC=$(aws ec2 create-subnet \
--vpc-id $VPC_ID \
--cidr-block "${CIDR_PUBLIC}" \
--availability-zone $AZ1 \
--tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=SUBNET-PUBLICA}]" \
--query 'Subnet.SubnetId' \
--output text)

aws ec2 modify-subnet-attribute \
--subnet-id $SUBNET_PUBLIC \
--map-public-ip-on-launch

echo "Public Subnet: $SUBNET_PUBLIC"

###########################################################################################################
######################################## SUBRED PRIVADA ###################################################
###########################################################################################################

SUBNET_PRIVATE=$(aws ec2 create-subnet \
--vpc-id $VPC_ID \
--cidr-block "${CIDR_PRIVATE}" \
--availability-zone $AZ1 \
--tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=SUBNET-PRIVADA}]" \
--query 'Subnet.SubnetId' \
--output text)

echo "Private Subnet: $SUBNET_PRIVATE"

###########################################################################################################
######################################## INTERNET GATEWAY #################################################
###########################################################################################################

IGW_ID=$(aws ec2 create-internet-gateway \
--tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=IGW-${ALUMNO}}]" \
--query 'InternetGateway.InternetGatewayId' \
--output text)

aws ec2 attach-internet-gateway \
--internet-gateway-id $IGW_ID \
--vpc-id $VPC_ID

###########################################################################################################
######################################## ROUTE TABLE PUBLIC ###############################################
###########################################################################################################

RT_PUBLIC=$(aws ec2 create-route-table \
--vpc-id $VPC_ID \
--tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=RT-PUBLICA}]" \
--query 'RouteTable.RouteTableId' \
--output text)

aws ec2 create-route \
--route-table-id $RT_PUBLIC \
--destination-cidr-block 0.0.0.0/0 \
--gateway-id $IGW_ID

aws ec2 associate-route-table \
--route-table-id $RT_PUBLIC \
--subnet-id $SUBNET_PUBLIC

###########################################################################################################
######################################## NAT GATEWAY ######################################################
###########################################################################################################

echo "Creando Elastic IP..."

EIP_ALLOC=$(aws ec2 allocate-address \
--domain vpc \
--query 'AllocationId' \
--output text)

echo "Creando NAT Gateway..."

NATGW_ID=$(aws ec2 create-nat-gateway \
--subnet-id $SUBNET_PUBLIC \
--allocation-id $EIP_ALLOC \
--query 'NatGateway.NatGatewayId' \
--output text)

echo "Esperando NAT Gateway..."

aws ec2 wait nat-gateway-available \
--nat-gateway-ids $NATGW_ID

###########################################################################################################
######################################## ROUTE TABLE PRIVADA ##############################################
###########################################################################################################

RT_PRIVATE=$(aws ec2 create-route-table \
--vpc-id $VPC_ID \
--tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=RT-PRIVADA}]" \
--query 'RouteTable.RouteTableId' \
--output text)

aws ec2 create-route \
--route-table-id $RT_PRIVATE \
--destination-cidr-block 0.0.0.0/0 \
--nat-gateway-id $NATGW_ID

aws ec2 associate-route-table \
--route-table-id $RT_PRIVATE \
--subnet-id $SUBNET_PRIVATE

###########################################################################################################
######################################## SECURITY GROUP WORDPRESS #########################################
###########################################################################################################

echo ""
echo "================ SECURITY GROUP WORDPRESS ================"

SG_ID_WORDPRESS=$(aws ec2 create-security-group \
--group-name "SG-WORDPRESS-${ALUMNO}" \
--description "$DESCRIPTION" \
--vpc-id $VPC_ID \
--query 'GroupId' \
--output text)

aws ec2 authorize-security-group-ingress \
--group-id $SG_ID_WORDPRESS \
--protocol tcp \
--port 22 \
--cidr $MY_IP

aws ec2 authorize-security-group-ingress \
--group-id $SG_ID_WORDPRESS \
--protocol tcp \
--port 80 \
--cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress \
--group-id $SG_ID_WORDPRESS \
--protocol tcp \
--port 443 \
--cidr 0.0.0.0/0

###########################################################################################################
######################################## SECURITY GROUP MARIADB ###########################################
###########################################################################################################

echo ""
echo "================ SECURITY GROUP MARIADB ================"

SG_ID_MARIADB=$(aws ec2 create-security-group \
--group-name "SG-MARIADB-${ALUMNO}" \
--description "$DESCRIPTION" \
--vpc-id $VPC_ID \
--query 'GroupId' \
--output text)

aws ec2 authorize-security-group-ingress \
--group-id $SG_ID_MARIADB \
--protocol tcp \
--port 22 \
--source-group $SG_ID_WORDPRESS

aws ec2 authorize-security-group-ingress \
--group-id $SG_ID_MARIADB \
--protocol tcp \
--port 3306 \
--source-group $SG_ID_WORDPRESS

###########################################################################################################
######################################## KEYPAIR ##########################################################
###########################################################################################################

echo ""
echo "================ CREANDO KEYPAIR ================"

aws ec2 create-key-pair \
--key-name "${KEY_NAME}" \
--query "KeyMaterial" \
--output text > ${KEY_NAME}.pem

chmod 400 ${KEY_NAME}.pem

###########################################################################################################
######################################## EC2 MARIADB ######################################################
###########################################################################################################

echo ""
echo "================ CREANDO EC2 MARIADB ================"

USER_DATA_MARIADB=$(cat <<EOF
#!/bin/bash

set -e

sleep 60

apt update -y

DEBIAN_FRONTEND=noninteractive apt install -y mariadb-server

systemctl enable mariadb
systemctl start mariadb

sed -i 's/^bind-address.*/bind-address = 0.0.0.0/' /etc/mysql/mariadb.conf.d/50-server.cnf

systemctl restart mariadb

mysql -e "CREATE DATABASE ${DB_NAME};"

mysql -e "CREATE USER '${DB_USER}'@'${IP_WORDPRESS}' IDENTIFIED BY '${DB_PASS}';"

mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'${IP_WORDPRESS}';"

mysql -e "FLUSH PRIVILEGES;"
EOF
)

MARIADB_INSTANCE_ID=$(aws ec2 run-instances \
--image-id "$AMI_ID" \
--instance-type "t2.micro" \
--key-name "$KEY_NAME" \
--network-interfaces "SubnetId=$SUBNET_PRIVATE,AssociatePublicIpAddress=false,DeviceIndex=0,PrivateIpAddresses=[{Primary=true,PrivateIpAddress=$IP_MARIADB}],Groups=[$SG_ID_MARIADB]" \
--tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=MARIADB}]" \
--user-data "$USER_DATA_MARIADB" \
--query "Instances[0].InstanceId" \
--output text)

echo "MariaDB creada: $MARIADB_INSTANCE_ID"

###########################################################################################################
######################################## ESPERAR MARIADB ##################################################
###########################################################################################################

echo "Esperando MariaDB..."

aws ec2 wait instance-running \
--instance-ids $MARIADB_INSTANCE_ID

sleep 120

###########################################################################################################
######################################## EC2 WORDPRESS ####################################################
###########################################################################################################

echo ""
echo "================ CREANDO EC2 WORDPRESS ================"

USER_DATA_WORDPRESS=$(cat <<EOF
#!/bin/bash

set -e

sleep 120

apt update -y

DEBIAN_FRONTEND=noninteractive apt install -y \
apache2 \
php \
php-mysql \
php-curl \
php-gd \
php-mbstring \
php-xml \
php-xmlrpc \
php-soap \
php-intl \
unzip \
curl

systemctl enable apache2
systemctl start apache2

# Obtener IP publica automaticamente
PUBLIC_IP=\$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

# Instalar WP CLI
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar

chmod +x wp-cli.phar

mv wp-cli.phar /usr/local/bin/wp

# Limpiar apache
rm -rf /var/www/html/*

cd /var/www/html

# Descargar Wordpress
wp core download --allow-root

# Config Wordpress
wp config create \
--dbname=${DB_NAME} \
--dbuser=${DB_USER} \
--dbpass=${DB_PASS} \
--dbhost=${IP_MARIADB} \
--allow-root

# Instalar Wordpress usando IP PUBLICA
wp core install \
--url="http://\${PUBLIC_IP}" \
--title="Wordpress AWS" \
--admin_user=admin \
--admin_password=${DB_PASS} \
--admin_email=${EMAIL} \
--skip-email \
--allow-root

# Permisos
chown -R www-data:www-data /var/www/html

chmod -R 755 /var/www/html

# Apache rewrite
a2enmod rewrite

systemctl restart apache2

echo "WORDPRESS INSTALADO"
EOF
)

WORDPRESS_INSTANCE_ID=$(aws ec2 run-instances \
--image-id "$AMI_ID" \
--instance-type "t2.micro" \
--key-name "$KEY_NAME" \
--network-interfaces "SubnetId=$SUBNET_PUBLIC,AssociatePublicIpAddress=true,DeviceIndex=0,PrivateIpAddresses=[{Primary=true,PrivateIpAddress=$IP_WORDPRESS}],Groups=[$SG_ID_WORDPRESS]" \
--tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=WORDPRESS}]" \
--user-data "$USER_DATA_WORDPRESS" \
--query "Instances[0].InstanceId" \
--output text)

echo "Wordpress creado: $WORDPRESS_INSTANCE_ID"

###########################################################################################################
######################################## IP PUBLICA #######################################################
###########################################################################################################

echo ""
echo "================ OBTENIENDO IP PUBLICA ================"

aws ec2 wait instance-running \
--instance-ids $WORDPRESS_INSTANCE_ID

PUBLIC_IP=$(aws ec2 describe-instances \
--instance-ids $WORDPRESS_INSTANCE_ID \
--query "Reservations[0].Instances[0].PublicIpAddress" \
--output text)

###########################################################################################################
######################################## FINAL ############################################################
###########################################################################################################

echo ""
echo "================ INSTALACION FINALIZADA ================"
echo ""
echo "Wordpress URL:"
echo "http://${PUBLIC_IP}"
echo ""
echo "Admin user: ${DB_USER}"
echo "Admin password: ${DB_PASS}"
echo ""
echo "MariaDB privada:"
echo "${IP_MARIADB}"
echo ""
