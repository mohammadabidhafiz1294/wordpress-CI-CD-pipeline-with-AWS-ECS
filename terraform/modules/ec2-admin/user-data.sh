#!/bin/bash
set -e

# Update system
yum update -y

# Install Amazon Linux Extras for newer software
amazon-linux-extras install nginx1 php8.2 -y

# Install required packages
yum install -y \
    php-mysqlnd \
    php-fpm \
    php-cli \
    php-curl \
    php-gd \
    php-mbstring \
    php-xml \
    php-json \
    php-zip \
    php-intl \
    php-bcmath \
    php-opcache \
    wget \
    git \
    nfs-utils \
    amazon-efs-utils

# Create directories
mkdir -p /var/www/html
mkdir -p /var/www/html/wp-content

# Mount EFS
echo "${efs_dns_name}:/wp-content /var/www/html/wp-content nfs4 defaults,_netdev 0 0" >> /etc/fstab
mount -a

# Download and configure WordPress
cd /var/www/html
wp core download --allow-root

# Configure wp-config.php (will be configured after DB connection)
cat > wp-config.php <<'WPCONFIG'
<?php
define( 'DB_NAME', 'wordpress' );
define( 'DB_USER', 'wordpress' );
define( 'DB_PASSWORD', '${db_password}' );
define( 'DB_HOST', '${db_endpoint}' );
define( 'DB_CHARSET', 'utf8mb4' );
define( 'DB_COLLATE', '' );

define('AUTH_KEY',         'put your unique phrase here');
define('SECURE_AUTH_KEY',  'put your unique phrase here');
define('LOGGED_IN_KEY',    'put your unique phrase here');
define('NONCE_KEY',        'put your unique phrase here');
define('AUTH_SALT',        'put your unique phrase here');
define('SECURE_AUTH_SALT', 'put your unique phrase here');
define('LOGGED_IN_SALT',   'put your unique phrase here');
define('NONCE_SALT',       'put your unique phrase here');

$table_prefix = 'wp_';

define( 'WP_DEBUG', false );

if ( ! defined( 'ABSPATH' ) ) {
    define( 'ABSPATH', __DIR__ . '/' );
}

require_once ABSPATH . 'wp-settings.php';
WPCONFIG

# Create Nginx configuration
cat > /etc/nginx/conf.d/wordpress.conf <<'NGINXCONF'
server {
    listen 80;
    server_name ${admin_domain_name};

    root /var/www/html;
    index index.php index.html;

    client_max_body_size 100M;
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    # wp-content from EFS
    location /wp-content {
        try_files $uri $uri/ /index.php?$args;
    }

    # WordPress permalinks
    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    # WordPress admin
    location /wp-admin {
        try_files $uri $uri/ /index.php?$args;
    }

    # PHP-FPM
    location ~ \.php$ {
        try_files $uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix/run/php-fpm/www.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;

        # Timeouts
        fastcgi_connect_timeout 60s;
        fastcgi_send_timeout 60s;
        fastcgi_read_timeout 60s;

        # Buffering
        fastcgi_buffer_size 128k;
        fastcgi_buffers 4 256k;
        fastcgi_busy_buffers_size 256k;
    }

    # Deny access to sensitive files
    location ~ /\.(?!well-known).* {
        deny all;
    }

    location = /favicon.ico {
        log_not_found off;
        access_log off;
    }

    location = /robots.txt {
        allow all;
        log_not_found off;
        access_log off;
    }

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
}

# HTTP to HTTPS redirect (uncomment after setting up SSL)
# server {
#     listen 80;
#     server_name ${admin_domain_name};
#     return 301 https://$server_name$request_uri;
# }
NGINXCONF

# Configure PHP-FPM
sed -i 's/;listen.owner = nobody/listen.owner = nginx/' /etc/php-fpm.d/www.conf
sed -i 's/;listen.group = nobody/listen.group = nginx/' /etc/php-fpm.d/www.conf
sed -i 's/;listen.mode = 0660/listen.mode = 0660/' /etc/php-fpm.d/www.conf

# Set PHP-FPM to use socket
sed -i 's/listen = 127.0.0.1:9000/listen = \/run\/php-fpm\/www.sock/' /etc/php-fpm.d/www.conf

# Configure PHP settings for WordPress
cat >> /etc/php.ini <<'PHPI'
; WordPress performance settings
opcache.enable=1
opcache.memory_consumption=128
opcache.interned_strings_buffer=8
opcache.max_accelerated_files=1000
opcache.revalidate_freq=2
opcache.fast_shutdown=1

; Upload settings
upload_max_filesize = 100M
post_max_size = 100M
max_execution_time = 300
max_input_time = 300
PHPI

# Set permissions
chown -R nginx:nginx /var/www/html
chmod -R 755 /var/www/html
chmod -R 775 /var/www/html/wp-content

# Enable and start services
systemctl enable nginx php-fpm
systemctl restart nginx php-fpm

# Install WordPress CLI for future admin tasks
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp

echo "WordPress Admin Server setup completed!"
