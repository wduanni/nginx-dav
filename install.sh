#!/usr/bin/env bash
set -e  # 任一步出错直接退出

echo "==== [0] 检查是否以 root 身份运行 ===="
if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 或 sudo 运行本脚本！"
    exit 1
fi

echo "==== [1] 检查 nginx 是否已安装 ===="
if command -v nginx >/dev/null 2>&1; then
    echo "[信息] 检测到已安装 nginx。"
    nginx_installed_before=1
else
    echo "[信息] 未检测到 nginx，先通过 apt 安装一次以获取基础配置..."
    apt-get update
    apt-get install -y nginx
    nginx_installed_before=0
fi

echo "==== [2] 停止并禁用 nginx systemd 服务 ===="
if systemctl list-unit-files | grep -q '^nginx\.service'; then
    echo "[信息] 停止 nginx 服务..."
    systemctl stop nginx || true
else
    echo "[信息] 未发现 nginx.service，跳过 stop/disable。"
fi

echo "==== [3] 使用 apt remove 卸载 nginx（保留配置文件） ===="
apt-get remove -y nginx nginx-core nginx-common || true
apt-get autoremove -y || true
echo "[完成] nginx 软件包已移除（配置文件应仍保留在 /etc/nginx）。"

echo "==== [4] 准备源码目录 /home/wdn 并 clone 仓库 ===="
mkdir -p /home/wdn
cd /home/wdn

if [ -d nginx-dav ]; then
    echo "[信息] 目录 /home/wdn/nginx-dav 已存在，跳过 git clone。"
    echo "       如需重新拉取，请手动删除该目录后再运行脚本。"
else
    echo "[信息] 正在克隆 https://github.com/wduanni/nginx-dav.git ..."
    git clone https://github.com/wduanni/nginx-dav.git
fi

cd /home/wdn/nginx-dav

echo "==== [5] 安装编译依赖环境 ===="
apt-get update
apt-get install -y \
    build-essential \
    libpcre3 libpcre3-dev \
    zlib1g zlib1g-dev \
    libssl-dev \
    libgd-dev \
    libxml2 libxml2-dev \
    uuid-dev \
    libxslt-dev

echo "[完成] 编译依赖安装完毕。"

echo "==== [6] 进入 nginx-1.22.1 目录并准备配置 ===="
cd nginx-1.22.1

echo "[信息] 为 configure 赋予可执行权限..."
chmod +x configure

echo "==== [7] 执行 ./configure 配置 nginx ===="
./configure \
  --prefix=/usr/share/nginx \
  --sbin-path=/usr/sbin/nginx \
  --conf-path=/etc/nginx/nginx.conf \
  --http-log-path=/var/log/nginx/access.log \
  --error-log-path=/var/log/nginx/error.log \
  --lock-path=/var/lock/nginx.lock \
  --pid-path=/run/nginx.pid \
  --modules-path=/usr/lib/nginx/modules \
  --http-client-body-temp-path=/var/lib/nginx/body \
  --http-fastcgi-temp-path=/var/lib/nginx/fastcgi \
  --http-proxy-temp-path=/var/lib/nginx/proxy \
  --http-scgi-temp-path=/var/lib/nginx/scgi \
  --http-uwsgi-temp-path=/var/lib/nginx/uwsgi \
  --with-compat \
  --with-cc-opt='-g -O2 -fstack-protector-strong -Wformat -Werror=format-security -fPIC -Wdate-time -D_FORTIFY_SOURCE=2' \
  --with-ld-opt='-Wl,-Bsymbolic-functions -Wl,-z,relro -Wl,-z,now -fPIC' \
  \
  --with-pcre-jit \
  --with-threads \
  --with-debug \
  \
  --with-http_ssl_module \
  --with-http_v2_module \
  --with-http_stub_status_module \
  --with-http_realip_module \
  --with-http_auth_request_module \
  --with-http_slice_module \
  --with-http_addition_module \
  --with-http_gunzip_module \
  --with-http_gzip_static_module \
  --with-http_sub_module \
  \
  --with-http_dav_module \
  --add-module=../nginx-dav-ext-module \
  --add-module=../headers-more-nginx-module

echo "[完成] configure 执行完毕。"

echo "==== [8] 开始编译 nginx（make -j1） ===="
make -j1
echo "[完成] make 编译完成。"

echo "==== [9] 执行 make install 安装 nginx ===="
make install
echo "[完成] nginx 安装完成。"

echo "==== [10] 全部步骤执行完毕！===="
echo "nginx 已按指定参数编译并安装到 /usr/sbin/nginx，配置路径为 /etc/nginx/nginx.conf"
