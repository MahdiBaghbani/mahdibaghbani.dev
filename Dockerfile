FROM ghcr.io/getzola/zola:v0.19.1 as zola

ADD .                                               /project
WORKDIR                                             /project

RUN ["zola", "build"]

FROM nginx:1.27.0-alpine3.19-slim
WORKDIR                                             /var/www/html
COPY --from=zola /project/public                    /var/www/html
COPY --from=zola /project/configs/default.conf      /etc/nginx/templates/default.conf.template
