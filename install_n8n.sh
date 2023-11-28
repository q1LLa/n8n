#!/bin/bash

# Удаление Docker и установка зависимостей
sudo apt-get -y remove docker docker-engine docker.io containerd runc
sudo apt-get -y update
sudo apt-get -y install ca-certificates curl gnupg lsb-release
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Установка Docker
sudo apt-get -y update
sudo apt-get -y install docker-ce docker-ce-cli containerd.io

# Установка плагина docker-compose
sudo apt-get -y install docker-compose-plugin

# Создание docker-compose.yml
cat <<EOF | sudo tee docker-compose.yml > /dev/null
version: "3.7"

services:
  traefik:
    image: "traefik"
    restart: always
    command:
      - "--api=true"
      - "--api.insecure=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
      - "--entrypoints.web.http.redirections.entrypoint.scheme=https"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.mytlschallenge.acme.tlschallenge=true"
      - "--certificatesresolvers.mytlschallenge.acme.email=\$SSL_EMAIL"
      - "--certificatesresolvers.mytlschallenge.acme.storage=/letsencrypt/acme.json"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - traefik_data:/letsencrypt
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /local-files:/files

  n8n:
    image: docker.n8n.io/n8nio/n8n
    restart: always
    ports:
      - "127.0.0.1:5678:5678"
    labels:
      - traefik.enable=true
      - traefik.http.routers.n8n.rule=Host(\`\${SUBDOMAIN}.\${DOMAIN_NAME}\`)
      - traefik.http.routers.n8n.tls=true
      - traefik.http.routers.n8n.entrypoints=web,websecure
      - traefik.http.routers.n8n.tls.certresolver=mytlschallenge
      - traefik.http.middlewares.n8n.headers.SSLRedirect=true
      - traefik.http.middlewares.n8n.headers.STSSeconds=315360000
      - traefik.http.middlewares.n8n.headers.browserXSSFilter=true
      - traefik.http.middlewares.n8n.headers.contentTypeNosniff=true
      - traefik.http.middlewares.n8n.headers.forceSTSHeader=true
      - traefik.http.middlewares.n8n.headers.SSLHost=\${DOMAIN_NAME}
      - traefik.http.middlewares.n8n.headers.STSIncludeSubdomains=true
      - traefik.http.middlewares.n8n.headers.STSPreload=true
      - traefik.http.routers.n8n.middlewares=n8n@docker
    environment:
      - N8N_HOST=\${SUBDOMAIN}.\${DOMAIN_NAME}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://\${SUBDOMAIN}.\${DOMAIN_NAME}/
      - GENERIC_TIMEZONE=\${GENERIC_TIMEZONE}
    volumes:
      - n8n_data:/home/node/.n8n
	  - /local-files:/files

volumes:
  traefik_data:
    external: true
  n8n_data:
    external: true
EOF

# Создание .env файла с запросом значений
echo -n "Введите DOMAIN_NAME (название вашего домена, например, example.com): "
read DOMAIN_NAME
echo -n "Введите SUBDOMAIN (поддомен, например, n8n): "
read SUBDOMAIN
echo -n "Введите GENERIC_TIMEZONE (часовой пояс, например, Europe/Berlin): "
read GENERIC_TIMEZONE
echo -n "Введите SSL_EMAIL (ваш адрес электронной почты для SSL-сертификата): "
read SSL_EMAIL

cat <<EOF | sudo tee .env > /dev/null
DOMAIN_NAME=\$DOMAIN_NAME
SUBDOMAIN=\$SUBDOMAIN
GENERIC_TIMEZONE=\$GENERIC_TIMEZONE
SSL_EMAIL=\$SSL_EMAIL
EOF

# Создание папки /local-files и установка разрешений
sudo mkdir -p /local-files
sudo chmod -R 777 /local-files

# Запуск Docker volumes
sudo docker volume create n8n_data
sudo docker volume create traefik_data

# Запуск docker-compose
sudo docker-compose up -d
