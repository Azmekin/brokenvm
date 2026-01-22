#!/bin/bash

set -e

echo "🎯 Настройка среды безопасности в Docker..."

# Переменные
GITLAB_URL="http://$(hostname -I | awk '{print $1}')"
DEFECTDOJO_URL="$GITLAB_URL:8080"
PROJECT_NAME="security-demo"
GITLAB_ROOT_PASSWORD="NewSecurePassword123!"
DEFECTDOJO_ADMIN_PASSWORD="NewSecurePassword123!"

# Функции
wait_for_service() {
    local url=$1
    local service=$2
    echo -n "⏳ Ожидание запуска $service..."
    until curl -s "$url" > /dev/null 2>&1; do
        echo -n "."
        sleep 5
    done
    echo " ✅"
}

# 1. Настройка GitLab
setup_gitlab() {
    echo "🔧 Настройка GitLab..."
    
    # Смена пароля root
    docker exec gitlab_web_1 gitlab-rails runner "
    user = User.find_by_username('root')
    user.password = '${GITLAB_ROOT_PASSWORD}'
    user.password_confirmation = '${GITLAB_ROOT_PASSWORD}'
    user.save!
    "
    
    # Отключение регистрации
    docker exec gitlab_web_1 gitlab-rails runner "
    ApplicationSetting.last.update!(signup_enabled: false)
    "
    
    # Создание токена для API
    GITLAB_TOKEN=$(docker exec gitlab_web_1 gitlab-rails runner "
    puts User.find_by_username('root').personal_access_tokens.create(
        scopes: [:api, :read_repository, :write_repository], 
        name: 'setup-token'
    ).token
    ")
    
    echo $GITLAB_TOKEN > /tmp/gitlab_token.txt
    
    # Создание проекта
    curl -s -X POST "$GITLAB_URL/api/v4/projects" \
        -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"name\": \"$PROJECT_NAME\",
            \"visibility\": \"public\",
            \"initialize_with_readme\": \"true\"
        }" > /dev/null
    
    echo "✅ GitLab настроен"
}

# 2. Настройка DefectDojo
setup_defectdojo() {
    echo "🔧 Настройка DefectDojo..."
    
    # Смена пароля администратора
    docker-compose -f /opt/defectdojo/docker-compose.yml exec -T uwsgi \
        python3 manage.py changepassword admin --password "$DEFECTDOJO_ADMIN_PASSWORD"
    
    
    # Отключение регистрации
    docker-compose -f /opt/defectdojo/docker-compose.yml exec -T db \
        mysql -u defectdojo -pdefectdojo defectdojo -e \
        "UPDATE dojo_system_settings SET enable_signup = 0 WHERE id = 1;"
    
    echo "✅ DefectDojo настроен"
}

# Главная функция
main() {
    echo "🔍 Проверка запущенных сервисов..."
    
    # Ожидаем запуск GitLab
    wait_for_service "$GITLAB_URL" "GitLab"
    
    # Ожидаем запуск DefectDojo  
    wait_for_service "$DEFECTDOJO_URL" "DefectDojo"
    
    # Настраиваем сервисы
    setup_gitlab
    setup_defectdojo
    
    echo ""
    echo "✅ Настройка завершена!"
    echo ""
    echo "📊 Информация для доступа:"
    echo "   GitLab: $GITLAB_URL"
    echo "   Логин: root"
    echo "   Пароль: $GITLAB_ROOT_PASSWORD"
    echo ""
    echo "   DefectDojo: $DEFECTDOJO_URL"
    echo "   Логин: admin" 
    echo "   Пароль: $DEFECTDOJO_ADMIN_PASSWORD"
    echo ""
    echo "🛠️ Управление:"
    echo "   GitLab: gitlab-docker-manage {start|stop|restart|status|logs}"
    echo "   DefectDojo: defectdojo-docker-manage {start|stop|restart|status|logs}"
}

main "$@"