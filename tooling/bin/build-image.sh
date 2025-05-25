#!/usr/bin/env bash
echo "$GITHUB_TOKEN" | skopeo login ghcr.io --username "$GITHUB_USERNAME" --password-stdin
result=$(nix build .#snapbin-image --no-link --print-out-paths)
# ${variabe,,} converts a string to lowercase
skopeo copy --insecure-policy docker-archive://"$result" docker://"ghcr.io/${GITHUB_REPOSITORY,,}/snapbin:latest"
