provider "aws" {
  region = "ap-southeast-1"
}
locals {
  vpc_cidr_block = "10.0.0.0/16"
  region         = "ap-southeast-1"
}
resource "random_pet" "this" {
  for_each = var.instance_details
  length   = 1
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name           = "coedestar-tuyetvoi-labvpc-001"
  cidr           = local.vpc_cidr_block
  azs            = ["${local.region}a", "${local.region}b"]
  public_subnets = ["10.0.0.0/24", "10.0.1.0/24"]
}

resource "aws_security_group" "this" {
  name        = "allow-ssh-http-lab-system"
  description = "Allow SSH inbound traffic"
  vpc_id      = module.vpc.vpc_id

  ingress { // inbound
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress { // outbound
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

### Export key pair and save to local file in this folder
resource "tls_private_key" "private_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "keypair" {
  key_name   = "codestar-deployment-key"
  public_key = tls_private_key.private_key.public_key_openssh

  provisioner "local-exec" {
    command = "echo '${tls_private_key.private_key.private_key_pem}' > ./codestar-deployment-key.pem && chmod 400 ./codestar-deployment-key.pem"
  }
}


resource "aws_instance" "main" {
  for_each               = var.instance_details
  ami                    = each.value.ami
  instance_type          = each.value.instance_type
  vpc_security_group_ids = [aws_security_group.this.id]
  associate_public_ip_address = true
  key_name = aws_key_pair.keypair.key_name

  subnet_id = module.vpc.public_subnets[0]

  tags = merge({
    "Name" = random_pet.this[each.key].id
  })
}

variable "instance_details" {
  default = {
    amzn3 = {
      ami  = "ami-06d753822bd94c64e" // ami name: al2023-ami-2023.5.20240701.0-kernel-6.1-x86_64
      instance_type = "t2.micro"
    }
    ubuntu = {
      ami  = "ami-060e277c0d4cce553" // ami name: ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-20240701.1
      instance_type = "t2.micro"
    }
  }
}

output "ipv4_address" {
    value = { for k, v in aws_instance.main : k => v.public_ip }
}