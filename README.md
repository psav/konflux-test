# Konflux Multi-Image Single-Pipeline Proof of Concept

**Objective:** Demonstrate that a single Konflux pipeline can build two container images, embed metadata linking them, and use a scanner component to extract and scan the second image.

**Proof Point:** Show a signed/sealed image chain where Image 2 proves knowledge of Image 1's exact digest, all built in one atomic pipeline run.

## Overview

This proof of concept demonstrates a novel approach to building and securing multiple related container images in a single Konflux pipeline. The key innovations are:

1. **Atomic Multi-Image Build**: One pipeline builds both images sequentially
2. **Cryptographic Linking**: Image 2 contains Image 1's digest baked in at build time
3. **Bidirectional Metadata**: Image 1 is labeled with Image 2's digest after both are built
4. **Separate Scanning**: A scanner component extracts and triggers scanning of Image 2

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Main Build Pipeline (app component)                         │
│                                                              │
│  1. Build Image 1 (primary container)                       │
│  2. Build Image 2 (receives Image 1 digest as build arg)    │
│  3. Label Image 1 (adds Image 2 digest to labels)           │
│                                                              │
│  Result: IMAGE_URL=Image1, IMAGE_DIGEST=Image1-digest       │
└─────────────────────────────────────────────────────────────┘
                        │
                        │ Konflux scans Image 1
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ Scanner Extractor Pipeline (metadata-scanner component)     │
│                                                              │
│  1. Read Image 1's labels                                   │
│  2. Extract Image 2 digest                                  │
│  3. Return Image 2 URL and digest                           │
│                                                              │
│  Result: IMAGE_URL=Image2, IMAGE_DIGEST=Image2-digest       │
└─────────────────────────────────────────────────────────────┘
                        │
                        │ Konflux scans Image 2
                        ▼
                   Both images scanned!
