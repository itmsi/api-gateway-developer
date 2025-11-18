#!/bin/bash

# Deploy Kong Routes Script - Developer Environment
# Script untuk deploy perubahan kong.yml ke developer environment dengan mudah

set -e

echo "🚀 Deploy Kong Routes Script (Developer)"
echo "========================================="

# Container details (sesuai dengan docker-compose.developer.yml)
CONTAINER_NAME="msi-api-gateway-developer-kong"
ADMIN_PORT="9589"
PROXY_PORT="9588"
CONFIG_PATH="/kong/kong.yml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Function to validate kong.yml locally
validate_local() {
    print_status "🔍 Validating kong.yml locally..."
    
    # Check if file exists
    if [[ ! -f "config/kong.yml" ]]; then
        print_error "config/kong.yml not found!"
        return 1
    fi
    
    # Validate YAML syntax
    if command -v python3 &> /dev/null; then
        if python3 -c "import yaml; yaml.safe_load(open('config/kong.yml'))" 2>&1; then
            print_success "YAML syntax is valid ✓"
        else
            print_error "YAML syntax error!"
            return 1
        fi
    else
        print_warning "Python3 not found, skipping YAML validation"
    fi
    
    # Count routes and services
    local route_count=$(grep -c "name:.*-route" config/kong.yml || echo "0")
    local service_count=$(grep -c "name:.*-service" config/kong.yml || echo "0")
    
    print_success "Found $service_count services and $route_count routes"
    echo ""
}

# Function to check if container is running
check_container() {
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        print_error "Container ${CONTAINER_NAME} is not running!"
        print_status "Please start the container first:"
        echo "  docker compose -f docker-compose.developer.yml up -d"
        return 1
    fi
    return 0
}

