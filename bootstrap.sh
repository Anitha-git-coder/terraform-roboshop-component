#!/bin/bash

#Inside catalogue.sh, Ansible is installed and ansible-pull configures catalogue.
component=$1
environment=$2
dnf install ansible -y
# ansible-pull -U https://github.com/Anitha-git-coder/ansible-roboshop-roles-tf.git main.yaml -e component=$component
REPO_URL=https://github.com/Anitha-git-coder/ansible-roboshop-roles-tf.git
REPO_DIR=/opt/roboshop/ansible
ANSIBLE_DIR=ansible-roboshop-roles-tf  # dir after clone

mkdir -p $REPO_DIR
mkdir -p /var/log/roboshop/
touch ansible.log

cd $REPO_DIR
# check if ansible already clone or not

if [ -d $ANSIBLE_DIR ]; then
 
 cd $ANSIBLE_DIR #open the dir
 git pull  
 else
 git clone $REPO_URL 
 cd $ANSIBLE_DIR   
 fi

ansible-playbook -e component=$component -e env=$environment main.yaml