#!/bin/bash

USER_CONTEXT=$(whoami)
EC2_USER="ec2-user"

if [[ $USER_CONTEXT != "$EC2_USER" ]]; then
  echo "Error! This script is only meant to be run on Amazon EC2 as user 'ec2-user'"
  exit 1
fi

# Make nvm available in script context
. ~/.nvm/nvm.sh

# Make sure shell commands exist before usage
if ! command -v sudo &>/dev/null; then
  echo "'sudo' command could not be found"
  exit 1
fi
if ! command -v yum &>/dev/null; then
  echo "'yum' command could not be found"
  exit 1
fi
if ! command -v cut &>/dev/null; then
  echo "'cut' command could not be found"
  exit 1
fi
if ! command -v git &>/dev/null; then
  echo "'git' command could not be found"
  exit 1
fi
if ! command -v nvm &>/dev/null; then
  echo "'nvm' command could not be found"
  exit 1
fi
if ! command -v npm &>/dev/null; then
  echo "'npm' command could not be found"
  exit 1
fi
if ! command -v curl &>/dev/null; then
  echo "'curl' command could not be found"
  exit 1
fi
if ! command -v unzip &>/dev/null; then
  echo "'unzip' command could not be found"
  exit 1
fi

clear_screen() {
  # printf "\033c"
  echo "==================================================================================================="
}

prompt_to_continue() {
  clear_screen
  read -rp "$1. Press enter to continue."
}

prompt_to_continue_done() {
  clear_screen
  echo "$1."
  echo ""
  read -rp "Done. Press enter to continue."
}

Q_00="Follow the on-screen prompts to configure your Cloud9 EC2 environment"
prompt_to_continue "$Q_00"

# Update linux package manager
Q_01="This script will now: update yum"
prompt_to_continue "$Q_01"
sudo yum update -y
prompt_to_continue_done "$Q_01"

# Configure Git
GIT_USER_NAME=$(git config user.name)
GIT_USER_EMAIL=$(git config user.email)
if [ -z "$GIT_USER_NAME" ] || [ -z "$GIT_USER_EMAIL" ]; then
  Q_02="This script will now: configure git"
  prompt_to_continue "$Q_02"

  # Prompt for name
  read -rp 'What is your full name?     ' NAME
  if [ -z "$NAME" ]; then
    echo "Error! You didn't type in your full name."
    echo "Re-run this script and try again."
    exit 1
  fi

  # Prompt for email
  read -rp 'What is your email address? ' EMAIL
  if [ -z "$EMAIL" ]; then
    echo "Error! You didn't type in your email address."
    echo "Re-run this script and try again."
    exit 1
  fi
  git config --global user.name "$NAME"
  git config --global user.email "$EMAIL"
  prompt_to_continue_done "$Q_02"
fi

Q_03="This script will now: update pip and install a git helper"
prompt_to_continue "$Q_03"
curl -O https://bootstrap.pypa.io/get-pip.py
python get-pip.py --user
rm -rf ./get-pip.py
python -m pip install git-remote-codecommit
prompt_to_continue_done "$Q_03"

# Install current version of AWS CDK
Q_04="This script will now: install and bootstrap the AWS CDK"
prompt_to_continue "$Q_04"
npm install -g aws-cdk
AWS_ACCOUNT_NUMBER=$(aws sts get-caller-identity --query Account --output text)
if [ -z "$AWS_ACCOUNT_NUMBER" ]; then
  read -rp 'What is your AWS account number?    ' AWS_ACCOUNT_NUMBER
fi
if [ -z "$AWS_ACCOUNT_NUMBER" ]; then
  echo "Error! You didn't type in your AWS account number."
  echo "Re-run this script and try again."
  exit 1
fi
export CDK_NEW_BOOTSTRAP=1
AWS_DEFAULT_REGION=$(aws configure get region)
if [ -z "$AWS_DEFAULT_REGION" ]; then
  read -rp 'What is your default AWS region? (us-east-1, us-west-2, etc.)   ' AWS_DEFAULT_REGION
fi
if [ -z "$AWS_DEFAULT_REGION" ]; then
  echo "Error! You didn't type in your default AWS region."
  echo "Re-run this script and try again."
  exit 1
fi
cdk bootstrap "aws://$AWS_ACCOUNT_NUMBER/$AWS_DEFAULT_REGION"
prompt_to_continue_done "$Q_04"

# Ensure LTS version of Node.js is installed
Q_05="This script will now: install the current 'LTS' version of Node.js"
CURRENT_NODE_LTS_NAME="fermium" # <= will require update to new LTS 10/2021
EC2_NODE_VERSION=$(node --version)
CURRENT_NODE_LTS_VERSION=$(nvm version-remote --lts=$CURRENT_NODE_LTS_NAME)
if [[ $EC2_NODE_VERSION != "$CURRENT_NODE_LTS_VERSION" ]]; then
  prompt_to_continue "$Q_05"
  nvm install --lts=$CURRENT_NODE_LTS_NAME
  nvm alias default lts/$CURRENT_NODE_LTS_NAME
  nvm uninstall "$EC2_NODE_VERSION"
  prompt_to_continue_done "$Q_05"
fi

