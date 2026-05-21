#!/bin/bash

set -euo pipefail

REGION="us-east-1"
export AWS_DEFAULT_REGION=$REGION

echo "======================================"
echo " AWS LAB CLEANUP (FINAL VERSION)"
echo " Región: $REGION"
echo "======================================"

echo ""
read -p "Escribe YES para confirmar eliminación total: " CONFIRM
if [[ "$CONFIRM" != "YES" ]]; then
  echo "Cancelado."
  exit 1
fi

########################################
# 1. TERMINAR INSTANCIAS EC2
########################################
echo "Terminando instancias EC2..."

INSTANCES=$(aws ec2 describe-instances \
  --query "Reservations[].Instances[?State.Name!='terminated'].InstanceId" \
  --output text)

if [[ -n "$INSTANCES" ]]; then
  aws ec2 terminate-instances --instance-ids $INSTANCES >/dev/null || true
  echo "EC2 terminadas: $INSTANCES"
fi

sleep 10

########################################
# 2. NAT GATEWAYS (con espera)
########################################
echo "Eliminando NAT Gateways..."

NATS=$(aws ec2 describe-nat-gateways \
  --query "NatGateways[?State!='deleted'].NatGatewayId" \
  --output text)

for nat in $NATS; do
  echo "Eliminando NAT: $nat"
  aws ec2 delete-nat-gateway --nat-gateway-id "$nat" || true
  echo "Esperando NAT se elimine..."
  aws ec2 wait nat-gateway-deleted --nat-gateway-ids "$nat" 2>/dev/null || true
  sleep 5
done

########################################
# 3. ELASTIC IPs
########################################
echo "Liberando Elastic IPs..."

EIPS=$(aws ec2 describe-addresses \
  --query "Addresses[].AllocationId" \
  --output text)

for eip in $EIPS; do
  aws ec2 release-address --allocation-id "$eip" || true
  echo "EIP liberada: $eip"
done

sleep 5

########################################
# 4. VPC ENDPOINTS
########################################
echo "Eliminando VPC Endpoints..."

VPCE=$(aws ec2 describe-vpc-endpoints \
  --query "VpcEndpoints[].VpcEndpointId" \
  --output text)

for vpce in $VPCE; do
  aws ec2 delete-vpc-endpoints --vpc-endpoint-ids "$vpce" || true
  echo "VPCE eliminado: $vpce"
done

sleep 5

########################################
# 5. NETWORK INTERFACES
########################################
echo "Eliminando ENIs (forzado)..."

ENIS=$(aws ec2 describe-network-interfaces \
  --query "NetworkInterfaces[].NetworkInterfaceId" \
  --output text)

for eni in $ENIS; do

  ATTACHMENT=$(aws ec2 describe-network-interfaces \
    --network-interface-ids "$eni" \
    --query "NetworkInterfaces[0].Attachment.AttachmentId" \
    --output text 2>/dev/null || true)

  if [[ "$ATTACHMENT" != "None" && -n "$ATTACHMENT" ]]; then
    aws ec2 detach-network-interface --attachment-id "$ATTACHMENT" --force 2>/dev/null || true
    sleep 2
  fi

  aws ec2 delete-network-interface --network-interface-id "$eni" 2>/dev/null || true
  echo "ENI eliminado: $eni"

done

sleep 10

########################################
# 6. INTERNET GATEWAYS
########################################
echo "Eliminando Internet Gateways..."

IGWS=$(aws ec2 describe-internet-gateways \
  --query "InternetGateways[].InternetGatewayId" \
  --output text)

for igw in $IGWS; do

  VPC=$(aws ec2 describe-internet-gateways \
    --internet-gateway-ids "$igw" \
    --query "InternetGateways[0].Attachments[0].VpcId" \
    --output text)

  IS_DEFAULT=$(aws ec2 describe-vpcs \
    --vpc-ids "$VPC" \
    --query "Vpcs[0].IsDefault" \
    --output text)

  if [[ "$IS_DEFAULT" == "False" ]]; then
    aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$VPC" || true
    aws ec2 delete-internet-gateway --internet-gateway-id "$igw" || true
    echo "IGW eliminado: $igw"
  else
    echo "Ignorado IGW default VPC"
  fi

done

sleep 5

########################################
# 7. ROUTE TABLES
########################################
echo "Eliminando Route Tables..."

RTS=$(aws ec2 describe-route-tables \
  --query "RouteTables[].RouteTableId" \
  --output text)

for rt in $RTS; do

  MAIN=$(aws ec2 describe-route-tables \
    --route-table-ids "$rt" \
    --query "RouteTables[0].Associations[0].Main" \
    --output text 2>/dev/null || echo "False")

  if [[ "$MAIN" == "False" ]]; then
    aws ec2 delete-route-table --route-table-id "$rt" || true
    echo "Route table eliminada: $rt"
  fi

done

sleep 5

########################################
# 8. SECURITY GROUPS
########################################
echo "Eliminando Security Groups..."

SGS=$(aws ec2 describe-security-groups \
  --query "SecurityGroups[?GroupName!='default'].GroupId" \
  --output text)

for sg in $SGS; do
  aws ec2 delete-security-group --group-id "$sg" || true
  echo "SG eliminado: $sg"
done

sleep 5

########################################
# 9. SUBNETS
########################################
echo "Eliminando Subnets..."

SUBNETS=$(aws ec2 describe-subnets \
  --query "Subnets[].SubnetId" \
  --output text)

for subnet in $SUBNETS; do

  VPC=$(aws ec2 describe-subnets \
    --subnet-ids "$subnet" \
    --query "Subnets[0].VpcId" \
    --output text)

  IS_DEFAULT=$(aws ec2 describe-vpcs \
    --vpc-ids "$VPC" \
    --query "Vpcs[0].IsDefault" \
    --output text)

  if [[ "$IS_DEFAULT" == "False" ]]; then
    aws ec2 delete-subnet --subnet-id "$subnet" || true
    echo "Subnet eliminada: $subnet"
  fi

done

sleep 5

########################################
# 10. KEY PAIRS (except default)
########################################
echo "Eliminando Key Pairs (excepto default)..."

KEYS=$(aws ec2 describe-key-pairs \
  --query "KeyPairs[?KeyName!='default'].KeyName" \
  --output text)

for key in $KEYS; do
  aws ec2 delete-key-pair --key-name "$key" || true
  echo "Key Pair eliminado: $key"
done

sleep 5

########################################
# 11. VPCs (último paso, con RETARDO largo)
########################################
echo "Eliminando VPCs de laboratorio..."
echo "Esperando 120 segundos extra para asegurar que todo esté completamente liberado..."
sleep 120

VPCS=$(aws ec2 describe-vpcs \
  --query "Vpcs[?IsDefault==\`false\`].VpcId" \
  --output text)

for vpc in $VPCS; do
  echo "Borrando VPC: $vpc"
  aws ec2 delete-vpc --vpc-id "$vpc" || true
  echo "VPC eliminada: $vpc"
done

echo ""
echo "======================================"
echo " LIMPIEZA COMPLETADA EN $REGION"
echo "======================================"
