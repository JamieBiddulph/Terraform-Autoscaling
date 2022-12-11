#!/bin/bash
aws autoscaling set-desired-capacity --auto-scaling-group-name $(terraform output -raw asg_name) --desired-capacity $1