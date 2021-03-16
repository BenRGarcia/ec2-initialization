#!/bin/bash

###############################################################################
# Update yum
###############################################################################
sudo yum update -y

###############################################################################
# Update pip
###############################################################################
curl -O https://bootstrap.pypa.io/get-pip.py
python3 get-pip.py --user
rm -rf ./get-pip.py

###############################################################################
# Install git-remote-codecommit
###############################################################################
python3 -m pip install git-remote-codecommit

###############################################################################
# Use nvm to install Node.js LTS version, uninstall default EC2 version
###############################################################################
. ~/.nvm/nvm.sh
CURRENT_NODE_LTS_NAME="fermium" # <= will require update to new LTS 10/2021
EC2_NODE_VERSION=$(node --version)
CURRENT_NODE_LTS_VERSION=$(nvm version-remote --lts=$CURRENT_NODE_LTS_NAME)
if [[ $EC2_NODE_VERSION != "$CURRENT_NODE_LTS_VERSION" ]]; then
    nvm install --lts=$CURRENT_NODE_LTS_NAME
    nvm alias default lts/$CURRENT_NODE_LTS_NAME
    nvm uninstall "$EC2_NODE_VERSION"
fi

###############################################################################
# Install TypeScript
###############################################################################
npm i -g typescript@"~3.9.9" # AWS CDK v1.94.0 TypeScript version

###############################################################################
# Install AWS CDK, bootstrap AWS environment
###############################################################################
npm install -g aws-cdk
AWS_ACCOUNT_NUMBER=$(aws sts get-caller-identity --query Account --output text)
AWS_DEFAULT_REGION=$(aws configure get region)
export CDK_NEW_BOOTSTRAP=1
cdk bootstrap "aws://$AWS_ACCOUNT_NUMBER/$AWS_DEFAULT_REGION"

