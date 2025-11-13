#!/bin/bash
# Build and push SSL proxy image to DigitalOcean Container Registry
# Platform: AMD64/x86_64 only (for DO droplets)

set -e  # Exit on error

REGISTRY="${REGISTRY:-registry.digitalocean.com/crudibase-registry}"
IMAGE_NAME="${IMAGE_NAME:-ssl-proxy}"
TAG="${TAG:-latest}"
FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${TAG}"

echo "=== Building and Pushing SSL Proxy Image ==="
echo "Registry: $REGISTRY"
echo "Image: $IMAGE_NAME"
echo "Tag: $TAG"
echo "Full image name: $FULL_IMAGE"
echo ""

# Check if doctl is installed
if ! command -v doctl &> /dev/null; then
    echo "❌ Error: doctl is not installed"
    echo "Install it with: brew install doctl"
    exit 1
fi

# Check if docker buildx is available
if ! docker buildx version &> /dev/null; then
    echo "❌ Error: docker buildx is not available"
    echo "Update Docker Desktop to the latest version"
    exit 1
fi

# Authenticate with DigitalOcean Container Registry
echo "🔐 Authenticating with DigitalOcean Container Registry..."
if ! doctl registry login; then
    echo "❌ Failed to authenticate with registry"
    echo "Run 'doctl auth init' first to set up authentication"
    exit 1
fi

# Create or use existing buildx builder for multi-platform builds
BUILDER_NAME="ssl-proxy-builder"
if ! docker buildx inspect "$BUILDER_NAME" &> /dev/null; then
    echo "📦 Creating buildx builder: $BUILDER_NAME"
    docker buildx create --name "$BUILDER_NAME" --use
else
    echo "📦 Using existing buildx builder: $BUILDER_NAME"
    docker buildx use "$BUILDER_NAME"
fi

# Bootstrap the builder
docker buildx inspect --bootstrap

# Build and push the image for AMD64 platform
echo ""
echo "🏗️  Building and pushing image for linux/amd64..."
echo ""

docker buildx build \
    --platform linux/amd64 \
    --tag "$FULL_IMAGE" \
    --push \
    --progress=plain \
    .

echo ""
echo "✅ Successfully built and pushed: $FULL_IMAGE"
echo ""
echo "📋 Next steps:"
echo "1. SSH to your DigitalOcean droplet"
echo "2. Authenticate: doctl registry login"
echo "3. Pull image: docker pull $FULL_IMAGE"
echo "4. Run with docker-compose on the droplet"
echo ""