# Install current version of TypeScript
Q_06="This script will now: install TypeScript"
prompt_to_continue "$Q_06"
npm i -g typescript@"~3.9.9" # AWS CDK v1.93.0 TypeScript version
prompt_to_continue_done "$Q_06"

# Increase EBS volume size
Q_07="This script will now: increase the size of the EBS volume to 30 GiB"
prompt_to_continue "$Q_07"
SIZE=30

# Get the ID of the environment host Amazon EC2 instance.
INSTANCEID=$(curl http://169.254.169.254/latest/meta-data/instance-id)

# Get the ID of the Amazon EBS volume associated with the instance.
VOLUMEID=$(aws ec2 describe-instances \
  --instance-id "$INSTANCEID" \
  --query "Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId" \
  --output text)

# Resize the EBS volume.
aws ec2 modify-volume --volume-id "$VOLUMEID" --size "$SIZE"

# Wait for the resize to finish.
while [ \
  "$(aws ec2 describe-volumes-modifications \
    --volume-id "$VOLUMEID" \
    --filters Name=modification-state,Values="optimizing","completed" \
    --query "length(VolumesModifications)"\
    --output text)" != "1" ]; do
sleep 1
done

#Check if we're on an NVMe filesystem
if [ "$(readlink -f /dev/xvda)" = "/dev/xvda" ]
then
  # Rewrite the partition table so that the partition takes up all the space that it can.
  sudo growpart /dev/xvda 1

  # Expand the size of the file system.
  # Check if we are on AL2
  STR=$(cat /etc/os-release)
  SUB="VERSION_ID=\"2\""
  if [[ "$STR" == *"$SUB"* ]]
  then
    sudo xfs_growfs -d /
  else
    sudo resize2fs /dev/xvda1
  fi

else
  # Rewrite the partition table so that the partition takes up all the space that it can.
  sudo growpart /dev/nvme0n1 1

  # Expand the size of the file system.
  # Check if we're on AL2
  STR=$(cat /etc/os-release)
  SUB="VERSION_ID=\"2\""
  if [[ "$STR" == *"$SUB"* ]]
  then
    sudo xfs_growfs -d /
  else
    sudo resize2fs /dev/nvme0n1p1
  fi
fi
prompt_to_continue_done "$Q_07"

# Uninstall AWS CLI V1 if installed
Q_08="This script will now: uninstall AWS CLI V1"
AWS_CLI_VERSION=$(aws --version | cut -d'/' -f2 | cut -c1-1)
echo "Installed version: $AWS_CLI_VERSION"
if [[ $AWS_CLI_VERSION == "1" ]]; then
  prompt_to_continue "$Q_08"
  sudo rm -rf /usr/local/aws
  sudo rm -rf /usr/bin/aws
  sudo rm /usr/local/bin/aws
  prompt_to_continue_done "$Q_08"
fi

# Install AWS CLI V2 if not installed
Q_09="This script will now: install AWS CLI V2"
echo "Installed version: $AWS_CLI_VERSION"
if [[ $AWS_CLI_VERSION != "2" ]]; then
  prompt_to_continue "$Q_09 "
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip awscliv2.zip
  sudo ./aws/install
  rm -rf awscliv2.zip
  rm -rf ./aws/
  prompt_to_continue_done "$Q_09"
fi

Q_10="This script will now: configure the AWS CLI V2 with your credentials"
prompt_to_continue "$Q_10"
sudo rm -rf ~/.aws/credentials
sudo rm -rf ~/.aws/config
aws configure
AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id)
AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key)
if [ -z "$AWS_ACCESS_KEY_ID" ]; then
  echo "Error! You didn't type in your AWS access key id."
  echo "Re-run this script and try again."
  exit 1
fi
if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
  echo "Error! You didn't type in your AWS secret access key."
  echo "Re-run this script and try again."
  exit 1
fi
TECHNICAL_TRAINER_ROLE_ARN="arn:aws:iam::403112560303:role/TechTrainerCloud9Stack-codeCommitReadOnlyAccess982-VWL5HSK3TV97"
{
  echo ""
  echo "[technical-trainer]"
  echo "source_profile = default"
  echo "aws_access_key_id = $AWS_ACCESS_KEY_ID"
  echo "aws_secret_access_key = $AWS_SECRET_ACCESS_KEY"
  echo "role_arn = $TECHNICAL_TRAINER_ROLE_ARN"
} >> ~/.aws/credentials
unset AWS_SECRET_ACCESS_KEY
{
  echo ""
  echo "[profile technical-trainer]"
  echo "region = $AWS_DEFAULT_REGION"
  echo "output = json"
} >> ~/.aws/config
prompt_to_continue_done "$Q_10"

Q_11="This script will now: clone all available repositories"
prompt_to_continue "$Q_11"
aws sts assume-role --role-arn "$TECHNICAL_TRAINER_ROLE_ARN" --role-session-name AWSCLI-Session
git clone codecommit://technical-trainer@aai-architecting-on-aws ~/environment/src/aai-architecting-on-aws
prompt_to_continue_done "$Q_11"

clear_screen
echo "Your EC2 environment has been configured."
echo "Close this terminal window and open another before running any additional scripts."
read -rp "Press enter to exit."
