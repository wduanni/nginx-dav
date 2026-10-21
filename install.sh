#!/usr/bin/env bash
# 用法:
#   全新安装: curl -fsSL https://raw.githubusercontent.com/wduanni/nginx-dav/refs/heads/main/install.sh | sudo bash
#   升级版本: curl -fsSL https://raw.githubusercontent.com/wduanni/nginx-dav/refs/heads/main/install.sh | sudo bash -s -- upgrade
#   本地运行: sudo ./install.sh [install|upgrade]
#
# 升级 nginx 时只需修改下面的 NGINX_VERSION（可用环境变量覆盖），模块源码保留在仓库中。
set -euo pipefail  # 任一步出错直接退出

NGINX_VERSION="${NGINX_VERSION:-1.30.6}"
MODE="${1:-install}"
REPO_URL="https://github.com/wduanni/nginx-dav.git"
REPO_DIR="/home/wdn/nginx-dav"
BUILD_DIR="$REPO_DIR/build"
NGINX_BIN="/usr/sbin/nginx"

# nginx 官方维护者 PGP 公钥指纹（https://nginx.org/en/pgp_keys.html）
# 源码包签名必须来自其中之一，否则拒绝编译
NGINX_KEYS="arut pluknet sb thresh"
NGINX_KEY_FPRS="
43387825DDB1BB97EC36BA5D007C8D7C15D87369
D6786CE303D9A9022998DC6CC8464D549AF75C0A
7338973069ED3F443F4D37DFA64FD5B17ADB39A8
13C82A63B603576156E30A4EA0EA981B66B0D967
"

case "$MODE" in
    install|upgrade) ;;
    *) echo "用法: $0 [install|upgrade]"; exit 1 ;;
esac

echo "==== [0] 检查是否以 root 身份运行 ===="
if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 或 sudo 运行本脚本！"
    exit 1
fi
echo "[信息] 模式: $MODE，目标版本: nginx $NGINX_VERSION"

if [ "$MODE" = "install" ]; then
    echo "==== [1] 检查 nginx 是否已安装 ===="
    if command -v nginx >/dev/null 2>&1; then
        echo "[信息] 检测到已安装 nginx。"
    else
        echo "[信息] 未检测到 nginx，先通过 apt 安装一次以获取基础配置..."
        apt-get update
        apt-get install -y nginx
    fi

    echo "==== [2] 停止 nginx systemd 服务 ===="
    if systemctl cat nginx.service >/dev/null 2>&1; then
        echo "[信息] 停止 nginx 服务..."
        systemctl stop nginx || true
    else
        echo "[信息] 未发现 nginx.service，跳过 stop。"
    fi

    echo "==== [3] 使用 apt remove 卸载 nginx（保留配置文件） ===="
    apt-get remove -y nginx nginx-core nginx-common || true
    apt-get autoremove -y || true
    echo "[完成] nginx 软件包已移除（配置文件应仍保留在 /etc/nginx）。"
else
    echo "==== [1-3] 升级模式：跳过 apt 安装/卸载 nginx ===="
    if [ ! -x "$NGINX_BIN" ]; then
        echo "[错误] 未找到 $NGINX_BIN，请先使用 install 模式安装。"
        exit 1
    fi
    "$NGINX_BIN" -v
fi

echo "==== [4] 准备源码目录 $REPO_DIR ===="
mkdir -p "$(dirname "$REPO_DIR")"
if [ -d "$REPO_DIR/.git" ]; then
    echo "[信息] 目录 $REPO_DIR 已存在，尝试 git pull 更新模块源码..."
    git -C "$REPO_DIR" pull --ff-only || echo "[警告] git pull 失败，继续使用本地源码。"
else
    echo "[信息] 正在克隆 $REPO_URL ..."
    git clone "$REPO_URL" "$REPO_DIR"
fi

echo "==== [5] 安装编译依赖环境 ===="
apt-get update
apt-get install -y \
    build-essential \
    curl ca-certificates gnupg git \
    libpcre2-dev \
    zlib1g-dev \
    libssl-dev \
    libxml2-dev \
    libxslt1-dev
echo "[完成] 编译依赖安装完毕。"

echo "==== [6] 下载并校验 nginx-$NGINX_VERSION 源码 ===="
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
tarball="nginx-$NGINX_VERSION.tar.gz"
curl -fsSL -o "$tarball" "https://nginx.org/download/$tarball"
curl -fsSL -o "$tarball.asc" "https://nginx.org/download/$tarball.asc"

gnupg_home="$(mktemp -d)"
trap 'rm -rf "$gnupg_home"' EXIT
for key in $NGINX_KEYS; do
    curl -fsSL "https://nginx.org/keys/$key.key" | gpg --homedir "$gnupg_home" --batch --quiet --import
done
# VALIDSIG 行的最后一个字段是主密钥指纹
signer="$(gpg --homedir "$gnupg_home" --batch --status-fd 1 --verify "$tarball.asc" "$tarball" 2>/dev/null \
    | awk '$2 == "VALIDSIG" { print $NF }' || true)"
if [ -z "$signer" ] || ! grep -qx "$signer" <<< "$NGINX_KEY_FPRS"; then
    echo "[错误] $tarball 签名校验失败，已中止！"
    exit 1
fi
echo "[完成] 签名校验通过（签名密钥 $signer）。"

rm -rf "nginx-$NGINX_VERSION"
tar xzf "$tarball"

echo "==== [7] 执行 ./configure 配置 nginx ===="
cd "nginx-$NGINX_VERSION"
./configure \
  --prefix=/usr/share/nginx \
  --sbin-path="$NGINX_BIN" \
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
  --add-module="$REPO_DIR/nginx-dav-ext-module" \
  --add-module="$REPO_DIR/headers-more-nginx-module"
echo "[完成] configure 执行完毕。"

echo "==== [8] 开始编译 nginx（make -j$(nproc)） ===="
make -j"$(nproc)"
echo "[完成] make 编译完成。"

echo "==== [9] 使用新编译的 nginx 检查现有配置 ===="
mkdir -p /var/lib/nginx /var/log/nginx
if [ -f /etc/nginx/nginx.conf ]; then
    objs/nginx -t -c /etc/nginx/nginx.conf
fi

echo "==== [10] 执行 make install 安装 nginx ===="
backup=""
if [ -x "$NGINX_BIN" ]; then
    old_version="$("$NGINX_BIN" -v 2>&1 | sed 's#.*/##')"
    backup="$NGINX_BIN.$old_version.bak"
    cp -p "$NGINX_BIN" "$backup"
    echo "[信息] 旧版本已备份到 $backup"
fi
make install
echo "[完成] nginx 安装完成。"

install -m 644 "$REPO_DIR/nginx.service" /etc/systemd/system/nginx.service
systemctl daemon-reload
systemctl enable nginx

if [ "$MODE" = "upgrade" ]; then
    echo "==== [11] 重启 nginx ===="
    if ! systemctl restart nginx; then
        echo "[错误] 新版本启动失败，回滚到旧版本..."
        if [ -n "$backup" ]; then
            cp -p "$backup" "$NGINX_BIN"
            systemctl restart nginx
        fi
        exit 1
    fi
fi

echo "==== 全部步骤执行完毕！===="
"$NGINX_BIN" -v
echo "nginx 已按指定参数编译并安装到 $NGINX_BIN，配置路径为 /etc/nginx/nginx.conf"
if [ -n "$backup" ]; then
    echo "如需回滚: cp -p $backup $NGINX_BIN && systemctl restart nginx"
fi
