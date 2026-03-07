# AGENTS.md

This file contains guidelines for agentic coding agents working with this repository.

## Build/Lint/Test Commands

### Terraform Commands
- `terraform init` - Initialize Terraform configuration
- `terraform plan` - Preview changes
- `terraform apply` - Apply changes
- `terraform fmt` - Format Terraform files
- `terraform validate` - Validate configuration

### GitHub Actions Testing
- Test workflow manually through GitHub Actions UI
- Push changes to trigger automated workflow
## Code Style Guidelines

### Terraform Conventions

1. **File Organization**
   - Variables in `variables.tf`
   - Outputs in `outputs.tf`
   - Main configuration in `main.tf`

2. **Naming Conventions**
   - Use lowercase with underscores (snake_case)
   - Resource names should be descriptive
   - Variables should be named clearly

3. **Variables**
   - All variables should have descriptions
   - Use appropriate types (string, number, bool, list, map, object)
   - Sensitive variables should have `sensitive = true`

4. **Formatting**
   - Use 2 spaces for indentation
   - Align equal signs for multiple assignments
   - Use consistent quoting (prefer double quotes)

5. **Modules**
   - Modules should be self-contained
   - Inputs via variables, outputs via outputs.tf
   - Version pinning for providers

### Error Handling

1. **Terraform**
   - Use `ignore_errors` only when appropriate
   - Handle dependencies with `depends_on`
   - Use appropriate timeouts for resources

2. **GitHub Actions**
   - Use `continue-on-error` for non-critical steps
   - Implement proper error handling in scripts

### Import Conventions

1. **Terraform Provider Configuration**
   - Define required providers in `terraform` block
   - Pin provider versions appropriately
   - Configure providers in root module only

### Types and Documentation

1. **Variable Types**
   - Use specific types rather than generic ones
   - Document complex object types
   - Use defaults where appropriate

2. **Documentation**
   - All variables must have descriptions
   - Complex modules should have README.md
   - Use comments for non-obvious configurations

## Running Single Tests

Since this project is primarily infrastructure-as-code with Terraform, testing focuses on:

1. **Terraform Validation**
   - `terraform validate` - Validates syntax and configuration
   - `terraform fmt -check` - Checks formatting compliance
   - `terraform plan` - Dry run to check for issues

2. **Module Testing**
   - Test individual modules by running terraform init/plan in module directory
   - Example:
   ```
   cd terraform/modules/vpc
   terraform init
   terraform plan
   ```

3. **GitHub Actions Testing**
   - Use GitHub's workflow testing features
   - Test locally with `act` tool if available