###############################################################################
# Increase size of EBS volume to accommodate AWS CodeCommit repository clones
###############################################################################
EBS_VOLUME_SIZE=30
# Get the ID of the environment host Amazon EC2 instance.
INSTANCEID=$(curl http://169.254.169.254/latest/meta-data/instance-id)

# Get the ID of the Amazon EBS volume associated with the instance.
VOLUMEID=$(aws ec2 describe-instances \
    --instance-id "$INSTANCEID" \
    --query "Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId" \
    --output text)

# Resize the EBS volume.
aws ec2 modify-volume --volume-id "$VOLUMEID" --size "$EBS_VOLUME_SIZE"

# Wait for the resize to finish.
while [ \
    "$(aws ec2 describe-volumes-modifications \
        --volume-id "$VOLUMEID" \
        --filters Name=modification-state,Values="optimizing","completed" \
        --query "length(VolumesModifications)" \
        --output text)" != "1" ]; do
    sleep 1
done

# Check if we're on an NVMe filesystem
if [ "$(readlink -f /dev/xvda)" = "/dev/xvda" ]; then
    # Rewrite the partition table so that the partition takes up all the space that it can.
    sudo growpart /dev/xvda 1

    # Expand the size of the file system.
    # Check if we are on AL2
    STR=$(cat /etc/os-release)
    SUB="VERSION_ID=\"2\""
    if [[ "$STR" == *"$SUB"* ]]; then
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
    if [[ "$STR" == *"$SUB"* ]]; then
        sudo xfs_growfs -d /
    else
        sudo resize2fs /dev/nvme0n1p1
    fi
fi

###############################################################################
# Uninstall AWS CLI v1
###############################################################################
sudo rm -rf /usr/local/aws
sudo rm /usr/local/bin/aws

###############################################################################
# Install, configure AWS CLI v2
###############################################################################
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm -rf awscliv2.zip
rm -rf ./aws/
AWS_TECHNICAL_TRAINER_ROLE_NAME="AwsTechnicalTrainerRole"
AWS_TECHNICAL_TRAINER_ROLE_ARN="arn:aws:iam::403112560303:role/AwsTechnicalTrainerRole"
{
    echo "[default]"
    echo "output = json"
    echo "account = $AWS_ACCOUNT_NUMBER"
    echo ""
    echo "[profile $AWS_TECHNICAL_TRAINER_ROLE_NAME]"
    echo "region = $AWS_DEFAULT_REGION"
    echo "role_arn = $AWS_TECHNICAL_TRAINER_ROLE_ARN"
    echo "output = json"
    echo "account = 403112560303"
    echo "source_profile = default"
} >>~/.aws/config

###############################################################################
# Next Step Instructions
###############################################################################
echo ""
echo "#######################################################################################################################################################"
echo ""
echo "Follow these instructions for the next steps:"
echo ""
echo "    ---------------------------------------------------------------------------------------------------------------------------------------------------"
echo "    1. Change Cloud9 setting to **NOT** use 'AWS managed temporary credentials'"
echo ""
echo "       Q: How do we do this?"
echo "       A: 1.1 Click on Cloud9 Settings (Gear icon in the top right)"
echo "          1.2 Click on 'AWS Settings' (Left sidebar in opened tab, near the bottom of the sidebar list)"
echo "          1.3 Click on 'Credentials' (Under the 'AWS Settings' sidebar section title)"
echo "          1.4 Toggle the 'AWS managed temporary credentials' setting to OFF (should now have red background toggle with 'X' on it)"
echo ""
echo "       Q: (For the curious) Why would we do this?"
echo "       A: Cloud9's default 'managed temporary credentials' will not allow you to assume the IAM Role which grants you access to the instructor demos)"
echo "          And much to my chagrin, I've not yet found a way to automate this step"
echo "          Documentation for Cloud9's default permissions limitations:"
echo "          https://docs.aws.amazon.com/cloud9/latest/user-guide/how-cloud9-with-iam.html#auth-and-access-control-temporary-managed-credentials-supported"
echo "          https://docs.aws.amazon.com/cloud9/latest/user-guide/troubleshooting.html#troubleshooting-cli-invalid-token"
echo ""
echo "    ---------------------------------------------------------------------------------------------------------------------------------------------------"
echo "    2. Open a **NEW** terminal window, and don't input any more commands into this terminal window"
echo ""
echo "       Q: How do we do this?"
echo "       A: 2.1 Click on the green circle plus icon just above this terminal window"
echo "          2.2 Click on 'New Terminal' option in the drop-down menu"
echo ""
echo "       Q: (For the curious) Why would we do this?"
echo "       A: The 'initialize.sh' script that just ran needs a fresh shell environment to be able to access everything that was just installed"
echo "          Eh, computers... What can I say?..."
echo ""
echo "    ---------------------------------------------------------------------------------------------------------------------------------------------------"
echo "    3. Configure the AWS CLI with your AWS Isengard account credentials"
echo ""
echo "       Q: How do we do this?"
echo "       A: 3.1 In your **NEW** terminal window, run the command:"
echo ""
echo "              $ aws configure"
echo ""
echo "              The AWS CLI will prompt you for your:"
echo "                  a. AWS access key ID"
echo "                  b. AWS secret access key"
echo "                  c. Default region name (e.g. 'us-east-1', 'us-west-2', etc.)"
echo "                  d. Default output format (e.g. 'json', 'yaml', 'text', etc.)"
echo ""
echo "              If you don't already have an access key ID and secret access key for your AWS account, here are instructions on how to generate those:"
echo "              https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_access-keys.html#Using_CreateAccessKey"
echo ""
echo "       Q: Why would we do this?"
echo "       A: When we turned off Cloud9's 'AWS managed temporary credentials' setting, the original AWS credentials were removed from this environment."
echo "          So until we reconfigure this environment with your permanent credentials, I'm afraid you're stranded here without permission to do anything."
echo ""
echo "    ---------------------------------------------------------------------------------------------------------------------------------------------------"
echo "    4. Start cloning repositories"
echo ""
echo "       Q: How do we do this?"
echo "       A: 4.1 In your **NEW** terminal window, run the command:"
echo ""
echo "             $ git clone codecommit::us-west-2://${AWS_TECHNICAL_TRAINER_ROLE_NAME}@aai-architecting-on-aws "
echo ""
echo "############################################################################################"
echo ""
echo "<<<<<<<<<<<<<<<<<< In case you missed it, the instructions for your next steps were output above >>>>>>>>>>>>>>>>>>"
