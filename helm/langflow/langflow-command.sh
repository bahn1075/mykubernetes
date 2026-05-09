#!/bin/bash

# Langflow Helm Chart Deployment Script

# Add Langflow Helm repository
helm repo add langflow https://langflow-ai.github.io/langflow-helm-charts
helm repo update

# Deploy using remote chart with custom values
cd /app/mykubernetes/helm/langflow
helm upgrade --install langflow langflow/langflow-ide -n langflow -f values.yaml
