# Use AWS as cloud provider and create resources in us-west-2
provider "aws" {
  region = "us-west-2"
}

# Fetch the account's default VPC
data "aws_vpc" "default" {
  default = true
}

# Fetch existing subnets in the default VPC
data "aws_subnets" "default" {
  # Attach to default VPC fetched above
  filter {
    name = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Fetch the latest Ubuntu 24.04 AMI
data "aws_ami" "ubuntu" {
  # Pick latest release
  most_recent = true

  # Filter down to exact image needed
  filter {
    name = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  # Official Canonical ID (prevents pulling fake images)
  owners = ["099720109477"]
}

# Create and configure Security Group
resource "aws_security_group" "minecraft-sg" {
  vpc_id = data.aws_vpc.default.id

  ingress {
    description = "Minecraft"
    from_port   = 25565
    to_port     = 25565
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create EC2 instance
resource "aws_instance" "minecraft-server" {
  # Uses the Ubuntu AMI found above
  ami = data.aws_ami.ubuntu.id

  # Configure common instance settings
  instance_type = "t3.medium"
  subnet_id = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.minecraft-sg.id]
  associate_public_ip_address = true

  # Attach Learner Lab's pre-configured IAM role
  # This grants the instance SSM permissions, which lets us run commands on it remotely without SSH (used by Ansible later)
  iam_instance_profile = "LabInstanceProfile"
  
  # Configure storage
  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }
}

# S3 bucket used by Ansible's SSM connection plugin to transfer files
resource "aws_s3_bucket" "ssm_bucket" {
  bucket = "minecraft-ssm"
  force_destroy = true # lets terraform destroy delete it even if non-empty
}

# Create hosts.ini file to specify server IP for ansible
resource "local_file" "hosts_ini" {
  content  = "[servers]\n${aws_instance.minecraft-server.id} ansible_connection=aws_ssm ansible_aws_ssm_region=us-west-2 ansible_aws_ssm_bucket_name=${aws_s3_bucket.ssm_bucket.bucket}"
  filename = "hosts.ini"
}