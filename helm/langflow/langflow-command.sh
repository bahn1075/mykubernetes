helm repo add langflow https://langflow-ai.github.io/langflow-helm-charts
helm repo update

helm upgrade --install langflow langflow/langflow-ide -n langflow -f /app/langflow-helm/values.yaml
