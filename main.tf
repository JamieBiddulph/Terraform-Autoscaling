// TODO
// - Setup HTTPS and SSL Certificates
// - Setup custom domain
// - Configure Secure rules for the Security groups
// - Configure / Enable CloudFlare for fronend caching

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Name = var.tag_name
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "template_file" "script" {
  template = file("script.tpl")
  vars = {
    efs_id = "${aws_efs_file_system.demo-infastructure.id}"
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.77.0"

  name = "main-vpc"
  cidr = "10.0.0.0/16"

  azs                  = data.aws_availability_zones.available.names
  public_subnets       = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  enable_dns_hostnames = true
  enable_dns_support   = true

}

resource "aws_efs_file_system" "demo-infastructure" {
  creation_token = "demo-infastructure"
  encrypted      = true
}

resource "aws_efs_access_point" "demo-infastructure" {
  file_system_id = aws_efs_file_system.demo-infastructure.id
}

# Don't currently have a way to get the subnet ids from the vpc, so comment these out on first run and then apply them on the second run
# with the subnet_id populated
resource "aws_efs_mount_target" "demo-infastructure-az1" {
  file_system_id  = aws_efs_file_system.demo-infastructure.id
  subnet_id       = "subnet-030dbe8370e722e66"
  security_groups = [aws_security_group.demo-infastructure_instance.id]
}

resource "aws_efs_mount_target" "demo-infastructure-az2" {
  file_system_id  = aws_efs_file_system.demo-infastructure.id
  subnet_id       = "subnet-03b3dd294534b2cc1"
  security_groups = [aws_security_group.demo-infastructure_instance.id]
}

resource "aws_efs_mount_target" "demo-infastructure-az3" {
  file_system_id  = aws_efs_file_system.demo-infastructure.id
  subnet_id       = "subnet-0acd3c34894345924"
  security_groups = [aws_security_group.demo-infastructure_instance.id]
}

data "aws_ami" "amazon-linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}

resource "aws_launch_configuration" "demo-infastructure" {
  name_prefix          = "demo-infastructure-asg-"
  image_id             = data.aws_ami.amazon-linux.id
  instance_type        = "t2.micro"
  user_data            = data.template_file.script.rendered
  security_groups      = [aws_security_group.demo-infastructure_instance.id]
  key_name             = "demo-infa"
  iam_instance_profile = "arn:aws:iam::153653607455:instance-profile/AWS_Code_Deploy"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "demo-infastructure" {
  name                 = "demo-infastructure"
  min_size             = 1
  max_size             = 3
  desired_capacity     = 1
  launch_configuration = aws_launch_configuration.demo-infastructure.name
  vpc_zone_identifier  = module.vpc.public_subnets

  lifecycle {
    ignore_changes = [desired_capacity, target_group_arns]
  }

  tag {
    key                 = "Name"
    value               = var.tag_name
    propagate_at_launch = true
  }
}

resource "aws_lb" "demo-infastructure" {
  name               = "demo-infastructure-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.demo-infastructure_lb.id]
  subnets            = module.vpc.public_subnets
}

resource "aws_lb_listener" "demo-infastructure" {
  load_balancer_arn = aws_lb.demo-infastructure.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.demo-infastructure.arn
  }
}

resource "aws_lb_target_group" "demo-infastructure" {
  name     = "demo-infastructure"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id
}


resource "aws_autoscaling_attachment" "demo-infastructure" {
  autoscaling_group_name = aws_autoscaling_group.demo-infastructure.id
  alb_target_group_arn   = aws_lb_target_group.demo-infastructure.arn
}

resource "aws_security_group" "demo-infastructure_instance" {
  name = "demo-infastructure-instance"
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.demo-infastructure_lb.id]
  }

  ingress {
    from_port = 2049
    to_port   = 2049
    protocol  = "tcp"
    self      = true
  }

  ingress {
    from_port = 3306
    to_port   = 3306
    protocol  = "tcp"
    self      = true
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.demo-infastructure_lb.id]
  }

  egress {
    from_port = 3306
    to_port   = 3306
    protocol  = "tcp"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  vpc_id = module.vpc.vpc_id
}

resource "aws_security_group" "demo-infastructure_lb" {
  name = "demo-infastructure-lb"
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  vpc_id = module.vpc.vpc_id
}

resource "aws_secretsmanager_secret" "demo-infastructure-wp-secrets" {
  name = "demo-infastructure-wp-secrets"
}

resource "aws_db_subnet_group" "demo-infastructure" {
  name       = "main"
  subnet_ids = ["subnet-030dbe8370e722e66", "subnet-03b3dd294534b2cc1", "subnet-0acd3c34894345924"]
}

resource "aws_db_instance" "demo-infastructure" {
  allocated_storage    = 5
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t3.micro"
  username             = var.dbuser
  password             = var.dbpass
  db_name              = var.dbuser
  parameter_group_name = "default.mysql5.7"
  skip_final_snapshot  = true
  db_subnet_group_name = aws_db_subnet_group.demo-infastructure.name
  vpc_security_group_ids = [aws_security_group.demo-infastructure_instance.id]

}
