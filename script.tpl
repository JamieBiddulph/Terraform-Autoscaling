#!/bin/bash

# Install some default system components
sudo apt update
sudo apt install -y software-properties-common \
curl \
acl \
git \
binutils \
stunnel4 \
ruby-full \
wget  \
python3-pip \
jq

# Setup AWS EFS utils for mounting the EFS later
git clone https://github.com/aws/efs-utils
cd efs-utils
sudo ./build-deb.sh
sudo apt-get -y install ./build/amazon-efs-utils*deb

# Setup the code-deploy agent. Not currently in use so could be removed.
# wget https://aws-codedeploy-eu-west-2.s3.eu-west-2.amazonaws.com/latest/install
# sudo chmod u+x ./install
# sudo ./install auto > /tmp/logfile
# sudo service codedeploy-agent start

# Setup prefered nginx and php versions
sudo add-apt-repository ppa:ondrej/php -y
sudo add-apt-repository ppa:ondrej/nginx -y
sudo apt update
sudo apt install -y nginx \
php8.1 \
php8.1-fpm \
php8.1-common \
php8.1-curl \
php8.1-bcmath \
php8.1-mbstring \
php8.1-pdo \
php8.1-xml \
php8.1-mysql \
php8.1-zip \
php8.1-gd \
php8.1-imagick \
php8.1-intl


#### Setup code base ####
pip3 install awscli --upgrade
sudo aws s3 cp s3://demo-infastructure-code-blog/release-latest-zip /tmp/release-latest-zip
sudo unzip -q /tmp/release-latest-zip -d /var/www/html/code
sudo chown -R www-data:www-data /var/www/html/code
sudo find /var/www/html/code -type d -exec chmod 2775 {} +
sudo find /var/www/html/code -type f -exec chmod 0664 {} +

# Setup wp-config.php using AWS Secrets Manager
AWS_SECRET_ID="arn:aws:secretsmanager:eu-west-2:153653607455:secret:demo-infastructure-wp-secrets-y3lnuc"
AWS_REGION="eu-west-2"
ENVFILE="/var/www/html/code/wp-config.php"
aws secretsmanager get-secret-value --secret-id $AWS_SECRET_ID --region $AWS_REGION | \
  jq -r '.SecretString' > $ENVFILE
sudo chown www-data:www-data $ENVFILE
sudo chmod 400 $ENVFILE

# Setup nginx and PHP-FPM configs
git clone https://github.com/JamieBiddulph/autoscale-templates.git --branch main
sudo cp autoscale-templates/nginx.conf /etc/nginx/nginx.conf
sudo cp autoscale-templates/www.conf /etc/php/8.1/fpm/pool.d/www.conf
curl https://ssl-config.mozilla.org/ffdhe2048.txt  > /etc/nginx/dhparam

# Setup Self-Signed Certificate files
AWS_SECRET_SSL_PEM_ID="arn:aws:secretsmanager:eu-west-2:153653607455:secret:demo-infastructure-ssl-pem-GCBfN7"
AWS_SECRET_SSL_KEY_ID="arn:aws:secretsmanager:eu-west-2:153653607455:secret:demo-infastructure-ssl-key-jEIOG7"
AWS_REGION="eu-west-2"
SSL_PEM_FILE="/etc/nginx/ssl.pem"
SSL_KEY_FILE="/etc/nginx/ssl.key"
aws secretsmanager get-secret-value --secret-id $AWS_SECRET_SSL_PEM_ID --region $AWS_REGION | \
  jq -r '.SecretString' > $SSL_PEM_FILE
sudo chmod 400 $SSL_PEM_FILE
aws secretsmanager get-secret-value --secret-id $AWS_SECRET_SSL_KEY_ID --region $AWS_REGION | \
  jq -r '.SecretString' > $SSL_KEY_FILE
sudo chmod 400 $SSL_KEY_FILE

# Restart services post conf update
sudo apt upgrade -y
sudo systemctl restart nginx
sudo systemctl restart php8.1-fpm

#### Setup uploads symlink ####
sudo mkdir /mnt/efs
sudo mount -t efs -o tls fs-0cbc934ff7d2a79ae:/ /mnt/efs
# Make the /mnt/efs/wp-content-uploads directory writeable to the www-data user
sudo setfacl -m u:www-data:rwx /mnt/efs/wp-content-uploads
sudo setfacl -m -R u:www-data:rwx /mnt/efs/wp-content-uploads
# Create symlink for /mnt/efs/wp-content-uploads to /var/www/html/code/wp-content
sudo ln -s /mnt/efs/wp-content-uploads /var/www/html/code/wp-content/uploads
sudo chown -h www-data:www-data /var/www/html/code/wp-content/uploads
