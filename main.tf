resource "aws_instance" "main" {  #Terraform creates the catalogue EC2 instance.
    ami= local.ami_id
    instance_type="t3.micro"
    vpc_security_group_ids = [local.sg_id]
    subnet_id = local.private_subnet_id
    tags = merge (
        local.common_tags,
        {
            Name="${local.common_name_suffix}-${var.component}"  # roboshop-dev-catalogue
        }
    )
  
}

# connect to instance using remote-exec provisioner through terraform_data

##Because of triggers_replace, the terraform_data.catalogue resource is tied to that EC2 instance.
resource "terraform_data" "main" {
  triggers_replace = [
    aws_instance.main.id   
  ]
 # Terraform connects to the catalogue instance via SSH (connection block).
connection {
      type        = "ssh"      
      user        = "ec2-user"
      password = "DevOps321"
      host = aws_instance.main.private_ip      
    }


# File provisioner copies catalogue.sh from your local machine to /tmp/catalogue.sh on the catalogue server.
provisioner "file" {
source = "bootstrap.sh" # Local file path
destination = "/tmp/bootstrap.sh" # Destination on EC2
}
# Remote‑exec provisioner runs commands inside the catalogue server:
  provisioner "remote-exec" {
    inline = [ 
         "chmod +x /tmp/bootstrap.sh",        
        "sudo sh /tmp/bootstrap.sh ${var.component} ${var.environment}"
     ]
  }
}

# stop the instance to take the image
resource "aws_ec2_instance_state" "main" {
  instance_id = aws_instance.main.id
  state       = "stopped"
  depends_on = [ terraform_data.main ]
}

resource "aws_ami_from_instance" "main" {
  name               = "${local.common_name_suffix}-${var.component}-ami"
  source_instance_id = aws_instance.main.id
  depends_on = [ aws_ec2_instance_state.main ]

      tags = merge (
        local.common_tags,
        {
            Name="${local.common_name_suffix}-${var.component}-ami"  # roboshop-dev-catalogue
        }
    )
}

resource "aws_lb_target_group" "main" {
  name        = "${local.common_name_suffix}-${var.component}"
  port        = local.tg_port  # if frontend port is 80 other wise port is 8080
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  deregistration_delay = 60

    health_check {
    healthy_threshold = 2
    unhealthy_threshold = 2
    interval = 10
    matcher ="200-299"
    protocol = "HTTP"
    path = local.health_check_path
    port = local.tg_port
    timeout = 2
    }
}

resource "aws_launch_template" "main" {
  name = "${local.common_name_suffix}-${var.component}"
  image_id = aws_ami_from_instance.main.id
  instance_initiated_shutdown_behavior = "terminate"
  instance_type = "t3.micro"

  vpc_security_group_ids = [local.sg_id]
  #when we run terraform apply again ,new template will be created with new AMI id
  update_default_version = true
# tags attached to the instance
  tag_specifications {
    resource_type = "instance"

    tags = merge (
        local.common_tags,
        {
            Name="${local.common_name_suffix}-${var.component}"  # roboshop-dev-catalogue
        }
    )
  }
# tags attached to the volumes
    tag_specifications {
    resource_type = "volume"

    tags = merge (
        local.common_tags,
        {
            Name="${local.common_name_suffix}-${var.component}"  # roboshop-dev-catalogue
        }
    )
  }

  # tags attached to the launch templet
    tags = merge (
        local.common_tags,
        {
            Name="${local.common_name_suffix}-${var.component}"  # roboshop-dev-catalogue
        }
    )
}

resource "aws_autoscaling_group" "main" {
  name                      = "${local.common_name_suffix}-${var.component}"
  max_size                  = 10
  min_size                  = 1
  health_check_grace_period = 100
  health_check_type         = "ELB"
  desired_capacity          = 4
  force_delete              = false
   launch_template {
    id      = aws_launch_template.main.id
    version = aws_launch_template.main.latest_version
  }
  vpc_zone_identifier       = [ local.private_subnet_ids ]
  target_group_arns = [aws_lb_target_group.main.arn]

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50 # atlease 50% of the application should be uo and running
    }
    triggers = ["launch_template"]
  }

  dynamic  "tag" { # we will get iterator with name as tag
    for_each = merge(
      local.common_tags,
      {
      name="${local.common_name_suffix}-${var.component}"
      }
    )
    content { 
      key =tag.key  
    value               = tag.value
    propagate_at_launch = true
  }
  }
  timeouts {
    delete = "15m"
  }

}

resource "aws_autoscaling_policy" "main" {
  autoscaling_group_name = aws_autoscaling_group.main.name
  name                   = "${local.common_name_suffix}-${var.component}"
  policy_type            = "TargetTrackingScaling"

  # ... other configuration ...

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 75.0
  }
}

resource "aws_lb_listener_rule" "catalogue_local" {
  listener_arn = local.listener_arn
  priority     = var.rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }

  condition {
    host_header {
      values = ["catalogue.backend-alb-${var.environment}.${var.domain_name}"]
    }
  }
}


##Because of triggers_replace, the terraform_data.catalogue resource is tied to that EC2 instance.
resource "terraform_data" "main_local" {
  triggers_replace = [
    aws_instance.main.id   
  ]
  depends_on = [ aws_autoscaling_policy.main ]

# Remote‑exec provisioner runs commands inside the catalogue server:
  provisioner "local-exec" {
   command = "aws ec2 terminate-instances --instance-ids ${aws_instance.main.id}"
  }
}
