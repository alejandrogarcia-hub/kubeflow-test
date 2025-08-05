#!/bin/bash

# Main Kubeflow operations script
# This provides a simple interface for common Kubeflow tasks

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

function print_header() {
    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${GREEN}================================================${NC}"
}

function print_usage() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  install    - Install Kubeflow Pipelines (clean install)"
    echo "  uninstall  - Remove all Kubeflow components"
    echo "  forward    - Start port forwarding to UI"
    echo "  compile    - Compile the pipeline to YAML"
    echo "  submit     - Submit pipeline to Kubeflow"
    echo "  status     - Check Kubeflow pods status"
    echo "  demo       - Run complete demo flow"
    echo "  help       - Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 install   # Clean install of Kubeflow"
    echo "  $0 demo      # Run full demo"
}

function check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check Docker
    if ! docker version &>/dev/null; then
        echo -e "${RED}❌ Docker is not running${NC}"
        echo "Please start Docker Desktop"
        exit 1
    else
        echo -e "${GREEN}✅ Docker is running${NC}"
    fi
    
    # Check Kubernetes
    if ! kubectl cluster-info &>/dev/null; then
        echo -e "${RED}❌ Kubernetes is not accessible${NC}"
        echo "Please enable Kubernetes in Docker Desktop"
        exit 1
    else
        echo -e "${GREEN}✅ Kubernetes is running${NC}"
    fi
    
    # Check Python
    if ! command -v uv &>/dev/null; then
        echo -e "${RED}❌ uv is not installed${NC}"
        echo "Please install uv: https://github.com/astral-sh/uv"
        exit 1
    else
        echo -e "${GREEN}✅ uv is installed${NC}"
    fi
    
    # Check Docker resources
    echo ""
    echo "→ Checking Docker Desktop resources..."
    DOCKER_MEM=$(docker system info 2>/dev/null | grep "Total Memory" | awk '{print $3}' | sed 's/GiB//')
    if [[ -n "$DOCKER_MEM" ]]; then
        MEM_INT=$(echo "$DOCKER_MEM" | awk -F. '{print $1}')
        if [[ "$MEM_INT" -lt 8 ]]; then
            echo -e "${YELLOW}⚠️  Docker Desktop has ${DOCKER_MEM}GB memory allocated${NC}"
            echo "   Recommended: 8GB or more for Kubeflow"
            echo "   You can increase it in Docker Desktop settings"
        else
            echo -e "${GREEN}✅ Docker Desktop has ${DOCKER_MEM}GB memory allocated${NC}"
        fi
    fi
    
    echo ""
}

function install_kubeflow() {
    print_header "Installing Kubeflow Pipelines"
    check_prerequisites
    
    echo -e "${YELLOW}This will remove any existing Kubeflow installation!${NC}"
    read -p "Continue with clean installation? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
    
    cd "$PROJECT_ROOT"
    ./ops/kubeflow/install_kubeflow_v4.sh
}

function start_port_forward() {
    print_header "Starting Port Forward"
    echo "Access Kubeflow UI at: http://localhost:8080"
    echo "Press Ctrl+C to stop"
    echo ""
    
    cd "$PROJECT_ROOT"
    if [ -f "kubeflow_port_forward.sh" ]; then
        ./kubeflow_port_forward.sh
    elif [ -f "port_forward_v2.sh" ]; then
        ./port_forward_v2.sh
    elif [ -f "port_forward_clean.sh" ]; then
        ./port_forward_clean.sh
    else
        ./ops/kubeflow/port_forward.sh
    fi
}

function compile_pipeline() {
    print_header "Compiling Pipeline"
    
    cd "$PROJECT_ROOT"
    echo "→ Compiling iris_pipeline.py to YAML..."
    uv run python src/pipelines/iris_pipeline.py
    
    if [ -f "iris_pipeline.yaml" ]; then
        echo -e "${GREEN}✅ Pipeline compiled successfully${NC}"
        echo "   Output: iris_pipeline.yaml"
    else
        echo -e "${RED}❌ Pipeline compilation failed${NC}"
        exit 1
    fi
}

function submit_pipeline() {
    print_header "Submitting Pipeline to Kubeflow"
    
    cd "$PROJECT_ROOT"
    
    # Check if pipeline YAML exists
    if [ ! -f "iris_pipeline.yaml" ]; then
        echo -e "${YELLOW}Pipeline YAML not found. Compiling first...${NC}"
        compile_pipeline
    fi
    
    # Generate unique run name
    RUN_NAME="iris-run-$(date +%Y%m%d-%H%M%S)"
    
    echo "→ Submitting pipeline..."
    echo "  Experiment: iris-demo"
    echo "  Run name: $RUN_NAME"
    
    uv run python src/run_pipeline.py --mode submit \
        --experiment "iris-demo" \
        --run-name "$RUN_NAME"
    
    echo ""
    echo -e "${GREEN}✅ Pipeline submitted!${NC}"
    echo "   View in UI: http://localhost:8080"
}

function check_status() {
    print_header "Kubeflow Status"
    
    echo "→ Kubeflow pods:"
    kubectl get pods -n kubeflow | head -20
    
    echo ""
    echo "→ Key services:"
    kubectl get svc -n kubeflow | grep -E "(ml-pipeline|minio|mysql)"
}

function run_demo() {
    print_header "Running Complete Demo"
    
    echo "This will:"
    echo "1. Check prerequisites"
    echo "2. Compile the pipeline"
    echo "3. Upload pipeline to Kubeflow"
    echo "4. Submit a run to Kubeflow"
    echo "5. Provide instructions for monitoring"
    echo ""
    
    read -p "Continue? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
    
    # Run steps
    check_prerequisites
    compile_pipeline
    
    echo ""
    echo -e "${YELLOW}⚠️  Make sure port-forward is running in another terminal:${NC}"
    echo "   ./ops/kubeflow/kubeflow.sh forward"
    echo ""
    read -p "Press Enter when port-forward is running..."
    
    # Check if ml-pipeline is ready
    echo ""
    echo "→ Checking if Kubeflow API is ready..."
    for i in {1..30}; do
        if curl -s http://localhost:8080/apis/v1beta1/healthz 2>/dev/null | grep -q "apiServerReady.*true"; then
            echo -e "${GREEN}✅ Kubeflow API is ready${NC}"
            break
        fi
        if [[ $((i % 5)) == 0 ]]; then
            echo "  Still waiting for API... ($i/30 seconds)"
        else
            echo -n "."
        fi
        sleep 1
    done
    
    # Upload pipeline first
    echo ""
    print_header "Uploading Pipeline to Kubeflow"
    cd "$PROJECT_ROOT"
    uv run python src/upload_pipeline.py
    
    # Then submit a run
    submit_pipeline
    
    echo ""
    print_header "Demo Submitted Successfully!"
    echo "Next steps:"
    echo "1. Open http://localhost:8080"
    echo "2. Go to Experiments → iris-demo"
    echo "3. Click on your run to watch progress"
    echo "4. After completion, run: make serve"
    echo "5. Test API: curl -X POST http://localhost:8000/predict ..."
}

# Main script logic
case "$1" in
    install)
        install_kubeflow
        ;;
    uninstall)
        cd "$PROJECT_ROOT"
        ./ops/kubeflow/uninstall_kubeflow.sh
        ;;
    forward)
        start_port_forward
        ;;
    compile)
        compile_pipeline
        ;;
    submit)
        submit_pipeline
        ;;
    status)
        check_status
        ;;
    demo)
        run_demo
        ;;
    help|"")
        print_usage
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        echo ""
        print_usage
        exit 1
        ;;
esac