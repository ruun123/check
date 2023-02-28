resource "aws_security_group" "sonarqube_server_sg" {
  name        = "sonarqube-server-sg"
  description = "Allow inbound traffic"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow application from VPC"
    from_port   = var.sonar_port
    to_port     = var.sonar_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "SonarQube_Server_SG"
  }
}


#------------------------------------------------------------------------------------------------
# Create SonarQube Key Pair
#------------------------------------------------------------------------------------------------

resource "aws_key_pair" "sonarqube_key_pair" {
  key_name   = "sonarqube-key"
  public_key = var.sonar_public_key
}


#------------------------------------------------------------------------------------------------
# Create SonarQube EC2 Instance
#------------------------------------------------------------------------------------------------

resource "aws_instance" "sonar-ec2" {
  ami                         = var.ami
  instance_type               = var.ec2-instance-type
  key_name                    = aws_key_pair.sonarqube_key_pair.key_name
  subnet_id                   = var.public_subnet1_id
  vpc_security_group_ids      = [aws_security_group.sonarqube_server_sg.id]
  associate_public_ip_address = true
  root_block_device {
    volume_type = "gp2"
    volume_size = var.Root-volume-size
  }

  volume_tags = {
   	Name = "SonarQube_Server"
  }
  
  tags = {
    Name = "SonarQube_Server"
  }
  
  depends_on = [aws_db_instance.Sonar_db]

}

#------------------------------------------------------------------------------------------------
# Create ALB Target Group
#------------------------------------------------------------------------------------------------

resource "aws_alb_target_group" "alb_target_group" {
  name     = "sonarqube-tg"
  port     = var.sonar_port
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  tags = {
    Name = "SonarQube_TG"
  }

  health_check {
    healthy_threshold   = var.tg_healthy_threshold
    unhealthy_threshold = var.tg_unhealthy_threshold
    timeout             = var.tg_timeout
    interval            = var.tg_interval
    protocol            = "HTTP"
    path                = var.sonar_context
    port                = var.sonar_port
  }

  depends_on = [aws_instance.sonar-ec2]
}


#------------------------------------------------------------------------------------------------
# Associating EC2 with target group
#------------------------------------------------------------------------------------------------

resource "aws_alb_target_group_attachment" "alb_tg" {
  target_group_arn = aws_alb_target_group.alb_target_group.arn
  target_id        = aws_instance.sonar-ec2.id
  port             = var.sonar_port
}


#------------------------------------------------------------------------------------------------
# Create ALB Security Group
#------------------------------------------------------------------------------------------------

resource "aws_security_group" "sonarqube_alb_sg" {
  name        = "sonarqube-alb-sg"
  description = "Allow inbound traffic"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow 443 port from everywhere"
    from_port   = "443"
    to_port     = "443"
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow 80 port from everywhere"
    from_port   = "80"
    to_port     = "80"
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "SonarQube_ALB_SG"
  }
}

#------------------------------------------------------------------------------------------------
# Create ALB and its resources for SonarQube
#------------------------------------------------------------------------------------------------

resource "aws_alb" "alb" {
  name            = "sonarqube-alb"
  subnets         = [var.public_subnet1_id, var.public_subnet2_id]
  security_groups = [aws_security_group.sonarqube_alb_sg.id]
  idle_timeout    = var.alb_idle_timeout
  tags = {
    Name = "SonarQube_ALB"
  }

  depends_on = [aws_alb_target_group.alb_target_group]
}

resource "aws_alb_listener" "alb_listener" {
  load_balancer_arn = aws_alb.alb.arn
  port              = var.alb_listener_port
  protocol          = var.alb_listener_protocol
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.sonarqube.arn
  
  default_action {
    target_group_arn = aws_alb_target_group.alb_target_group.arn
    type             = "forward"
  }
}