#!/usr/bin/env sh

mkdir -p /data/mysql5/data
mkdir -p /data/mysql5/log
cat > /data/mysql5/my.cnf << EOF
[client]
default-character-set=utf8mb4
[mysql]
default-character-set=utf8mb4
[mysqld]
max_connections = 2000
secure_file_priv=/var/lib/mysql
sql_mode=STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION
EOF
docker run -p 3306:3306 --name mysql5    -v /data/mysql5/data:/var/lib/mysql    -v /etc/localtime:/etc/localtime:ro -v /data/mysql5/my.cnf:/etc/mysql/conf.d/my.cnf -e MYSQL_ROOT_PASSWORD=123456  -e MYSQL_USER=kylin  -e MYSQL_PASSWORD=123456  -e TZ=Asia/Shanghai  --restart unless-stopped  -d mysql:5.7.29
