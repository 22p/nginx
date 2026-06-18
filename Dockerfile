FROM alpine:latest AS builder
ENV PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig

RUN apk add --no-cache \
        build-base \
        linux-headers \
        pcre2-dev \
        zlib-dev \
        perl \
        curl \
        ca-certificates \
        bash \
        coreutils \
        jq \
        git \
        rust \
        cargo \
        pkgconfig \
        clang-dev

WORKDIR /build

RUN OSSL_VER=$(curl -fsSL "https://api.github.com/repos/openssl/openssl/releases?per_page=100" \
        | jq -r '[.[] | select(.prerelease==false) | .tag_name | select(startswith("openssl-4."))] | .[0]' \
        | sed 's/^openssl-//') \
 && echo "Building openssl ${OSSL_VER}" \
 && curl -fsSL "https://github.com/openssl/openssl/releases/download/openssl-${OSSL_VER}/openssl-${OSSL_VER}.tar.gz" -o openssl.tar.gz \
 && tar -xzf openssl.tar.gz \
 && cd "openssl-${OSSL_VER}" \
 && ./Configure \
        --prefix=/usr/local \
        enable-ech \
        enable-ktls \
        no-legacy \
        no-tests \
        no-docs \
 && make -j"$(nproc)" \
 && make install_sw

RUN NGX_VER=$(curl -fsSL "https://api.github.com/repos/nginx/nginx/releases/latest" \
        | jq -r '.tag_name' | sed 's/^release-//') \
 && echo "Building nginx ${NGX_VER}" \
 && curl -fsSL "https://nginx.org/download/nginx-${NGX_VER}.tar.gz" -o nginx.tar.gz \
 && tar -xzf nginx.tar.gz \
 && mv "nginx-${NGX_VER}" nginx \
 && cd nginx \
 && ./configure \
        --prefix=/etc/nginx \
        --sbin-path=/usr/sbin/nginx \
        --modules-path=/usr/lib/nginx/modules \
        --conf-path=/etc/nginx/nginx.conf \
        --error-log-path=/var/log/nginx/error.log \
        --http-log-path=/var/log/nginx/access.log \
        --pid-path=/run/nginx.pid \
        --lock-path=/run/nginx.lock \
        --http-client-body-temp-path=/var/cache/nginx/client_temp \
        --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
        --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
        --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
        --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
        --user=nginx \
        --group=nginx \
        --with-compat \
        --with-file-aio \
        --with-threads \
        --with-http_addition_module \
        --with-http_auth_request_module \
        --with-http_dav_module \
        --with-http_flv_module \
        --with-http_gunzip_module \
        --with-http_gzip_static_module \
        --with-http_mp4_module \
        --with-http_random_index_module \
        --with-http_realip_module \
        --with-http_secure_link_module \
        --with-http_slice_module \
        --with-http_ssl_module \
        --with-http_stub_status_module \
        --with-http_sub_module \
        --with-http_v2_module \
        --with-http_v3_module \
        --with-mail \
        --with-mail_ssl_module \
        --with-stream \
        --with-stream_realip_module \
        --with-stream_ssl_module \
        --with-stream_ssl_preread_module \
        --with-cc-opt='-O2 -fstack-clash-protection -Wformat -Werror=format-security' \
        --with-ld-opt='-Wl,--as-needed,-O1,--sort-common -Wl,-z,pack-relative-relocs' \
 && make -j"$(nproc)" \
 && make install \
 && strip /usr/sbin/nginx

RUN NGX_ACME_VER=$(curl -fsSL "https://api.github.com/repos/nginx/nginx-acme/releases/latest" | jq -r '.tag_name') \
 && echo "Building nginx-acme ${NGX_ACME_VER}" \
 && curl -fsSL "https://github.com/nginx/nginx-acme/releases/download/${NGX_ACME_VER}/nginx-acme-${NGX_ACME_VER#v}.tar.gz" -o nginx-acme.tar.gz \
 && tar -xzf nginx-acme.tar.gz \
 && mv "nginx-acme-${NGX_ACME_VER#v}" nginx-acme \
 && cd nginx-acme \
 && export NGINX_BUILD_DIR=/build/nginx/objs \
 && cargo build --release

FROM alpine:latest

RUN apk add --no-cache \
        pcre2 \
        zlib \
        ca-certificates \
        tzdata \
        tini \
        curl \
        libgcc \
 && addgroup -S nginx \
 && adduser -S -D -H -u 101 -h /var/cache/nginx -s /sbin/nologin -G nginx -g nginx nginx \
 && mkdir -p /var/cache/nginx/client_temp \
               /var/cache/nginx/proxy_temp \
               /var/cache/nginx/fastcgi_temp \
               /var/cache/nginx/uwsgi_temp \
               /var/cache/nginx/scgi_temp \
               /var/log/nginx \
               /etc/nginx/conf.d \
 && chown -R nginx:nginx /var/cache/nginx /var/log/nginx \
 && ln -sf /dev/stdout /var/log/nginx/access.log \
 && ln -sf /dev/stderr /var/log/nginx/error.log

COPY --from=builder /usr/sbin/nginx /usr/sbin/nginx
COPY --from=builder /etc/nginx /etc/nginx
COPY --from=builder /usr/local/bin/openssl /usr/local/bin/
COPY --from=builder /usr/local/lib*/libssl.so.4 /usr/local/lib*/libcrypto.so.4 /usr/lib/
COPY --from=builder /build/nginx-acme/target/release/libnginx_acme.so /usr/lib/nginx/modules/ngx_http_acme_module.so
COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 80 443

STOPSIGNAL SIGQUIT

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["nginx", "-g", "daemon off;"]