# Function to deploy kong.yml
deploy() {
    print_status "📦 Deploying kong.yml to developer environment..."
    echo ""
    
    # Step 1: Check container
    print_status "Step 1: Checking container status..."
    check_container || return 1
    print_success "Container is running ✓"
    echo ""
    
    # Step 2: Validate local file
    print_status "Step 2: Validating local kong.yml..."
    validate_local || return 1
    echo ""
    
    # Step 3: Backup current config in container
    print_status "Step 3: Backing up current kong.yml in container..."
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    docker exec ${CONTAINER_NAME} cp ${CONFIG_PATH} ${CONFIG_PATH}.backup.${timestamp} 2>/dev/null || true
    print_success "Backup created in container"
    echo ""
    
    # Step 4: Copy to container (via volume mount, file should already be there)
    # Since we're using volume mount, we just need to reload
    print_status "Step 4: Verifying kong.yml in container..."
    if docker exec ${CONTAINER_NAME} test -f ${CONFIG_PATH}; then
        print_success "kong.yml found in container ✓"
    else
        print_error "kong.yml not found in container!"
        return 1
    fi
    echo ""
    
    # Step 5: Validate config in Kong
    print_status "Step 5: Validating kong.yml with Kong..."
    if docker exec ${CONTAINER_NAME} kong config parse ${CONFIG_PATH} > /dev/null 2>&1; then
        print_success "Kong config is valid ✓"
    else
        print_error "Kong config validation failed!"
        print_status "Checking error details..."
        docker exec ${CONTAINER_NAME} kong config parse ${CONFIG_PATH}
        return 1
    fi
    echo ""
    
    # Step 6: Reload Kong (declarative config reload)
    print_status "Step 6: Reloading Kong configuration..."
    
    # Kong 3.4 supports reload for declarative config
    if docker exec ${CONTAINER_NAME} kong reload; then
        print_success "Kong reloaded successfully! ✓"
        sleep 2
    else
        print_warning "Reload failed, restarting container..."
        docker compose -f docker-compose.developer.yml restart kong
        sleep 10
        print_success "Container restarted"
    fi
    echo ""
    
    # Step 7: Verify Kong is healthy
    print_status "Step 7: Verifying Kong health..."
    for i in {1..10}; do
        if curl -s http://localhost:${ADMIN_PORT}/status >/dev/null 2>&1; then
            print_success "Kong is healthy! ✓"
            break
        fi
        if [[ $i -eq 10 ]]; then
            print_error "Kong health check failed after 10 attempts"
            return 1
        fi
        echo -n "."
        sleep 2
    done
    echo ""
    echo ""
    
    # Step 8: Show current routes
    print_status "Step 8: Current routes:"
    local route_count=$(curl -s http://localhost:${ADMIN_PORT}/routes 2>/dev/null | grep -o '"name"' | wc -l || echo "0")
    print_success "Total routes: $route_count"
    echo ""
    
    print_success "✅ Deployment completed successfully!"
    echo ""
    echo "🧪 Test your routes:"
    echo "  curl -v http://localhost:${PROXY_PORT}/api/your-endpoint"
}

# Function to show diff
show_diff() {
    print_status "📊 Comparing local and container kong.yml..."
    echo ""
    
    # Get container file
    print_status "Fetching kong.yml from container..."
    docker exec ${CONTAINER_NAME} cat ${CONFIG_PATH} > /tmp/kong.yml.container 2>/dev/null || {
        print_error "Failed to read kong.yml from container"
        return 1
    }
    
    # Show diff
    print_status "Differences (local vs container):"
    echo ""
    diff -u /tmp/kong.yml.container config/kong.yml || true
    
    # Cleanup
    rm -f /tmp/kong.yml.container
    echo ""
}

# Function to pull from container
pull() {
    print_status "⬇️  Pulling kong.yml from container..."
    echo ""
    
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    
    # Backup local file
    if [[ -f "config/kong.yml" ]]; then
        cp config/kong.yml "config/kong.yml.backup.${timestamp}"
        print_success "Local backup saved: config/kong.yml.backup.${timestamp}"
    fi
    
    # Pull from container
    docker exec ${CONTAINER_NAME} cat ${CONFIG_PATH} > config/kong.yml
    
    print_success "✅ kong.yml pulled from container"
    echo ""
    
    # Show info
    local route_count=$(grep -c "name:.*-route" config/kong.yml || echo "0")
    local service_count=$(grep -c "name:.*-service" config/kong.yml || echo "0")
    print_status "Downloaded config has $service_count services and $route_count routes"
}

# Function to check status
check_status() {
    print_status "📊 Checking Kong status..."
    echo ""
    
    # Container status
    print_status "Container Status:"
    docker ps --filter name=${CONTAINER_NAME} --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
    echo ""
    
    # Kong health
    print_status "Kong Health:"
    if curl -s http://localhost:${ADMIN_PORT}/status >/dev/null 2>&1; then
        curl -s http://localhost:${ADMIN_PORT}/status | python3 -m json.tool 2>/dev/null || curl -s http://localhost:${ADMIN_PORT}/status
    else
        print_error "Cannot connect to Kong Admin API"
    fi
    echo ""
    
    # Routes count
    print_status "Routes:"
    local route_count=$(curl -s http://localhost:${ADMIN_PORT}/routes 2>/dev/null | grep -o '"name"' | wc -l || echo "0")
    echo "Total: $route_count"
    echo ""
    
    # Services count
    print_status "Services:"
    local service_count=$(curl -s http://localhost:${ADMIN_PORT}/services 2>/dev/null | grep -o '"name"' | wc -l || echo "0")
    echo "Total: $service_count"
    echo ""
}

# Function to test route
test_route() {
    local route_path="$1"
    
    if [[ -z "$route_path" ]]; then
        print_error "Please provide route path!"
        echo "Usage: $0 test <route-path>"
        echo "Example: $0 test /api/catalogs/categories/get"
        return 1
    fi
    
    print_status "🧪 Testing route: $route_path"
    echo ""
    
    curl -v http://localhost:${PROXY_PORT}${route_path} -H 'Content-Type: application/json' -d '{}'
}

# Function to show help
show_help() {
    echo "🚀 Deploy Kong Routes Script (Developer)"
    echo "========================================="
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  deploy              - Deploy local kong.yml to container"
    echo "  pull                - Pull kong.yml from container to local"
    echo "  diff                - Show differences between local and container"
    echo "  status              - Check Kong status"
    echo "  test <path>         - Test a specific route"
    echo "  validate            - Validate local kong.yml"
    echo "  help                - Show this help"
    echo ""
    echo "Workflow Examples:"
    echo ""
    echo "  # Edit kong.yml locally, then deploy"
    echo "  vim config/kong.yml"
    echo "  $0 deploy"
    echo ""
    echo "  # Pull changes from container"
    echo "  $0 pull"
    echo ""
    echo "  # Check what changed before deploying"
    echo "  $0 diff"
    echo "  $0 deploy"
    echo ""
    echo "  # Test a route"
    echo "  $0 test /api/catalogs/categories/get"
    echo ""
}

# Main execution
main() {
    local command="$1"
    
    case "$command" in
        "deploy")
            deploy
            ;;
        "pull")
            pull
            ;;
        "diff")
            show_diff
            ;;
        "status")
            check_status
            ;;
        "test")
            test_route "$2"
            ;;
        "validate")
            validate_local
            ;;
        "help"|"")
            show_help
            ;;
        *)
            print_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

main "$@"

