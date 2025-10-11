#!/bin/bash

set -e

echo "🔧 Создание systemd сервиса для GitLab..."

# Проверка root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Скрипт должен запускаться с правами root"
    exit 1
fi

# Переменные
GITLAB_DIR="/opt/gitlab"
SERVICE_FILE="/etc/systemd/system/gitlab-docker.service"

# Проверяем, что GitLab установлен
if [ ! -f "$GITLAB_DIR/docker-compose.yml" ]; then
    echo "❌ GitLab не установлен. Сначала запустите install-gitlab-docker.sh"
    exit 1
fi

echo "📁 Найден GitLab в: $GITLAB_DIR"

echo "🔧 Создание systemd сервиса..."
cat > $SERVICE_FILE << EOF
[Unit]
Description=GitLab Docker Service
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${GITLAB_DIR}
ExecStartPre=-/usr/bin/docker-compose down
ExecStart=/usr/bin/docker-compose up -d
ExecStop=/usr/bin/docker-compose down
ExecReload=/usr/bin/docker-compose down && /usr/bin/docker-compose up -d
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

echo "🎯 Настройка сервиса..."
systemctl daemon-reload
systemctl enable gitlab-docker.service

echo "🔄 Перезапуск GitLab через systemd..."
systemctl stop gitlab-docker.service 2>/dev/null || true
systemctl start gitlab-docker.service

echo "⏳ Ожидание запуска GitLab..."
for i in {1..30}; do
    if curl -s "http://$(hostname -I | awk '{print $1}')" > /dev/null 2>&1; then
        break
    fi
    echo -n "."
    sleep 5
done

echo ""
echo "✅ Systemd сервис для GitLab создан!"
echo ""
echo "🛠️ Команды управления:"
echo "   sudo systemctl start gitlab-docker    # Запуск"
echo "   sudo systemctl stop gitlab-docker     # Остановка" 
echo "   sudo systemctl restart gitlab-docker  # Перезапуск"
echo "   sudo systemctl status gitlab-docker   # Статус"
echo "   journalctl -u gitlab-docker -f        # Логи"
echo ""
echo "🔁 Сервис будет автоматически запускаться при загрузке системы"