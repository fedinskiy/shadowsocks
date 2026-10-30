FROM registry.access.redhat.com/ubi9/ubi AS build
ARG VERSION=1.25.0

RUN <<EOF
dnf install -y xz
curl -LO https://github.com/shadowsocks/shadowsocks-rust/releases/download/v${VERSION}/shadowsocks-v${VERSION}.x86_64-unknown-linux-gnu.tar.xz
curl -LO https://github.com/shadowsocks/shadowsocks-rust/releases/download/v${VERSION}/shadowsocks-v${VERSION}.x86_64-unknown-linux-gnu.tar.xz.sha256
sha256sum -c shadowsocks-v${VERSION}.x86_64-unknown-linux-gnu.tar.xz.sha256
tar -xaf shadowsocks-v${VERSION}.x86_64-unknown-linux-gnu.tar.xz ssserver sslocal
chmod 755 ssserver
EOF

# newer version of ssserver require newer glibc
FROM registry.access.redhat.com/ubi10/ubi-micro

COPY --from=build ssserver ssserver

CMD ["./ssserver","-c", "server.conf"]
