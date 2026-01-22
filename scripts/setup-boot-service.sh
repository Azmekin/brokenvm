#!/bin/bash

set -e

echo "🔧 Создание сервиса для автоматической настройки при загрузке..."

# Проверка root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Скрипт должен запускаться с правами root"
    exit 1
fi

# Переменные
SETUP_SERVICE_FILE="/etc/systemd/system/security-setup.service"
SETUP_SCRIPT="/usr/local/bin/security-setup-onboot.sh"

echo "📝 Создание скрипта настройки..."
cat > $SETUP_SCRIPT << 'EOF'
#!/bin/bash

# Скрипт автоматической настройки при загрузке
set -e

LOG_FILE="/var/log/security-setup.log"

echo "$(date): Starting security setup..." >> $LOG_FILE

# Переменные
GITLAB_URL="http://$(hostname -I | awk '{print $1}')"
DEFECTDOJO_URL="$GITLAB_URL:8080"

# Функция ожидания сервиса
wait_for_service() {
    local url=$1
    local service=$2
    local max_attempts=20
    local attempt=1
    
    echo "$(date): Waiting for $service..." >> $LOG_FILE
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s "$url" > /dev/null 2>&1; then
            echo "$(date): $service is ready" >> $LOG_FILE
            return 0
        fi
        sleep 10
        ((attempt++))
    done
    echo "$(date): ERROR: $service failed to start" >> $LOG_FILE
    return 1
}

# Настройка GitLab
setup_gitlab() {
    echo "$(date): Setting up GitLab..." >> $LOG_FILE
    
    wait_for_service "$GITLAB_URL" "GitLab" || return 1
    
    # Смена пароля root
    docker exec gitlab_web_1 gitlab-rails runner "
    user = User.find_by_username('root')
    user.password = 'NewSecurePassword123!'
    user.password_confirmation = 'NewSecurePassword123!'
    user.save!
    " >> $LOG_FILE 2>&1 && echo "$(date): GitLab password changed" >> $LOG_FILE
    
    # Отключение регистрации
    docker exec gitlab_web_1 gitlab-rails runner "
    ApplicationSetting.last.update!(signup_enabled: false)
    " >> $LOG_FILE 2>&1 && echo "$(date): GitLab registration disabled" >> $LOG_FILE
}

# Настройка DefectDojo
setup_defectdojo() {
    echo "$(date): Setting up DefectDojo..." >> $LOG_FILE
    
    wait_for_service "$DEFECTDOJO_URL" "DefectDojo" || return 1
    
    # Смена пароля администратора
    docker-compose -f /opt/defectdojo/docker-compose.yml exec -T uwsgi \
        python3 manage.py changepassword admin --password "NewSecurePassword123!" >> $LOG_FILE 2>&1 \
        && echo "$(date): DefectDojo password changed" >> $LOG_FILE
}

# Главная функция
main() {
    echo "$(date): Starting main setup..." >> $LOG_FILE
    
    # Даем время на запуск контейнеров
    sleep 60
    
    setup_gitlab
    setup_defectdojo
    
    echo "$(date): Setup completed successfully" >> $LOG_FILE
}

main "$@"
EOF

chmod +x $SETUP_SCRIPT

echo "🔧 Создание systemd сервиса..."
cat > $SETUP_SERVICE_FILE << EOF
[Unit]
Description=Security Stack Auto-Setup
After=security-stack.service
Requires=security-stack.service

[Service]
Type=oneshot
ExecStart=$SETUP_SCRIPT
RemainAfterExit=yes
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

echo "🎯 Настройка сервиса..."
systemctl daemon-reload
systemctl enable security-setup.service

echo ""
echo "✅ Сервис автоматической настройки создан!"
echo ""
echo "📋 Полная последовательность установки:"
echo "   1. sudo ./install-gitlab-docker.sh          # Установка GitLab"
echo "   2. sudo ./install-defectdojo-docker.sh      # Установка DefectDojo"
echo "   3. sudo ./create-gitlab-service.sh          # Сервис GitLab"
echo "   4. sudo ./create-defectdojo-service.sh      # Сервис DefectDojo"
echo "   5. sudo ./create-security-stack-service.sh  # Общий сервис"
echo "   6. sudo ./setup-boot-service.sh             # Автонастройка"
echo ""
echo "🔁 После этого при перезагрузке:"
echo "   - Автоматически запустятся контейнеры"
echo "   - Автоматически применятся настройки"
echo "   - Пароли будут изменены"
echo "   - Регистрация будет отключена"