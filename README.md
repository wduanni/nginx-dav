# nginx-dav
 nginx full webdav support

基于官方 nginx 源码 + `nginx-dav-ext-module` + `headers-more-nginx-module` 编译，提供完整 WebDAV 支持。
nginx 源码由安装脚本从 nginx.org 下载并校验 PGP 签名，版本由 `install.sh` 中的 `NGINX_VERSION` 指定。

全新安装：

    curl -fsSL https://raw.githubusercontent.com/wduanni/nginx-dav/refs/heads/main/install.sh | sudo bash

升级 nginx（不卸载/重装 apt 包，编译前用新版本检查现有配置，失败自动回滚）：

    curl -fsSL https://raw.githubusercontent.com/wduanni/nginx-dav/refs/heads/main/install.sh | sudo bash -s -- upgrade

临时指定其他版本：`sudo NGINX_VERSION=1.30.6 ./install.sh upgrade`
