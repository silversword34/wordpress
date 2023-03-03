#main.tf

#Finding Our VPC ID [ There is only one VPC configured, so will return 1 id. ]

data "aws_vpcs" "AF-VPC" {}

#Finding Recent Ubuntu Image

data "aws_ami" "ubuntu" {

    most_recent = true

    filter {
        name   = "name"
        values = ["*ubuntu-jammy-22.04-amd64-server*"]
    }

    filter {
        name = "virtualization-type"
        values = ["hvm"]
    }

        owners = ["099720109477"]

}

# Creating Key Pair #Wordpress-KEY

resource "tls_private_key" "pk" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "keypair" {
  key_name   = "Wordpress-KEY"       # Create a "myKey" to AWS!!
  public_key = tls_private_key.pk.public_key_openssh
}

resource "local_file" "ssh_key" {
  filename = "${aws_key_pair.keypair.key_name}.pem"
  content = tls_private_key.pk.private_key_pem

provisioner "local-exec" {
    command = "chmod 0400 Wordpress-KEY.pem"
}

}

#Creating Security Group for ingress ssh and HTTP, egress any port
#AFS Security Group creation

resource "aws_security_group" "WPSecurityGroup" {
        name        = "WPSG"
        description = "Allow Incoming SSH, Outgoing HTTP, Outgoing HTTPS"
        vpc_id = data.aws_vpcs.AF-VPC.ids[0]


        ingress {
                description = "Inbound SSH"
                from_port   = 22 
                to_port     = 22 
                protocol    = "tcp"
                cidr_blocks = ["0.0.0.0/0"]
        }

        ingress {
                description = "HTTP Port"
                from_port   = 80 
                to_port     = 80 
                protocol    = "tcp"
                cidr_blocks = ["0.0.0.0/0"]
        }

        egress {
                description = "Outbound All Traffic"
                from_port   = 0 
                to_port     = 0 
                protocol    = "-1"
                cidr_blocks = ["0.0.0.0/0"]
        }

        tags = {
                Name = "WPSG"
        }
}


resource "aws_instance" "ec2_instance" {

  ami             = "${data.aws_ami.ubuntu.image_id}"
  instance_type   = "t2.micro"

  # refering key which we created earlier
  key_name        = "Wordpress-KEY"

  # refering security group created earlier
  security_groups = [ "WPSG" ]
  
  depends_on = [
    aws_key_pair.keypair
  ]

  tags = {
                Name = "EC2 for Wordpress"
        }

}

resource "local_file" "ec2_instance_public_ip" {
  filename = "hosts"
  content = <<-EOT
    [wordpress]
    ${aws_instance.ec2_instance.public_ip}
  EOT

  depends_on = [
    aws_instance.ec2_instance
  ]

  provisioner "local-exec" {
    command = <<-EOT
        ansible-playbook -u ubuntu -i hosts --limit 'wordpress' --private-key Wordpress-KEY.pem wordpress-deploy.yml
        EOT
  }

}

output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.ec2_instance.id
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_instance.ec2_instance.public_ip
}

