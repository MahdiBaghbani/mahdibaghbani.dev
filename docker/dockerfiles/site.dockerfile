FROM ghcr.io/getzola/zola:v0.19.1 AS zola

COPY .                                              /project
WORKDIR                                             /project

# build static website with zola.
RUN ["zola", "build"]

FROM nginx:1.27.0-alpine3.19-slim

# keys for oci taken from:
# https://github.com/opencontainers/image-spec/blob/main/annotations.md#pre-defined-annotation-keys
LABEL org.opencontainers.image.licenses=AGPL-3.0-only
LABEL org.opencontainers.image.title="Mahdi Baghbani personal website Image"
LABEL org.opencontainers.image.source="https://github.com/MahdiBaghbani/mahdibaghbani.dev"
LABEL org.opencontainers.image.authors="Mohammad Mahdi Baghbani Pourvahid"

WORKDIR                                             /var/www/html
COPY --from=zola /project/public                    /var/www/html
COPY ./docker/configs/site.conf                     /etc/nginx/templates/default.conf.template
