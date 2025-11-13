#!/bin/bash
# Test build locally without pushing to registry

set -e

IMAGE_NAME="${IMAGE_NAME:-ssl-proxy}"
TAG="${TAG:-test}"

echo "=== Testing SSL Proxy Build ==="
echo "Building image: $IMAGE_NAME:$TAG"
echo ""

# Build for AMD64 platform
docker buildx build \
    --platform linux/amd64 \
    --tag "$IMAGE_NAME:$TAG" \
    --load \
    --progress=plain \
    .

echo ""
echo "✅ Build successful: $IMAGE_NAME:$TAG"
echo ""
echo "🧪 To test locally:"
echo "  1. Update docker-compose.yml to use image: $IMAGE_NAME:$TAG"
echo "  2. Run: docker-compose up"
echo "  3. Test endpoints (requires backend services running)"
echo ""
echo "🔍 Image details:"
docker images "$IMAGE_NAME:$TAG"
echo ""
