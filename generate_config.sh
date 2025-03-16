#!/bin/bash


ip=${1##*@}
set -euo pipefail

port=${2:?10500}
version=${3:?1.15.4}
echo "Enter password"
read -s password

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

cat > socks.service <<EOF
[Unit]
Description=Podman service for shadowsocks
Documentation=https://github.com/fedinskiy/shadowsocks
Wants=network-online.target
After=network-online.target
RequiresMountsFor=/run/user/{{uid}}/containers

[Service]
Environment=PODMAN_SYSTEMD_UNIT=%n
Restart=on-failure
TimeoutStopSec=70
ExecStart=/usr/bin/podman start socks
ExecStop=/usr/bin/podman stop -t 10 socks
ExecStopPost=/usr/bin/podman stop -t 10 socks
PIDFile=/run/user/{{uid}}/socks-conmon.pid
Type=forking

[Install]
WantedBy=default.target
EOF

echo "Downloading the binaries of version $version"
curl -LO https://github.com/shadowsocks/shadowsocks-rust/releases/download/v$version/shadowsocks-v$version.x86_64-unknown-linux-gnu.tar.xz
curl -LO https://github.com/shadowsocks/shadowsocks-rust/releases/download/v$version/shadowsocks-v$version.x86_64-unknown-linux-gnu.tar.xz.sha256

sha256sum -c shadowsocks-v$version.x86_64-unknown-linux-gnu.tar.xz.sha256
tar -xaf shadowsocks-v$version.x86_64-unknown-linux-gnu.tar.xz ssserver sslocal

echo "Creating container"
podman build -t quay.io/fdudinsk/shadowsocks -f Dockerfile
podman push quay.io/fdudinsk/shadowsocks

echo "Gathering data about the server"
result=$(ssh $1 /bin/bash << 'EOF'
	folder=$(pwd)/ssocks
	rm -r $folder || mkdir $folder
	echo $folder && id -u
EOF
)

rlt=($result)
folder=${rlt[0]}
uid=${rlt[1]}

echo "Copying the configs"
scp server.conf socks.service $1:$folder
echo "Starting the server"

ssh -t $1 "sed -ie 's/{{uid}}/${uid}/' ${folder}/socks.service \
&& sudo cp ${folder}/socks.service /etc/systemd/user/ \
&& sudo ufw allow $port"

ssh $1 /bin/bash <<EOF
podman stop socks || podman rm socks
podman create --name socks -p $port:$port \
--conmon-pidfile=/run/user/${uid}/socks-conmon.pid \
--pidfile=/run/user/${uid}/socks.pid \
--mount type=bind,source=${folder}/server.conf,target=/server.conf,readonly \
quay.io/fdudinsk/shadowsocks

loginctl enable-linger # to keep server running after logout
systemctl --user stop socks
systemctl --user start socks
systemctl --user enable socks
EOF
