############################################
# Provider
############################################
provider "aws" {
  region = "ap-south-2"
}

############################################
# Step 1: Network Setup - VPC, Subnets, IGW, Route Table
############################################
resource "aws_vpc" "main_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "MainVPC" }
}

resource "aws_subnet" "subnet_1" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "ap-south-2a"

  tags = { Name = "Subnet-1" }
}

resource "aws_subnet" "subnet_2" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-south-2b"

  tags = { Name = "Subnet-2" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main_vpc.id

  tags = { Name = "MainIGW" }
}

resource "aws_route_table" "main_route_table" {
  vpc_id = aws_vpc.main_vpc.id

  tags = { Name = "MainRouteTable" }
}

resource "aws_route" "internet_route" {
  route_table_id         = aws_route_table.main_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "subnet1_assoc" {
  subnet_id      = aws_subnet.subnet_1.id
  route_table_id = aws_route_table.main_route_table.id
}

resource "aws_route_table_association" "subnet2_assoc" {
  subnet_id      = aws_subnet.subnet_2.id
  route_table_id = aws_route_table.main_route_table.id
}

############################################
# Step 2: Security Groups
############################################
resource "aws_security_group" "web_sg" {
  name        = "web_sg"
  description = "Allow SSH, HTTP, HTTPS, Custom TCP 8080"
  vpc_id      = aws_vpc.main_vpc.id

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
    description = "Custom TCP 8080"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "WebSG" }
}

############################################
# Step 3: Generate Key Pair for EC2
############################################
resource "tls_private_key" "deployer" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = tls_private_key.deployer.public_key_openssh
}

resource "local_file" "private_key" {
  content         = tls_private_key.deployer.private_key_pem
  filename        = "terraform/deployer.pem"
  file_permission = "0400"
}


############################################
# Step 4: IAM Role and Instance Profile
############################################
resource "aws_iam_role" "ec2_role" {
  name = "ec2_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2_policy" {
  name   = "ec2_policy"
  role   = aws_iam_role.ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "s3:*"
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2_profile"
  role = aws_iam_role.ec2_role.name
}

############################################
# Step 5: EC2 Instance
############################################
resource "aws_instance" "web_server" {
  ami                    = "ami-0cbe896ecf507b2a4" # Ubuntu 20.04 example
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.subnet_1.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  key_name               = aws_key_pair.deployer.key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  tags = { Name = "web-server" }
}

############################################
# Step 6: RDS MySQL Instance
############################################
resource "aws_db_subnet_group" "main_db_subnet_group" {
  name       = "main-db-subnet-group"
  subnet_ids = [aws_subnet.subnet_1.id, aws_subnet.subnet_2.id]

  tags = { Name = "Main DB subnet group" }
}

resource "aws_db_instance" "main_db" {
  engine               = "mysql"
  instance_class       = "db.t4g.micro"
  allocated_storage    = 20
  storage_type         = "gp2"
  db_name              = "mydb"
  username             = "admin"
  password             = "passw0rd"
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  db_subnet_group_name = aws_db_subnet_group.main_db_subnet_group.name
  multi_az             = false
  publicly_accessible  = false
  skip_final_snapshot  = true
}

############################################
# Step 7: Ansible Inventory
############################################
resource "local_file" "ansible_inventory" {
  content = <<EOT
[web]
web1 ansible_host=${aws_instance.web_server.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=terraform/deployer.pem

[all:vars]
ansible_python_interpreter=/usr/bin/python3
EOT
  filename = "ansible/hosts.ini"
}

############################################
# Step 8: Outputs
############################################
output "ec2_public_ip" {
  value = aws_instance.web_server.public_ip
}

output "private_key_path" {
  value = local_file.private_key.filename
}
