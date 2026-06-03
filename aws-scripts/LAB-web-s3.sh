#!/bin/bash

set -e

echo "=========== PRACTICA S3 + EC2 ==========="

read -p "Nombre alumno: " ALUMNO

REGION="us-east-1"
AMI_ID="ami-04b4f1a9cf54c11d0"

BUCKET_NAME="web-${ALUMNO,,}-$(date +%s)"

KEY_NAME="${ALUMNO}-key"

#################################################################

# CREAR WEB LOCAL

#################################################################

mkdir -p web/css
mkdir -p web/img

cat > web/index.html <<EOF

<!DOCTYPE html>

<html lang="es">
<head>
<meta charset="UTF-8">
<title>Web AWS S3</title>
<link rel="stylesheet" href="css/style.css">
</head>
<body>

<header>
<h1>Mi sitio AWS</h1>
<p>Descargado desde Amazon S3 usando AWS CLI</p>
</header>

<section>
<img src="img/aws.png" width="300">
</section>

</body>
</html>
EOF

cat > web/css/style.css <<EOF
body{
font-family: Arial;
text-align:center;
background:#f4f4f4;
}

header{
background:#232f3e;
color:white;
padding:40px;
}

img{
margin-top:30px;
}
EOF

# Imagen de ejemplo

touch web/img/aws.png

#################################################################

# CREAR BUCKET S3

#################################################################

echo "Creando bucket..."

aws s3 mb s3://$BUCKET_NAME --region $REGION

#################################################################

# SUBIR WEB A S3

#################################################################

echo "Subiendo web..."

aws s3 cp web s3://$BUCKET_NAME --recursive

#################################################################

# ROLE IAM PARA EC2

#################################################################

cat > trust-policy.json <<EOF
{
"Version":"2012-10-17",
"Statement":[
{
"Effect":"Allow",
"Principal":{
"Service":"ec2.amazonaws.com"
},
"Action":"sts:AssumeRole"
}
]
}
EOF

ROLE_NAME="EC2S3Role-${ALUMNO}"

aws iam create-role 
--role-name $ROLE_NAME 
--assume-role-policy-document file://trust-policy.json

cat > s3-policy.json <<EOF
{
"Version":"2012-10-17",
"Statement":[
{
"Effect":"Allow",
"Action":[
"s3:GetObject",
"s3:ListBucket"
],
"Resource":[
"arn:aws:s3:::$BUCKET_NAME",
"arn:aws:s3:::$BUCKET_NAME/*"
]
}
]
}
EOF

aws iam put-role-policy 
--role-name $ROLE_NAME 
--policy-name S3ReadPolicy 
--policy-document file://s3-policy.json

aws iam create-instance-profile 
--instance-profile-name $ROLE_NAME

aws iam add-role-to-instance-profile 
--instance-profile-name $ROLE_NAME 
--role-name $ROLE_NAME

echo "Esperando propagacion IAM..."
sleep 20

#################################################################

# KEYPAIR

#################################################################

aws ec2 create-key-pair 
--key-name $KEY_NAME 
--query KeyMaterial 
--output text > ${KEY_NAME}.pem

chmod 400 ${KEY_NAME}.pem

#################################################################

# SECURITY GROUP

#################################################################

DEFAULT_VPC=$(aws ec2 describe-vpcs 
--filters Name=isDefault,Values=true 
--query 'Vpcs[0].VpcId' 
--output text)

SG_ID=$(aws ec2 create-security-group 
--group-name SG-S3-${ALUMNO} 
--description "Web S3" 
--vpc-id $DEFAULT_VPC 
--query GroupId 
--output text)

aws ec2 authorize-security-group-ingress 
--group-id $SG_ID 
--protocol tcp 
--port 22 
--cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress 
--group-id $SG_ID 
--protocol tcp 
--port 80 
--cidr 0.0.0.0/0


echo ""
echo "========================================"
echo "BUCKET:"
echo "s3://$BUCKET_NAME"
echo ""
echo "http://$PUBLIC_IP"
echo "========================================"
