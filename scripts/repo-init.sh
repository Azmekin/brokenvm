#!/bin/bash

set -e

echo "🚀 Запуск настройки с легковесной джобой и зашитым секретом..."

# Переменные
GITLAB_URL="http://127.0.0.1:8081"
DEFECTDOJO_URL="http://127.0.0.1:8080"
GITLAB_ROOT_PASSWORD="NewSecurePassword123!"
DEFECTDOJO_ADMIN_PASSWORD="NewSecurePassword123!"
PROJECT_NAME="security-demo"
REPO_NAME="vulnerable-app"

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

# 1. Смена пароля в GitLab
change_gitlab_password() {
    echo "🔐 Смена пароля root в GitLab..."
    docker exec gitlab gitlab-rails runner "user = User.find_by_username('root'); user.password = '$GITLAB_ROOT_PASSWORD'; user.password_confirmation = '$GITLAB_ROOT_PASSWORD'; user.save!"
}

# 2. Отключение регистрации в GitLab
disable_gitlab_registration() {
    echo "🔒 Отключение регистрации в GitLab..."
    docker exec gitlab gitlab-rails runner "ApplicationSetting.last.update!(signup_enabled: false)"
}

# 3. Создание проекта в GitLab
create_gitlab_project() {
    echo "📦 Создание проекта в GitLab..."
    
    # Получаем токен аутентификации
    GITLAB_TOKEN=$(docker exec gitlab-vulnerable gitlab-rails runner "
token = User.find_by_username('john_doe').personal_access_tokens.create(
scopes: [:api, :read_repository, :write_repository], 
name: 'john_doe',
expires_at: Time.now + 7.days)
puts token.token" 2>/dev/null)
    echo "$GITLAB_TOKEN"
    
    
    # Создаем проект
    curl  -X POST "$GITLAB_URL/api/v4/projects" \
        -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"name\": \"$PROJECT_NAME\",
            \"visibility\": \"private\",
            \"initialize_with_readme\": \"false\"
        }"
    echo $GITLAB_TOKEN > /tmp/gitlab_token.txt
}

# 4. Смена пароля и создание readonly токена в DefectDojo
setup_defectdojo_readonly() {
    echo "🔧 Настройка DefectDojo с readonly токеном..."
    
    # Ждем запуска DefectDojo
    wait_for_service "$DEFECTDOJO_URL" "DefectDojo"
    
    # Смена пароля администратора
    docker exec defectdojo_uwsgi_1  \
        python3 manage.py shell -c "
import django
from django.contrib.auth.models import User
u = User.objects.get(username='admin')
u.set_password('$DEFECTDOJO_ADMIN_PASSWORD')
u.save()
print('saved new password')"    
    # Создаем пользователя только для чтения
    docker-compose -f /opt/defectdojo/docker-compose.yml exec -T uwsgi python3 manage.py shell << 'EOF'
from dojo.models import User
from django.contrib.auth.models import Permission
from rest_framework.authtoken.models import Token

# Создаем пользователя только для чтения
user, created = User.objects.get_or_create(
    username='readonly-viewer',
    email='readonly@localhost',
    defaults={
        'is_active': True,
        'is_superuser': False,
        'is_staff': False
    }
)
user.set_password('readonly_pass_123')
user.save()

# Даем ТОЛЬКО права на просмотр
read_permissions = [
    'view_product',
    'view_engagement', 
    'view_test',
    'view_finding',
    'view_scan',
]

for perm_codename in read_permissions:
    try:
        permission = Permission.objects.get(codename=perm_codename)
        user.user_permissions.add(permission)
    except:
        pass

# Создаем API token
token, created = Token.objects.get_or_create(user=user)
print(token.key)
EOF
}

# 5. Отключение регистрации в DefectDojo
disable_defectdojo_registration() {
    echo "🔒 Отключение регистрации в DefectDojo..."
    
    docker-compose -f /opt/defectdojo/docker-compose.yml exec -T uswgi \
        python3 manage.py shell -c "
from dojo.models import System_Settings
try:
	settings = System_Settings.objects.get()
	settings.enable_signup = False
	settings.save()
	print('reg off1')
except:
	System_Settings.objects.create(enable_signup=False)
print('reg off2')"
}

