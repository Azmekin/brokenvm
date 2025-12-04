#!/bin/bash

set -e

echo "🎯 Создание CTF пользователя и репозитория с подсказкой..."

# Переменные
GITLAB_URL="http://$(hostname -I | awk '{print $1}')"
GITLAB_PORT="${GITLAB_PORT:-80}"
VICTIM_USERNAME="john_doe"
VICTIM_EMAIL="john.doe@gitlab.local"
VICTIM_PASSWORD="VictimPass123!"
HINT_REPO_NAME="company-secrets"
HINT_FILE="internal/employees.md"

# Функции
wait_for_gitlab() {
    echo -n "⏳ Ожидание GitLab..."
    until curl -s "${GITLAB_URL}:${GITLAB_PORT}" > /dev/null 2>&1; do
        echo -n "."
        sleep 5
    done
    echo " ✅"
}

# 1. Создание пользователя-жертвы
create_victim_user() {
    echo "👤 Создание пользователя-жертвы..."
    
    # Получаем root токен
    if docker ps | grep -q "gitlab"; then
        # Для Docker-установки
        ROOT_TOKEN=$(docker exec gitlab_web_1 gitlab-rails runner "
        token = User.find_by_username('root').personal_access_tokens.create(
            scopes: [:api, :sudo], 
            name: 'ctf-victim-setup',
            expires_at: Time.now + 7.days
        )
        puts token.token
        " 2>/dev/null)
    else
        # Для native-установки
        ROOT_TOKEN=$(gitlab-rails runner "
        token = User.find_by_username('root').personal_access_tokens.create(
            scopes: [:api, :sudo], 
            name: 'ctf-victim-setup',
            expires_at: Time.now + 7.days
        )
        puts token.token
        " 2>/dev/null)
    fi
    
    if [ -z "$ROOT_TOKEN" ]; then
        echo "❌ Не удалось получить root токен"
        return 1
    fi
    
    echo $ROOT_TOKEN > /tmp/gitlab_ctf_root_token.txt
    
    # Проверяем, существует ли пользователь
    USER_CHECK=$(curl -s "${GITLAB_URL}:${GITLAB_PORT}/api/v4/users?username=${VICTIM_USERNAME}" \
        -H "PRIVATE-TOKEN: $ROOT_TOKEN" | jq 'length')
    
    if [ "$USER_CHECK" -gt 0 ]; then
        echo "⚠️ Пользователь $VICTIM_USERNAME уже существует"
        return 0
    fi
    
    # Создаем пользователя
    USER_RESPONSE=$(curl -s -X POST "${GITLAB_URL}:${GITLAB_PORT}/api/v4/users" \
        -H "PRIVATE-TOKEN: $ROOT_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"email\": \"${VICTIM_EMAIL}\",
            \"username\": \"${VICTIM_USERNAME}\",
            \"name\": \"John Doe\",
            \"password\": \"${VICTIM_PASSWORD}\",
            \"skip_confirmation\": true,
            \"admin\": false,
            \"can_create_group\": false,
            \"projects_limit\": 10,
            \"external\": false,
            \"note\": \"Internal employee. Handle sensitive documents.\"
        }")
    
    USER_ID=$(echo $USER_RESPONSE | jq '.id // empty')
    
    if [ -n "$USER_ID" ]; then
        echo "✅ Пользователь создан:"
        echo "   👤 Username: $VICTIM_USERNAME"
        echo "   📧 Email: $VICTIM_EMAIL"
        echo "   🔑 Password: $VICTIM_PASSWORD"
        echo "   🆔 ID: $USER_ID"
        
        # Создаем персональный токен для пользователя
        create_user_token "$USER_ID"
        
        return 0
    else
        echo "❌ Ошибка создания пользователя:"
        echo "$USER_RESPONSE"
        return 1
    fi
}

# 2. Создание персонального токена для пользователя
create_user_token() {
    local user_id=$1
    
    echo "🔑 Создание персонального токена для пользователя..."
    
    USER_TOKEN=$(curl -s -X POST "${GITLAB_URL}:${GITLAB_PORT}/api/v4/users/$user_id/personal_access_tokens" \
        -H "PRIVATE-TOKEN: $ROOT_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "api-access-token",
            "scopes": ["api", "read_user", "read_repository", "write_repository"],
            "expires_at": "'$(date -d "+30 days" +%Y-%m-%d)'"
        }' | jq -r '.token // empty')
    
    if [ -n "$USER_TOKEN" ]; then
        echo "✅ Токен пользователя создан: ${USER_TOKEN:0:20}..."
        echo $USER_TOKEN > /tmp/gitlab_victim_token.txt
    else
        echo "⚠️ Не удалось создать токен пользователя"
    fi
}

# 3. Создание публичного репозитория с подсказкой
create_hint_repository() {
    echo "📦 Создание публичного репозитория с подсказкой..."
    
    local token=$(cat /tmp/gitlab_ctf_root_token.txt)
    
    # Создаем репозиторий от имени root
    REPO_RESPONSE=$(curl -s -X POST "${GITLAB_URL}:${GITLAB_PORT}/api/v4/projects" \
        -H "PRIVATE-TOKEN: $token" \
        -H "Content-Type: application/json" \
        -d "{
            \"name\": \"${HINT_REPO_NAME}\",
            \"visibility\": \"public\",
            \"description\": \"Internal company documentation and employee information\",
            \"initialize_with_readme\": false,
            \"auto_devops_enabled\": false,
            \"topics\": [\"internal\", \"documentation\", \"employees\"]
        }")
    
    REPO_ID=$(echo $REPO_RESPONSE | jq '.id // empty')
    
    if [ -z "$REPO_ID" ]; then
        echo "❌ Ошибка создания репозитория"
        echo "$REPO_RESPONSE"
        return 1
    fi
    
    echo "✅ Репозиторий создан (ID: $REPO_ID)"
    
    # Создаем локальный репозиторий и добавляем файлы
    local repo_dir="/tmp/${HINT_REPO_NAME}"
    rm -rf "$repo_dir"
    mkdir -p "$repo_dir"
    cd "$repo_dir"
    
    git init
    git config user.email "root@localhost"
    git config user.name "Administrator"
    
    # README с общей информацией
    cat > README.md << EOF
# Company Internal Documentation

## Описание
При онбординге для получение доступов к internal репозиториям обратитесь к 👤 Username: $VICTIM_USERNAME" 📧 Email: $VICTIM_EMAIL". Если Вам нужно сбросить пароль и у вас проблемы с получением письма на почту, также обратитесь к нему.
EOF
    
    git add .
    git commit -m "Initial commit: Company internal documentation"
    
    # Пушим в созданный репозиторий
    git push "http://root:${ROOT_PASSWORD}@${GITLAB_URL#http://}:${GITLAB_PORT}/root/${HINT_REPO_NAME}.git" main --force 2>/dev/null || \
    git push "http://root:${ROOT_PASSWORD}@${GITLAB_URL#http://}/root/${HINT_REPO_NAME}.git" main --force
    
    echo "✅ Репозиторий заполнен данными"
}






# Главная функция
main() {
    echo "🎯 Настройка CTF пользователя и репозиториев..."
    
    # Получаем пароль root
    echo "🔐 Введите пароль root пользователя GitLab:"
    read -s ROOT_PASSWORD
    
    wait_for_gitlab
    create_victim_user
    create_hint_repository
    create_secret_repository
    create_hint_issue
    
    echo ""
    echo "✅ CTF-задание настроено!"
    echo ""
    echo "📊 Информация для CTF:"
    echo "   👤 Пользователь-жертва:"
    echo "      Username: $VICTIM_USERNAME"
    echo "      Email: $VICTIM_EMAIL"
    echo "      Password: $VICTIM_PASSWORD"
    echo ""
    echo "   📁 Репозитории:"
    echo "      Публичный: ${GITLAB_URL}:${GITLAB_PORT}/root/${HINT_REPO_NAME}"
    echo ""
    echo "   🔍 Подсказки:"
    echo "      1. Проверьте файл ${HINT_FILE} в публичном репозитории"
    echo "      2. Посмотрите Issue о странном поведении сброса пароля"
    echo "      3. John Doe работает с инфраструктурой GitLab"
    echo ""
    echo "   🎯 Цель:"
    echo "      Получить доступ к аккаунту John Doe и найти секрет в его приватном репозитории"
}

# Запуск
main