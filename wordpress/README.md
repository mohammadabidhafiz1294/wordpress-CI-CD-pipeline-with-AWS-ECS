# WordPress Application

This directory contains the WordPress application code that will be containerized and deployed to ECS Fargate.

## Directory Structure

Place your WordPress files here. The CI/CD pipeline will:
1. Build a Docker image from the files in this directory
2. Push the image to Amazon ECR
3. Deploy the image to ECS Fargate

## Customization

To customize the WordPress deployment:
- Modify files in this directory
- Update the Docker configuration in `../docker/wordpress-fpm/`
- Commit and push changes to trigger the CI/CD pipeline

## Notes

- The Docker image is built using the Dockerfile in `../docker/wordpress-fpm/`
- File changes in this directory will trigger the GitHub Actions workflow
- Ensure any custom plugins or themes are included in this directory
