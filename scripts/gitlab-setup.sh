#!/bin/bash

set -e

echo "🚀 Установка GitLab CE в Docker..."

# Проверка root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Скрипт должен запускаться с правами root"
    exit 1
fi

# Переменные
GITLAB_URL="${1:-http://$(hostname -I | awk '{print $1}')}"
GITLAB_DIR="/opt/gitlab"
DOCKER_COMPOSE_FILE="$GITLAB_DIR/docker-compose.yml"
VULNERABLE_VERSION="16.5.6-ce.0"

echo "📦 Установка Docker..."
apt-get update
apt-get install -y curl docker.io docker-compose
systemctl enable docker
systemctl start docker

echo "📁 Создание директорий..."
mkdir -p $GITLAB_DIR/{data,logs,config}
cd $GITLAB_DIR

echo "🐳 Создание docker-compose.yml..."
cat > $DOCKER_COMPOSE_FILE << EOF
version: '3.6'
services:
  gitlab:
    image: "gitlab/gitlab-ce:${VULNERABLE_VERSION}"
    container_name: gitlab-vulnerable
    restart: unless-stopped
    hostname: 'gitlab-vuln.local'
    environment:
      GITLAB_OMNIBUS_CONFIG: |
        external_url '${GITLAB_URL}'
        gitlab_rails['initial_root_password'] = 'ChangeMe123!'
        gitlab_rails['gitlab_shell_ssh_port'] = 2222
        nginx['listen_port'] = 80
        nginx['listen_https'] = false
        
        # Уязвимая конфигурация почты
        gitlab_rails['smtp_enable'] = true
        gitlab_rails['smtp_address'] = "mailhog"
        gitlab_rails['smtp_port'] = 1025
        gitlab_rails['smtp_user_name'] = ""
        gitlab_rails['smtp_password'] = ""
        gitlab_rails['smtp_domain'] = "gitlab-vuln.local"
        gitlab_rails['smtp_authentication'] = "plain"
        gitlab_rails['smtp_enable_starttls_auto'] = false
        gitlab_rails['smtp_tls'] = false
        
        # Отключаем проверки безопасности для CTF
        gitlab_rails['password_authentication_enabled_for_web'] = true
        gitlab_rails['signup_enabled'] = true
        gitlab_rails['require_two_factor_authentication'] = false
    ports:
      - '8081:80'
      - '2223:22'
    volumes:
      - '${GITLAB_DIR}/config:/etc/gitlab'
      - '${GITLAB_DIR}/logs:/var/log/gitlab'
      - '${GITLAB_DIR}/data:/var/opt/gitlab'
    depends_on:
      - mailhog
    networks:
      - ctf-network

  mailhog:
    image: mailhog/mailhog:latest
    container_name: mailhog-ctf
    restart: unless-stopped
    ports:
      - '8025:8025'  # Web UI
      - '1025:1025'  # SMTP server
    networks:
      - ctf-network
    command: ["-storage=maildir", "-maildir-path=/tmp", "-smtp-bind-addr=0.0.0.0:1025"]

networks:
  ctf-network:
    driver: bridge
EOF

echo "🎯 Запуск GitLab..."
docker-compose up -d

echo "⏳ Ожидание запуска GitLab (это может занять 3-5 минут)..."
for i in {1..60}; do
    if docker-compose logs web 2>/dev/null | grep -q "gitlab Reconfigured"; then
        break
    fi
    echo -n "."
    sleep 5
done

echo ""
echo "✅ GitLab установлен в Docker!"
echo "🌐 URL: $GITLAB_URL"
echo "🔑 Логин: root"
echo "🔒 Пароль: ChangeMe123!"
echo ""
echo "🛠️ Команды управления:"
echo "   cd /opt/gitlab"
echo "   sudo docker-compose up -d     # Запуск"
echo "   sudo docker-compose down      # Остановка"
echo "   sudo docker-compose restart   # Перезапуск"
echo "   sudo docker-compose logs -f   # Логи"

# Создание скрипта управления
cat > /usr/local/bin/gitlab-docker-manage << EOF
#!/bin/bash
cd /opt/gitlab
case "\$1" in
    start) docker-compose up -d ;;
    stop) docker-compose down ;;
    restart) docker-compose restart ;;
    status) docker-compose ps ;;
    logs) docker-compose logs -f ;;
    update) 
        docker-compose down
        docker-compose pull
        docker-compose up -d
        ;;
    *) echo "Usage: gitlab-docker-manage {start|stop|restart|status|logs|update}" ;;
esac
EOF

chmod +x /usr/local/bin/gitlab-docker-manage