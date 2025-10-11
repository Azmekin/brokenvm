#!/bin/bash

set -e

echo "🔧 Создание systemd сервиса для DefectDojo..."

# Проверка root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Скрипт должен запускаться с правами root"
    exit 1
fi

# Переменные
DD_DIR="/opt/defectdojo"
SERVICE_FILE="/etc/systemd/system/defectdojo-docker.service"

# Проверяем, что DefectDojo установлен
if [ ! -f "$DD_DIR/docker-compose.yml" ]; then
    echo "❌ DefectDojo не установлен. Сначала запустите install-defectdojo-docker.sh"
    exit 1
fi

echo "📁 Найден DefectDojo в: $DD_DIR"

echo "🔧 Создание systemd сервиса..."
cat > $SERVICE_FILE << EOF
[Unit]
Description=DefectDojo Docker Service
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${DD_DIR}
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
systemctl enable defectdojo-docker.service

echo "🔄 Перезапуск DefectDojo через systemd..."
systemctl stop defectdojo-docker.service 2>/dev/null || true
systemctl start defectdojo-docker.service

echo "⏳ Ожидание запуска DefectDojo..."
for i in {1..30}; do
    if curl -s "http://$(hostname -I | awk '{print $1}'):8080" > /dev/null 2>&1; then
        break
    fi
    echo -n "."
    sleep 5
done

echo ""
echo "✅ Systemd сервис для DefectDojo создан!"
echo ""
echo "🛠️ Команды управления:"
echo "   sudo systemctl start defectdojo-docker    # Запуск"
echo "   sudo systemctl stop defectdojo-docker     # Остановка"
echo "   sudo systemctl restart defectdojo-docker  # Перезапуск"
echo "   sudo systemctl status defectdojo-docker   # Статус"
echo "   journalctl -u defectdojo-docker -f        # Логи"
echo ""
echo "🔁 Сервис будет автоматически запускаться при загрузке системы"