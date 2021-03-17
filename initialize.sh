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

{
    echo "#!/bin/bash"
    echo ""
    echo "git clone codecommit::us-west-2://${AWS_TECHNICAL_TRAINER_ROLE_NAME}@aai-architecting-on-aws"
    echo "cd aai-architecting-on-aws"
    echo "npm ci"
} >~/environment/get-aai-architecting-on-aws.sh
chmod +x ~/environment/get-aai-architecting-on-aws.sh

###############################################################################
# Next Step Instructions
###############################################################################
{
    echo "# Manual Setup Instructions"
    echo ""
    echo "To read these instructions with pretty formatting:"
    echo ""
    echo "1. Click anywhere on the text inside this file so your cursor is blinking inside"
    echo "2. Click on the \`Preview\` button (at the top, to the left of the 'Run' button)"
    echo "3. Choose the option to \`Preview File manual-setup-instructions.md\`"
    echo ""
    echo "---"
    echo ""
    echo "Follow these manual steps to complete your setup (These steps can't be automated)."
    echo ""
    echo "### I. Turn Off Cloud9's 'Managed Temporary Credentials'"
    echo ""
    echo "> By default, Cloud9 uses 'AWS managed temporary credentials'. These credentials will not allow us to assume the IAM Role which grants us access to the instructor demos. Therefore, we must turn it off."
    echo ""
    echo "1. Open up the Cloud9 preferences tab by pressing <kbd>Ctrl</kbd> + <kbd>,</kbd> (or, by clicking on the gear icon in the top right)"
    echo "2. In the preferences tab that just appeared, click on \`AWS Settings\` in the left sidebar (you should see it near the bottom of the sidebar list)"
    echo "3. Click on \`Credentials\` (Under the 'AWS Settings' sidebar section title)"
    echo "4. Toggle the \`AWS managed temporary credentials\` setting to OFF (toggle should now have red background with an 'X' on it)"
    echo "5. Close Cloud9 preferences by clicking the 'X' on the tab"
    echo ""
    echo "### II. Configure the AWS CLI"
    echo ""
    echo "> When we turned off Cloud9's 'managed temporary credentials', we removed all AWS credentials associated with this environment. Therefore, we must configure the AWS CLI with new credentials."
    echo ""
    echo "1. Close the terminal window you were previously using by clicking on the 'X' on the terminal window's tab. (Press <kbd>F6</kbd> to show the console drawer if it's hidden)"
    echo "2. Open a new terminal window by pressing <kbd>Alt</kbd> + <kbd>t</kbd> (or, by clicking on the green '+' at the top of the console drawer, and then click \`New Terminal\`)"
    echo "3. Run this command in your **NEW** terminal window: \`aws configure\`"
    echo "    - The AWS CLI will prompt you for your access key id, secret access key, region, and output"
    echo "    - If you don't already have an access key ID & secret access key for your AWS account, here are instructions on how to generate those: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_access-keys.html#Using_CreateAccessKey"
} >~/environment/manual-setup-instructions.md

echo ""
echo "####################################################################################################"
echo "Open up the file 'manual-setup-instructions.md' and follow those instructions to complete your setup"
echo ""
