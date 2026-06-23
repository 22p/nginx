# nginx

## 快速开始

```sh
# 从 Quay.io 拉取
podman pull quay.io/bbbb/nginx:latest

# 或从 GHCR 拉取
podman pull ghcr.io/22p/nginx:latest
```

### 启用 kTLS

kTLS (Kernel TLS) 将 TLS 加解密卸载到内核，降低 CPU 开销。需要内核支持（Linux 4.13+）：

```nginx
ssl_conf_command Options KTLS;
```

### 启用 ECH

ECH (Encrypted Client Hello) 加密 TLS 握手中的 SNI，防止中间设备窥探访问的域名。需要客户端支持（Chrome/Edge 119+、Firefox 128+）和 DNS HTTPS 记录配合。

**1. 生成 ECH 密钥：**

```sh
podman run --rm quay.io/bbbb/nginx:latest \
  openssl ech -public_name example.com -out /dev/stdout > echconfig.pem
```


**3. 添加 DNS HTTPS 记录：**

```
example.com. 3600 IN HTTPS 1 . alpn="h2,h3" ech=AD7+DQA6aAAgACAUuLn6xfqQz0tigs6Kc3ASmowKga4L3XQFm+c5pJpBcAAEAAEA
AQALZXhhbXBsZS5jb20AAA==
```

**4. nginx 配置：**

```nginx
ssl_ech_key_file cert/echconfig.pem;
```

### 使用 ACME 自动证书

加载 `ngx_http_acme_module` 模块并在配置中使用 ACME 指令，详见 [nginx-acme](https://github.com/nginx/nginx-acme)。
