#!/bin/bash

# K6 Long Transaction Load Test Runner
# This script runs a k6 load test that generates long-running transactions

echo "=========================================="
echo "K6 Long Transaction Load Test"
echo "=========================================="
echo ""
echo "Test Configuration:"
echo "  - Target: http://localhost:8000/demo"
echo "  - Transaction Rate: 1 every 5 seconds"
echo "  - Test Duration: 3 minutes"
echo "  - Expected Transaction Duration: 60+ seconds"
echo ""
echo "Prerequisites:"
echo "  1. k6 must be installed (brew install k6)"
echo "  2. Port forwarding must be active:"
echo "     kubectl port-forward svc/airecipe-service 8000:8000 -n airecipe"
echo ""
read -p "Press Enter to start the test or Ctrl+C to cancel..."
echo ""

# Check if k6 is installed
if ! command -v k6 &> /dev/null; then
    echo "Error: k6 is not installed. Please install it with: brew install k6"
    exit 1
fi

# Check if port 8000 is accessible
if ! curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/demo --max-time 5 > /dev/null 2>&1; then
    echo "Warning: Cannot connect to http://localhost:8000/demo"
    echo "Make sure port-forwarding is active:"
    echo "  kubectl port-forward svc/airecipe-service 8000:8000 -n airecipe"
    echo ""
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Run the k6 test
echo "Starting k6 load test..."
echo ""

k6 run \
  --out json="${SCRIPT_DIR}/test-results-$(date +%Y%m%d-%H%M%S).json" \
  "${SCRIPT_DIR}/long-transaction-test.js"

echo ""
echo "Test completed!"
echo "Results saved to: ${SCRIPT_DIR}/test-results-*.json"