```

## Quick Start

### Prerequisites

1. Access to a Konflux instance
2. Quay.io account with two repositories:
   - `multi-image-poc-image1`
   - `multi-image-poc-image2`
3. GitHub repository with this code
4. kubectl/oc CLI access to your Konflux namespace

### Setup Steps

1. **Update Placeholders**

   Replace these values in all `.tekton/*.yaml` files:
   - `YOUR-ORG` → Your GitHub organization
   - `YOUR-QUAY-ORG` → Your Quay.io organization
   - `YOUR-TENANT-NAMESPACE` → Your Konflux namespace

2. **Create Konflux Application**

   ```bash
   oc create -f - <<EOF
   apiVersion: appstudio.redhat.com/v1alpha1
   kind: Application
   metadata:
     name: multi-image-poc
     namespace: YOUR-TENANT-NAMESPACE
   spec:
     displayName: Multi-Image PoC
   EOF
   ```

3. **Create Main Build Component**

   ```bash
   oc create -f - <<EOF
   apiVersion: appstudio.redhat.com/v1alpha1
   kind: Component
   metadata:
     name: app
     namespace: YOUR-TENANT-NAMESPACE
   spec:
     application: multi-image-poc
     componentName: app
     source:
       git:
         url: https://github.com/YOUR-ORG/konflux-multi-image-poc
         revision: main
   EOF
   ```

4. **Create Scanner Extractor Component**

   ```bash
   oc create -f - <<EOF
   apiVersion: appstudio.redhat.com/v1alpha1
   kind: Component
   metadata:
     name: metadata-scanner
     namespace: YOUR-TENANT-NAMESPACE
   spec:
     application: multi-image-poc
     componentName: metadata-scanner
     source:
       git:
         url: https://github.com/YOUR-ORG/konflux-multi-image-poc
         revision: main
   EOF
   ```

5. **Push to Trigger Build**

   ```bash
   git add .
   git commit -m "Initial PoC setup for multi-image build"
   git push origin main
   ```

## Validation

### Verify Build Success

1. **Check PipelineRuns**

   ```bash
   oc get pipelineruns -n YOUR-TENANT-NAMESPACE | grep app-on-push
   ```

2. **Verify Both Images Exist**

   ```bash
   skopeo inspect docker://quay.io/YOUR-QUAY-ORG/multi-image-poc-image1:latest
   skopeo inspect docker://quay.io/YOUR-QUAY-ORG/multi-image-poc-image2:latest
   ```

3. **Check Metadata Linking**

   Image 1 should have Image 2's digest in labels:
   ```bash
   skopeo inspect docker://quay.io/YOUR-QUAY-ORG/multi-image-poc-image1:latest | \
     jq '.Labels["io.konflux.poc.metadata-image.digest"]'
   ```

### Test Image Functionality

1. **Run Image 1**

   ```bash
   podman run --rm quay.io/YOUR-QUAY-ORG/multi-image-poc-image1:latest
   ```

   Expected output:
   ```
   Hello from Image 1!
   This is the primary container in our multi-image build.
   Timestamp: 2025-12-16T...
   ```

2. **Run Image 2**

   ```bash
   podman run --rm quay.io/YOUR-QUAY-ORG/multi-image-poc-image2:latest
   ```

   Expected output:
   ```
   Hello from Image 2!
   This container proves the signed/sealed image chain.
   Image 1 Digest: sha256:abc123def456...
   Image 1 URL: quay.io/YOUR-QUAY-ORG/multi-image-poc-image1@sha256:abc123def456...
   This digest was baked in at build time, proving atomic build.
   Timestamp: 2025-12-16T...
   ```

### Verify Scanner Extraction

1. **Check Scanner PipelineRun**

   ```bash
   oc get pipelineruns -n YOUR-TENANT-NAMESPACE | grep metadata-scanner-on-push
   ```

2. **Verify Extracted Results**

   ```bash
   oc get pipelinerun <scanner-pipelinerun-name> -n YOUR-TENANT-NAMESPACE -o yaml | \
     grep -A 2 "results:"
   ```

   Should show Image 2's URL and digest.

### Verify Sealed Chain

1. **Get Image 1's Actual Digest**

   ```bash
   IMAGE1_DIGEST=$(skopeo inspect docker://quay.io/YOUR-QUAY-ORG/multi-image-poc-image1:latest | jq -r '.Digest')
   echo "Image 1 Digest: $IMAGE1_DIGEST"
   ```

2. **Get Image 2's Embedded Digest**

   ```bash
   podman run --rm quay.io/YOUR-QUAY-ORG/multi-image-poc-image2:latest | grep "Image 1 Digest"
   ```

3. **Verify Match**

   The digests should be identical, proving the atomic build chain.

## Repository Structure

```
konflux-multi-image-poc/
├── .tekton/
│   ├── app-push.yaml                    # Main build component (builds both images)
│   ├── app-pull-request.yaml            # PR testing
│   ├── metadata-scanner-push.yaml       # Scanner extractor component
│   └── metadata-scanner-pull-request.yaml
├── image1/
│   ├── Containerfile                    # Primary image definition
│   └── entrypoint.sh                    # Simple hello world script
├── image2/
│   ├── Containerfile                    # Metadata image (receives Image 1 digest)
│   └── entrypoint.sh                    # Displays embedded digest
├── pipeline/
│   └── unified-build.yaml               # Custom pipeline that builds both images
└── README.md                            # This file
```

## How It Works

### Phase 1: Build Image 1

The pipeline clones the repository and builds Image 1 using standard buildah task.

**Result:** `IMAGE_URL` and `IMAGE_DIGEST` for Image 1

### Phase 2: Build Image 2 with Image 1's Digest

Image 2 is built with build arguments containing Image 1's exact digest:

```yaml
BUILD_ARGS:
  - IMAGE1_DIGEST=$(tasks.build-image-1.results.IMAGE_DIGEST)
  - IMAGE1_URL=$(tasks.build-image-1.results.IMAGE_URL)
```

These are baked into Image 2's environment and labels at build time.

**Result:** Image 2 cryptographically proves it was built with knowledge of Image 1's digest

### Phase 3: Label Image 1 with Image 2's Digest

After both images are built, the pipeline adds Image 2's digest as a label to Image 1:

```bash
skopeo copy \
  --add-label="io.konflux.poc.metadata-image.digest=$(params.image-2-digest)" \
  "docker://${IMAGE1_REF}" \
  "docker://$(params.image-1-url):latest"
```

**Result:** Image 1 now contains metadata pointing to Image 2

### Phase 4: Scanner Extraction

A separate component reads Image 1's labels and extracts Image 2's digest:

```bash
IMAGE2_DIGEST=$(skopeo inspect docker://image1:latest | \
  jq -r '.Labels["io.konflux.poc.metadata-image.digest"]')
```

It returns this as `IMAGE_URL` and `IMAGE_DIGEST`, triggering Konflux to scan Image 2.

**Result:** Both images are scanned and signed by Konflux

## Success Criteria

- ✅ Single pipeline builds both images atomically
- ✅ Image 2 contains Image 1's digest (provable chain)
- ✅ Image 1 labeled with Image 2's digest (bidirectional link)
- ✅ Scanner extracts Image 2 for separate scanning
- ✅ Both images scanned and signed by Konflux
- ✅ No manual intervention required

## Troubleshooting

### Pipeline Fails at label-image-1 Task

**Symptom:** Authentication or permission errors

**Solution:** Verify pipeline service account has push access:
```bash
oc get secret -n YOUR-TENANT-NAMESPACE | grep quay
```

### Scanner Can't Find Label

**Symptom:** Scanner extractor fails with "Could not find label"

**Debug:**
```bash
skopeo inspect docker://quay.io/YOUR-QUAY-ORG/multi-image-poc-image1:latest | jq '.Labels'
```

Verify `io.konflux.poc.metadata-image.digest` exists.

### Image 2 Shows Wrong Digest

**Symptom:** Embedded digest doesn't match Image 1

**Cause:** Build args not passed correctly

**Debug:** Check build-image-2 task logs:
```bash
oc logs -n YOUR-TENANT-NAMESPACE -l tekton.dev/pipelineTask=build-image-2
```

Look for `--build-arg IMAGE1_DIGEST=...` in buildah command.

## Next Steps

Once this PoC proves successful, the same pattern can be applied to:

- **OLM Operators**: Operator → Bundle → Catalog chain
- **Multi-architecture Builds**: Link manifest lists with platform-specific images
- **Complex Deployments**: Application + sidecar containers
- **Supply Chain Security**: Cryptographic proof of build relationships

## License

This is a proof of concept for testing purposes.
