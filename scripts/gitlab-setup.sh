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
  web:
    image: 'gitlab/gitlab-ce:latest'
    restart: always
    hostname: 'gitlab.example.com'
    environment:
      GITLAB_OMNIBUS_CONFIG: |
        external_url '${GITLAB_URL}'
        gitlab_rails['initial_root_password'] = 'ChangeMe123!'
        gitlab_rails['gitlab_shell_ssh_port'] = 2222
        nginx['listen_port'] = 80
        nginx['listen_https'] = false
    ports:
      - '80:80'
      - '2222:22'
    volumes:
      - './config:/etc/gitlab'
      - './logs:/var/log/gitlab'
      - './data:/var/opt/gitlab'
    shm_size: '256m'
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