# 6. Создание легковесного .gitlab-ci.yml с зашитым секретом
create_lightweight_ci() {
    echo "⚙️ Создание легковесного CI пайплайна..."
    
    local repo_dir="/tmp/$REPO_NAME"
    cd "$repo_dir"
    
    # Получаем readonly токен
    READONLY_TOKEN=$(docker-compose -f /opt/defectdojo/docker-compose.yml exec -T uwsgi python3 manage.py shell << 'EOF'
from rest_framework.authtoken.models import Token
try:
    token = Token.objects.get(user__username='readonly-viewer')
    print(token.key)
except:
    print("TOKEN_NOT_FOUND")
EOF
    )
    
    # Создаем легковесный .gitlab-ci.yml
    cat > .gitlab-ci.yml << 'EOF'
# Lightweight Security Scan Pipeline
# This job simulates security scanning without heavy processing

stages:
  - security

lightweight_scan:
  stage: security
  image: alpine:latest  # Минимальный образ
  before_script:
    - echo "🚀 Starting lightweight security scan..."
    - apk add --no-cache curl 2>/dev/null || echo "curl already available"
  
  script:
    # Легковесная "проверка" без реального сканирования
    - echo "📊 Scanning code structure..."
    - find . -name "*.js" -type f | head -5 | xargs -I {} echo "Found: {}"
    - echo "🔍 Checking for common patterns..."
    - echo "Total JavaScript files: \$(find . -name '*.js' | wc -l)"
    
    # Симуляция создания отчета (без реального сканирования)
    - cat > mock-scan-report.json << 'MOCKREPORT'
{
  "results": [
    {
      "check_id": "mock-scan-001",
      "path": "src/app.js",
      "start": { "line": 1 },
      "end": { "line": 10 },
      "extra": {
        "message": "Mock security finding for demonstration",
        "severity": "INFO",
        "metadata": {
          "description": "This is a simulated finding",
          "confidence": "LOW"
        }
      }
    }
  ],
  "errors": [],
  "stats": {
    "files_processed": \$(find . -name '*.js' | wc -l),
    "scan_time": 0.5,
    "findings_count": 1
  }
}
MOCKREPORT

    # Попытка отправки в DefectDojo (будет fail из-за readonly токена)
    - |
      echo "📤 Attempting to send report to DefectDojo..."
      RESPONSE=\$(curl -s -w "HTTP_STATUS:%{http_code}" -X POST "\$DEFECTDOJO_URL/api/v2/import-scan/" \\
        -H "Authorization: Token $READONLY_TOKEN" \\
        -H "Content-Type: multipart/form-data" \\
        -F "engagement=1" \\
        -F "verified=true" \\
        -F "active=true" \\
        -F "minimum_severity=Info" \\
        -F "scan_type=Semgrep JSON Report" \\
        -F "file=@mock-scan-report.json" \\
        -F "product_name=GitLabDemo" \\
        -F "engagement_name=Lightweight_Scan" 2>&1)
      
      HTTP_STATUS=\$(echo "\$RESPONSE" | grep -o 'HTTP_STATUS:[0-9]*' | cut -d: -f2)
      
      if [ "\$HTTP_STATUS" = "403" ] || [ "\$HTTP_STATUS" = "401" ]; then
        echo "✅ Expected: Report upload blocked (readonly token working correctly)"
        echo "🔒 Security: Token has correct readonly permissions"
      else
        echo "⚠️ Unexpected response: HTTP \$HTTP_STATUS"
        echo "Response: \$RESPONSE"
      fi
    
    # Всегда успешное завершение
    - echo "🎉 Lightweight scan completed successfully"
    - echo "📈 Summary: Processed \$(find . -name '*.js' | wc -l) files, found 1 demo finding"
  
  after_script:
    - echo "🏁 Scan job finished"
  
  rules:
    - if: \$CI_COMMIT_BRANCH == "main"
      when: always  # Всегда запускается но не нагружает систему
  
  tags: []
  
  # Ограничения ресурсов
  variables:
    GIT_STRATEGY: clone
    GIT_DEPTH: 1
  
  # Артефакты для демонстрации
  artifacts:
    paths:
      - mock-scan-report.json
    expire_in: 1 hour
    when: always

# Демо джоба которая показывает информацию о токене
token_info:
  stage: security
  image: alpine:latest
  script:
    - |
      echo "🔐 Token Information:"
      echo "DefectDojo URL: \$DEFECTDOJO_URL"
      echo "Token (masked): ****\$(echo "$READONLY_TOKEN" | tail -c 8)"
      echo "Token Length: \${#READONLY_TOKEN}"
      echo ""
      echo "🔒 This token has READONLY permissions:"
      echo "   - Can view findings: ✅"
      echo "   - Can import scans: ❌ (blocked)"
      echo "   - Can modify data: ❌ (blocked)"
  rules:
    - if: \$CI_COMMIT_BRANCH == "main"
      when: on_success
  tags: []
EOF
    cat .gitlab-ci.yml
    git status
    git add .gitlab-ci.yml
    git status
    git add "$repo_dir"/.gitlab-ci.yml
    git status
    git commit -m "Add utility function"
    echo "endpipe"
}

