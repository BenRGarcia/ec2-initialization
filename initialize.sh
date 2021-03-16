#!/bin/bash

USER_CONTEXT=$(whoami)
EC2_USER="ec2-user"

if [[ $USER_CONTEXT != $EC2_USER ]]; then
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

read -p 'What is your full name?     ' NAME

# Make sure name was input
if [ -z "$NAME" ]; then
  echo "Error! You didn't type in your full name."
  echo "Re-run this script and try again."
  exit 1
fi

read -p 'What is your email address? ' EMAIL

# Make sure email was input
if [ -z "$EMAIL" ]; then
  echo "Error! You didn't type in your email address."
  echo "Re-run this script and try again."
  exit 1
fi

clear_screen() {
  # printf "\033c"
  echo "==================================================================================================="
}

prompt_to_continue() {
  clear_screen
  read -p "$1. Press enter to continue."
}

prompt_to_continue_done() {
  clear_screen
  echo "$1."
  echo ""
  read -p "Done. Press enter to continue."
}

Q_00="Thank you, $NAME"
prompt_to_continue "$Q_00"

# Update linux package manager
Q_01="Now we will update yum"
prompt_to_continue "$Q_01"
sudo yum update -y
prompt_to_continue_done "$Q_01"

# Configure Git
Q_02="Now we will configure git using your name ($NAME) and email ($EMAIL)"
prompt_to_continue "$Q_02"
git config --global user.name "$NAME"
git config --global user.email "$EMAIL"
prompt_to_continue_done "$Q_02"

# Ensure LTS version of Node.js is installed
Q_03="Now we will install the current 'LTS' version of Node.js"
CURRENT_NODE_LTS_NAME="fermium" # <= will require update to new LTS 10/2021
EC2_NODE_VERSION=$(node --version)
CURRENT_NODE_LTS_VERSION=$(nvm version-remote --lts=$CURRENT_NODE_LTS_NAME)
if [[ $EC2_NODE_VERSION != $CURRENT_NODE_LTS_VERSION ]]; then
  prompt_to_continue "$Q_03"
  nvm install --lts=$CURRENT_NODE_LTS_NAME
  nvm alias default lts/$CURRENT_NODE_LTS_NAME
  nvm uninstall $EC2_NODE_VERSION
  prompt_to_continue_done "$Q_03"
fi

# Install current version of TypeScript
Q_04="Now we will install TypeScript"
prompt_to_continue "$Q_04"
npm i -g typescript
prompt_to_continue_done "$Q_04"

# Uninstall AWS CLI V1 if installed
Q_05="Now we will uninstall AWS CLI V1"
AWS_CLI_VERSION="$(echo $(aws --version) | cut -d'/' -f2 | cut -c1-1)"
if [[ $AWS_CLI_VERSION == "1" ]]; then
  prompt_to_continue "$Q_05"
  sudo rm -rf /usr/local/aws
  sudo rm /usr/local/bin/aws
  prompt_to_continue_done "$Q_05"
fi

# Install AWS CLI V2 if not installed
Q_06="Now we will install AWS CLI V2"
if [[ $AWS_CLI_VERSION != "2" ]]; then
  prompt_to_continue "$Q_06"
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip awscliv2.zip
  sudo ./aws/install
  rm -rf awscliv2.zip
  rm -rf ./aws/
  prompt_to_continue_done "$Q_06"
fi

Q_07="Now we will configure the AWS CLI V2 with your credentials"
prompt_to_continue "$Q_07"
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
echo "[technical-trainer]" >> ~/.aws/credentials
echo "aws_access_key_id = $AWS_ACCESS_KEY_ID" >>  ~/.aws/credentials
echo "aws_secret_access_key = $AWS_SECRET_ACCESS_KEY" >>  ~/.aws/credentials
echo "source_profile = default" >> ~/.aws/credentials
echo "role_arn = $TECHNICAL_TRAINER_ROLE_ARN" >> ~/.aws/credentials
unset AWS_SECRET_ACCESS_KEY
prompt_to_continue_done "$Q_07"

# Install current version of AWS CDK
Q_08="Now we will install and bootstrap the AWS CDK"
prompt_to_continue "$Q_08"
read -p 'What is your AWS account number?    ' AWS_ACCOUNT_NUMBER
if [ -z "$AWS_ACCOUNT_NUMBER" ]; then
  echo "Error! You didn't type in your AWS account number."
  echo "Re-run this script and try again."
  exit 1
fi
npm install -g aws-cdk
CDK_NEW_BOOTSTRAP=1
AWS_DEFAULT_REGION=$(aws configure get region)
if [ -z "$AWS_DEFAULT_REGION" ]; then
  AWS_DEFAULT_REGION="us-east-1"
fi
cdk bootstrap "aws://$AWS_ACCOUNT_NUMBER/$AWS_DEFAULT_REGION"
prompt_to_continue_done "$Q_08"

Q_09="Now we will increase the size of the EBS volume"
prompt_to_continue "$Q_09"
# Specify the desired volume size in GiB as a command line argument.
SIZE=30

# Get the ID of the environment host Amazon EC2 instance.
INSTANCEID=$(curl http://169.254.169.254/latest/meta-data/instance-id)

# Get the ID of the Amazon EBS volume associated with the instance.
VOLUMEID=$(aws ec2 describe-instances \
  --instance-id $INSTANCEID \
  --query "Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId" \
  --output text)

# Resize the EBS volume.
aws ec2 modify-volume --volume-id $VOLUMEID --size $SIZE

# Wait for the resize to finish.
while [ \
  "$(aws ec2 describe-volumes-modifications \
    --volume-id $VOLUMEID \
    --filters Name=modification-state,Values="optimizing","completed" \
    --query "length(VolumesModifications)"\
    --output text)" != "1" ]; do
sleep 1
done

#Check if we're on an NVMe filesystem
if [ $(readlink -f /dev/xvda) = "/dev/xvda" ]
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
prompt_to_continue_done "$Q_09"

Q_10="Now we will update pip"
prompt_to_continue "$Q_10"
curl -O https://bootstrap.pypa.io/get-pip.py
python get-pip.py --user
rm -rf ./get-pip.py
prompt_to_continue_done "$Q_10"

Q_11"Now we will clone all available repositories"
prompt_to_continue "$Q_11"
python -m pip install git-remote-codecommit
sts assume-role --role-arn "$TECHNICAL_TRAINER_ROLE_ARN" --role-session-name AWSCLI-Session
git clone codecommit://technical-trainer@aai-architecting-on-aws ~/environment/src/aai-architecting-on-aws
prompt_to_continue_done "$Q_11"

clear_screen
echo "Your EC2 environment has been configured."
echo "Close this terminal window and open another before running any additional scripts."
read -p "Press enter to exit."
