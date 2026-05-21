#!/bin/bash

set -e

###########################################################################################################
######################################### VARIABLES #######################################################
###########################################################################################################

echo "================ AWS VPC + EC2 ================"

printf "%s" "Nombre alumno/proyecto: "
read ALUMNO

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

printf "%s" "IP EC2 Windows (subred publica, opcional, dejar vacío para asignar automáticamente): "
read IP_WINDOWS

printf "%s" "IP EC2 Ubuntu (subred privada, ej: 10.0.2.100): "
read IP_UBUNTU

###########################################################################################################
######################################### VARIABLES AWS ###################################################
###########################################################################################################

export EDITOR=true

REGION="us-east-1"
AZ1="${REGION}a"

DESCRIPTION="Practica VPC AWS"

MY_IP="0.0.0.0/0"

VPC_NAME="vpc-${ALUMNO}"

# AMIs oficiales (ejemplos)
AMI_WINDOWS="ami-0909cee4864578472"   # Windows Server 2022 base
AMI_UBUNTU="ami-04b4f1a9cf54c11d0"    # Ubuntu 24.04 LTS

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
######################################## SECURITY GROUP PUBLIC ############################################
###########################################################################################################

SG_ID_PUBLIC=$(aws ec2 create-security-group \
--group-name "SG-PUBLIC-${ALUMNO}" \
--description "$DESCRIPTION" \
--vpc-id $VPC_ID \
--query 'GroupId' \
--output text)

aws ec2 authorize-security-group-ingress \
--group-id $SG_ID_PUBLIC \
--protocol tcp \
--port 3389 \
--cidr $MY_IP

aws ec2 authorize-security-group-ingress \
--group-id $SG_ID_PUBLIC \
--protocol tcp \
--port 22 \
--cidr $MY_IP

###########################################################################################################
######################################## SECURITY GROUP PRIVATE ###########################################
###########################################################################################################

SG_ID_PRIVATE=$(aws ec2 create-security-group \
--group-name "SG-PRIVATE-${ALUMNO}" \
--description "$DESCRIPTION" \
--vpc-id $VPC_ID \
--query 'GroupId' \
--output text)

aws ec2 authorize-security-group-ingress \
--group-id $SG_ID_PRIVATE \
--protocol tcp \
--port 22 \
--source-group $SG_ID_PUBLIC

aws ec2 authorize-security-group-ingress \
--group-id $SG_ID_PRIVATE \
--protocol tcp \
--port 80 \
--source-group $SG_ID_PUBLIC

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
######################################## EC2 UBUNTU (PRIVADA) ############################################
###########################################################################################################

echo ""
echo "================ CREANDO EC2 UBUNTU ================"

USER_DATA_UBUNTU=$(cat <<EOF
#!/bin/bash
set -e
apt update -y
apt install -y apache2
echo "hola mundo" > /var/www/html/index.html
systemctl enable apache2
systemctl start apache2
EOF
)

UBUNTU_INSTANCE_ID=$(aws ec2 run-instances \
--image-id "$AMI_UBUNTU" \
--instance-type "t2.micro" \
--key-name "$KEY_NAME" \
--network-interfaces "SubnetId=$SUBNET_PRIVATE,AssociatePublicIpAddress=false,DeviceIndex=0,PrivateIpAddresses=[{Primary=true,PrivateIpAddress=$IP_UBUNTU}],Groups=[$SG_ID_PRIVATE]" \
--tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=UBUNTU-APACHE}]" \
--user-data "$USER_DATA_UBUNTU" \
--query "Instances[0].InstanceId" \
--output text)

echo "EC2 Ubuntu creada: $UBUNTU_INSTANCE_ID"

###########################################################################################################
######################################## EC2 WINDOWS (PUBLICA) ###########################################
###########################################################################################################

echo ""
echo "================ CREANDO EC2 WINDOWS ================"

WINDOWS_NI="{SubnetId=$SUBNET_PUBLIC,AssociatePublicIpAddress=true,DeviceIndex=0,Groups=[$SG_ID_PUBLIC]}"
if [ -n "$IP_WINDOWS" ]; then
  WINDOWS_NI="{SubnetId=$SUBNET_PUBLIC,AssociatePublicIpAddress=true,DeviceIndex=0,PrivateIpAddresses=[{Primary=true,PrivateIpAddress=$IP_WINDOWS}],Groups=[$SG_ID_PUBLIC]}"
fi

WINDOWS_INSTANCE_ID=$(aws ec2 run-instances \
--image-id "$AMI_WINDOWS" \
--instance-type "t2.micro" \
--key-name "$KEY_NAME" \
--network-interfaces "$WINDOWS_NI" \
--tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=WINDOWS}]" \
--query "Instances[0].InstanceId" \
--output text)

echo "EC2 Windows creada: $WINDOWS_INSTANCE_ID"

###########################################################################################################
######################################## FINAL ############################################################
###########################################################################################################

echo "Esperando instancias..."

aws ec2 wait instance-running --instance-ids $UBUNTU_INSTANCE_ID $WINDOWS_INSTANCE_ID

PUBLIC_IP_WINDOWS=$(aws ec2 describe-instances \
--instance-ids $WINDOWS_INSTANCE_ID \
--query "Reservations[0].Instances[0].PublicIpAddress" \
--output text)

echo ""
echo "================ INSTALACION FINALIZADA ================"
echo ""
echo "Windows RDP Public IP: $PUBLIC_IP_WINDOWS"
echo "EC2 Ubuntu (privada) IP: $IP_UBUNTU"
echo ""
echo "Desde la EC2 Windows, puedes hacer: curl http://$IP_UBUNTU para ver 'hola mundo'"
echo ""
