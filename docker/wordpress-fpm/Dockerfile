FROM wordpress:6.4.3-php8.2-fpm-alpine

# Install additional PHP extensions
RUN docker-php-ext-install mysqli pdo pdo_mysql

# Create wp-content directory structure (will be mounted from EFS)
RUN mkdir -p /var/www/html/wp-content && \
    chown -R www-data:www-data /var/www/html && \
    chmod -R 755 /var/www/html

# Copy custom nginx configuration if exists
# COPY nginx.conf /etc/nginx/http.d/default.conf

# Switch to non-root user
USER www-data

# Expose port 9000 for PHP-FPM
EXPOSE 9000

CMD ["php-fpm"]
