# syntax=docker/dockerfile:1

ARG PAPERLESS_TAG=3.2.1
FROM ghcr.io/paperless-ngx/paperless-ngx:${PAPERLESS_TAG}

# Greek OCR data, baked in so containers don't apt-install it on every start.
# Cache mounts keep apt's downloads out of the image and speed up rebuilds.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
 && apt-get update \
 && apt-get install --yes --no-install-recommends tesseract-ocr-ell

ENV PAPERLESS_OCR_LANGUAGE=ell+eng
