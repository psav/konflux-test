#!/bin/sh
echo "Hello from Image 2!"
echo "This container proves the signed/sealed image chain."
echo "Image 1 Digest: ${IMAGE1_DIGEST}"
echo "Image 1 URL: ${IMAGE1_URL}"
echo "This digest was baked in at build time, proving atomic build."
echo "Timestamp: $(date)"
