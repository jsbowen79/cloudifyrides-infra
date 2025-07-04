provider "aws" {
  region = var.aws_region
}

resource "tls_private_key" "deployer" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "deployer" {
  key_name   = "cloudifyrides-key"
  public_key = tls_private_key.deployer.public_key_openssh
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "cloudifyrides-vpc"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "allow_ssh_http" {
  name        = "allow_ssh_http"
  description = "Allow SSH and HTTP(s) access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "NodePort traffic within SG"
    from_port   = 30080
    to_port     = 30081
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "k3s_node" {
  ami                    = var.ubuntu_ami
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public.id
  private_ip             = "10.0.1.10"
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.allow_ssh_http.id]

  user_data = file("${path.module}/scripts/k3s-node.sh")

  tags = {
    Name = "k3s-node"
  }
}

resource "aws_instance" "nginx_proxy" {
  ami                    = var.ubuntu_ami
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public.id
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.allow_ssh_http.id]

  user_data = file("${path.module}/scripts/nginx-proxy.sh")

  tags = {
    Name = "nginx-proxy"
  }
}

resource "aws_eip" "nginx" {
}

resource "aws_eip_association" "nginx_eip_assoc" {
  allocation_id = aws_eip.nginx.id
  instance_id   = aws_instance.nginx_proxy.id
}

output "nginx_ip" {
  value = aws_eip.nginx.public_ip
}

output "private_key" {
  value     = tls_private_key.deployer.private_key_pem
  sensitive = false
}
