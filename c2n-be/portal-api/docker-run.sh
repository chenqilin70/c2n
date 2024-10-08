#!/usr/bin/env sh

docker run -p 8080:8080 --name portal-api --restart: always    \
-e SPRING_PROFILES_ACTIVE=dev    \
-e TZ=Asia/Shanghai    \
-e OWNER_PRIVATE_KEY=privatekey    \
-e DB_HOST=mysql5:3306    \
-e DB_NAME=brewery    \
-e DB_USERNAME=root    \
-e DB_PWD=123456    \
-d registry.localdev:5002/bobabrewery/portal-api:0.0.1-snapshot-79b82e2

