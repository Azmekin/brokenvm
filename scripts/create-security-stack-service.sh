#!/bin/bash

set -e

echo "🔧 Создание общего systemd сервиса для security stack..."

# Проверка root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Скрипт должен запускаться с правами root"
    exit 1
fi

# Переменные
STACK_SERVICE_FILE="/etc/systemd/system/security-stack.service"

# Проверяем, что оба сервиса установлены
if [ ! -f "/opt/gitlab/docker-compose.yml" ]; then
    echo "❌ GitLab не установлен. Сначала запустите install-gitlab-docker.sh"
    exit 1
fi

if [ ! -f "/opt/defectdojo/docker-compose.yml" ]; then
    echo "❌ DefectDojo не установлен. Сначала запустите install-defectdojo-docker.sh"
    exit 1
fi

echo "🔧 Создание общего systemd сервиса..."
cat > $STACK_SERVICE_FILE << EOF
[Unit]
Description=Security Stack (GitLab + DefectDojo)
Requires=docker.service
After=docker.service network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=-/usr/bin/docker-compose -f /opt/gitlab/docker-compose.yml down
ExecStartPre=-/usr/bin/docker-compose -f /opt/defectdojo/docker-compose.yml down
ExecStart=/usr/bin/docker-compose -f /opt/gitlab/docker-compose.yml up -d && /usr/bin/docker-compose -f /opt/defectdojo/docker-compose.yml up -d
ExecStop=/usr/bin/docker-compose -f /opt/gitlab/docker-compose.yml down && /usr/bin/docker-compose -f /opt/defectdojo/docker-compose.yml down
ExecReload=/usr/bin/docker-compose -f /opt/gitlab/docker-compose.yml down && /usr/bin/docker-compose -f /opt/defectdojo/docker-compose.yml down && /usr/bin/docker-compose -f /opt/gitlab/docker-compose.yml up -d && /usr/bin/docker-compose -f /opt/defectdojo/docker-compose.yml up -d
TimeoutStartSec=600

[Install]
WantedBy=multi-user.target
EOF

echo "🎯 Настройка сервиса..."
systemctl daemon-reload
systemctl enable security-stack.service

echo "🔄 Перезапуск стека через systemd..."
systemctl stop security-stack.service 2>/dev/null || true
systemctl start security-stack.service

echo "⏳ Ожидание запуска стека..."
sleep 30

echo ""
echo "✅ Общий systemd сервис для security stack создан!"
echo ""
echo "🛠️ Команды управления:"
echo "   sudo systemctl start security-stack       # Весь стек"
echo "   sudo systemctl stop security-stack        # Остановить стек"
echo "   sudo systemctl restart security-stack     # Перезапустить стек"
echo "   sudo systemctl status security-stack      # Статус"
echo "   journalctl -u security-stack -f           # Логи"
echo ""
echo "🔁 Весь стек будет автоматически запускаться при загрузке системы"