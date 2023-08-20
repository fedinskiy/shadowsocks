#!/bin/bash


ip=${1##*@}
set -euo pipefail

port=${2:?10500}
version=${3:?1.15.4}
echo "Enter password"
read password

echo "Generating configs for $ip:$port"
# based on https://habr.com/ru/articles/358126/
cat > server.conf <<EOF
{
	"server": "0.0.0.0",
	"server_port": $port,
	"password": "$password",
	"timeout": 60,
	"method": "chacha20-ietf-poly1305",
	"fast_open": true
}
EOF

cat > client.conf <<EOF
{
	"server": "$ip",
	"server_port": $port,
	"password": "$password",
	"timeout": 60,
	"method": "chacha20-ietf-poly1305",
	"fast_open": true,
	"local_address": "127.0.0.1",
	"local_port": 1080
}
EOF

folder=$(ssh $1 'pwd')/ssocks

cat > socks.service <<EOF
[Unit]
Description=Podman service for shadowsocks
Documentation=https://github.com/fedinskiy/deploy-vpn
Wants=network-online.target
After=network-online.target
RequiresMountsFor=/run/user/1000/containers

[Service]
Environment=PODMAN_SYSTEMD_UNIT=%n
Restart=on-failure
TimeoutStopSec=70
ExecStart=/usr/bin/podman start socks
ExecStop=/usr/bin/podman stop -t 10 socks
ExecStopPost=/usr/bin/podman stop -t 10 socks
PIDFile=/run/user/1000/socks-conmon.pid
Type=forking

[Install]
WantedBy=default.target
EOF


echo "Downloading the binaries of version $version"
curl -LO https://github.com/shadowsocks/shadowsocks-rust/releases/download/v$version/shadowsocks-v$version.x86_64-unknown-linux-gnu.tar.xz
curl -LO https://github.com/shadowsocks/shadowsocks-rust/releases/download/v$version/shadowsocks-v$version.x86_64-unknown-linux-gnu.tar.xz.sha256

sha256sum -c shadowsocks-v$version.x86_64-unknown-linux-gnu.tar.xz.sha256
tar -xaf shadowsocks-v$version.x86_64-unknown-linux-gnu.tar.xz ssserver sslocal

ssh $1 "rm -r $folder && mkdir $folder"
scp server.conf socks.service $1:$folder

podman build -t quay.io/fdudinsk/shadowsocks -f Dockerfile
podman push quay.io/fdudinsk/shadowsocks

ssh $1 "podman create --name socks -p $port:$port \
--conmon-pidfile=/run/user/1000/socks-conmon.pid \
--pidfile=/run/user/1000/socks.pid \
--mount type=bind,source=$folder/server.conf,target=/server.conf,readonly \
quay.io/fdudinsk/shadowsocks"

ssh -t $1 "sudo cp $folder/socks.service /etc/systemd/user/ \
&& sudo ufw allow $port \
&& systemctl --user stop socks \
&& systemctl --user start socks \
&& systemctl --user enable socks"
