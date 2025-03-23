# ⛳ Base image
FROM ubuntu:22.04 as builder

# Cài gói build & các công cụ cần thiết
RUN apt update && apt install -y \
  build-essential git curl cmake automake autoconf libtool \
  libpcre3 libpcre3-dev zlib1g zlib1g-dev libssl-dev \
  ca-certificates unzip wget

# Cài cmake từ source để tránh lỗi QEMU multi-arch
RUN curl -LO https://github.com/Kitware/CMake/releases/download/v3.25.2/cmake-3.25.2.tar.gz && \
    tar -xzf cmake-3.25.2.tar.gz && cd cmake-3.25.2 && \
    ./bootstrap && make -j$(nproc) && make install

# Clone Brotli module
RUN git clone --depth=1 https://github.com/google/ngx_brotli /usr/local/src/ngx_brotli && \
    cd /usr/local/src/ngx_brotli && git submodule update --init

# Build Brotli dependency
RUN cd /usr/local/src/ngx_brotli/deps/brotli && mkdir -p out && cd out && \
    cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local .. && \
    make -j$(nproc) && make install

# Build OpenResty với Brotli module
RUN curl -fsSL https://openresty.org/download/openresty-1.21.4.1.tar.gz | tar xz -C /usr/local/src

RUN cd /usr/local/src/openresty-1.21.4.1 && \
    ./configure \
      --prefix=/usr/local/openresty \
      --with-pcre-jit \
      --with-http_ssl_module \
      --with-http_v2_module \
      --with-http_realip_module \
      --with-http_stub_status_module \
      --add-module=/usr/local/src/ngx_brotli && \
    make -j$(nproc) && make install

# Cài LuaRocks
ARG LUAROCKS_VERSION=3.9.2
RUN curl -fsSL https://luarocks.org/releases/luarocks-${LUAROCKS_VERSION}.tar.gz | tar xz && \
    cd luarocks-${LUAROCKS_VERSION} && \
    ./configure --with-lua=/usr/local/openresty/luajit \
                --lua-suffix=jit \
                --with-lua-include=/usr/local/openresty/luajit/include/luajit-2.1 && \
    make && make install

# Image tối ưu
FROM debian:bullseye-slim

COPY --from=builder /usr/local/openresty /usr/local/openresty
COPY --from=builder /usr/local/bin/luarocks /usr/local/bin/luarocks

ENV PATH=$PATH:/usr/local/openresty/nginx/sbin:/usr/local/openresty/bin:/usr/local/openresty/luajit/bin

WORKDIR /usr/local/openresty/nginx
EXPOSE 80 443

CMD ["/usr/local/openresty/nginx/sbin/nginx", "-g", "daemon off;"]