# 7. Создание репозитория с CI пайплайном
create_repo_with_ci() {
    echo "📁 Создание репозитория с CI пайплайном..."
    
    local token=$(cat /tmp/gitlab_token.txt)
    local repo_dir="/tmp/$REPO_NAME"
    
    # Создаем локальный репозиторий
    rm -rf "$repo_dir"
    mkdir -p "$repo_dir"
    cd "$repo_dir"
    
    git init
    git config user.email "john_doe@localhost"
    git config user.name "John Doe"
    git config commit.gpgsign false
    
    # Начальный коммит
    echo "# Security Demo Project with CI" > README.md
    cat >> README.md << 'EOF'

## CI Pipeline

This project includes a lightweight security scan pipeline that:
- Uses minimal Alpine Linux image
- Performs mock scanning without heavy processing  
- Attempts to send reports to DefectDojo (will fail due to readonly token)
- Demonstrates CI/CD integration without system load

### Token Security
The DefectDojo token embedded in the pipeline has READONLY permissions only.
EOF

    git add README.md
    git commit -m "Initial commit with CI documentation"

    # Создаем базовую структуру
    mkdir -p src/utils
    cat > src/app.js << 'EOF'
// Main application file
function processData(input) {
    console.log("Processing:", input);
    return input.toUpperCase();
}

module.exports = { processData };
EOF

    git add src/app.js
    git commit -m "Add main application file"
    for i in {1..50}; do
        echo "// Utility function" > "src/utils/util_$i.js"
        echo "// Mock functionality" >> "src/utils/util_$i.js"
        git add .
        git commit -m "Add utility function"
    done
    # Добавляем легковесный CI пайплайн
    create_lightweight_ci
    rm -f .gitlab-ci.yml
    # Еще несколько коммитов для демонстрации
    for i in {1..50}; do
        echo "// Utility function" > "src/utils/util2_$i.js"
        echo "// Mock functionality" >> "src/utils/util2_$i.js"
        git add .
        git commit -m "Add utility function"
    done

    # Пушим в GitLab
    echo "📤 Пуш репозитория в GitLab..."
    #PROJECT_ID=$(curl -s "$GITLAB_URL/api/v4/projects?search=$PROJECT_NAME" -H "PRIVATE-TOKEN: $token" | jq '.[0].id')
    git push --set-upstream "http://john_doe:$GITLAB_TOKEN@${GITLAB_URL#http://}/john_doe/$PROJECT_NAME.git" master --force
}

# 8. Очистка
cleanup() {
    echo "🧹 Очистка временных файлов..."
    rm -f /tmp/gitlab_token.txt
    history -c
}

# Главная функция
main() {
    echo "🎯 Запуск настройки с легковесным CI..."
    
    # Ожидаем запуск сервисов
    wait_for_service "$GITLAB_URL" "GitLab"
    wait_for_service "$DEFECTDOJO_URL" "DefectDojo"
    
    # Выполняем настройку
    #change_gitlab_password
    #disable_gitlab_registration
    create_gitlab_project
    setup_defectdojo_readonly
    echo "Start dd disable reg"
#    disable_defectdojo_registration
    echo "Start  ci"
    create_repo_with_ci
    cleanup
    
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
    echo "🔧 Создан проект: $PROJECT_NAME"
    echo "⚙️  Настроен легковесный CI пайплайн:"
    echo "    - Использует alpine image"
    echo "    - Не нагружает систему"
    echo "    - Readonly токен зашит в .gitlab-ci.yml"
    echo "    - Отправка отчетов будет fail (ожидаемо)"
    echo ""
    echo "🚀 CI пайплайн запустится автоматически при пуше"
}

main "$@"
