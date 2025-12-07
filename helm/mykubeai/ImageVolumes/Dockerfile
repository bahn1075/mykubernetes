FROM python:3.9-slim

# Set working directory
WORKDIR /models

# Install git and git-lfs for downloading models
RUN apt-get update && apt-get install -y \
    git \
    git-lfs \
    && rm -rf /var/lib/apt/lists/*

# Initialize git-lfs
RUN git lfs install

# Clone the Qwen3-4B model from Hugging Face
RUN git clone https://huggingface.co/Qwen/Qwen3-4B /models/qwen3-4b

# Set proper permissions
RUN chmod -R 755 /models

# Create a simple script to keep the container running
RUN echo '#!/bin/bash\necho "Qwen3-4B model container is running..."\ntail -f /dev/null' > /start.sh && chmod +x /start.sh

EXPOSE 8080

CMD ["/start.sh"]