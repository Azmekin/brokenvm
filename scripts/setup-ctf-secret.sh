#!/bin/bash

set -e

echo "🎯 Настройка CTF секретов в DefectDojo..."

# Переменные
DEFECTDOJO_URL="http://$(hostname -I | awk '{print $1}'):8080"
PROJECT_NAME="ctf-security-project"
CTF_SECRET_FILE="/opt/ctf/secret.txt"

# Переменная для ручной установки флага
CTF_FLAG="CTF_FLAG:-CTF{Default_Secret_Flag}"

# Функции
wait_for_dd() {
    echo -n "⏳ Ожидание запуска DefectDojo..."
    until curl -s "$DEFECTDOJO_URL" > /dev/null 2>&1; do
        echo -n "."
        sleep 5
    done
    echo " ✅"
}

# 1. Создание CTF секрета в DefectDojo
create_ctf_secret_in_dd() {
    echo "🔐 Создание CTF секрета в DefectDojo..."
    echo "📝 Используется флаг: $CTF_FLAG"
    
    local result=$(docker-compose -f /opt/defectdojo/docker-compose.yml exec -T uwsgi python3 manage.py shell << EOF
import os
from dojo.models import Product, Engagement, Test, Finding
from django.contrib.auth.models import User
from django.utils import timezone

try:
    # Создаем или получаем продукт
    product, created = Product.objects.get_or_create(
        name="$PROJECT_NAME",
        defaults={
            'description': "CTF Security Project - Find the hidden secrets!",
            'prod_type': 1  # Research and Development
        }
    )
    
    if created:
        print("PRODUCT_CREATED:$PROJECT_NAME")
    else:
        print("PRODUCT_EXISTS:$PROJECT_NAME")
    
    # Создаем engagement
    engagement, created = Engagement.objects.get_or_create(
        name="CTF_Challenge_Engagement",
        product=product,
        defaults={
            'target_start': timezone.now(),
            'target_end': timezone.now().replace(year=2025)
        }
    )
    
    # Создаем тест
    test, created = Test.objects.get_or_create(
        engagement=engagement,
        test_type=1,  # Other
        defaults={
            'target_start': timezone.now(),
            'target_end': timezone.now().replace(year=2025),
            'percent_complete': 100
        }
    )
    
    # Создаем finding с CTF секретом
    finding, created = Finding.objects.get_or_create(
        title="[CTF] Hidden Secret Flag",
        test=test,
        defaults={
            'severity': "Info",
            'description': """# CTF Challenge: Find the Hidden Secret Flag\n\n**Flag:** $CTF_FLAG\n\n## Challenge Description:\nThis is a Capture The Flag challenge. The secret flag is hidden in this finding.\n\n## Rules:\n- Do not share the flag with other participants\n- Document how you found it\n- Have fun!""",
            'mitigation': "This is an intentional CTF challenge finding.",
            'impact': "No real impact - educational CTF challenge",
            'numerical_severity': "S4",
            'active': True,
            'verified': True
        }
    )
    
    if created:
        print("FINDING_CREATED:CTF_Secret_Flag")
    else:
        # Обновляем существующий finding
        finding.description = """# CTF Challenge: Find the Hidden Secret Flag\n\n**Flag:** $CTF_FLAG\n\n## Challenge Description:\nThis is a Capture The Flag challenge. The secret flag is hidden in this finding.\n\n## Rules:\n- Do not share the flag with other participants\n- Document how you found it\n- Have fun!"""
        finding.save()
        print("FINDING_UPDATED:CTF_Secret_Flag")
    
    print("CTF_FLAG:$CTF_FLAG")
    print("SUCCESS")
    
except Exception as e:
    print("ERROR:" + str(e))
EOF
)

    # Парсим результат
    if echo "$result" | grep -q "SUCCESS"; then
        echo "✅ CTF секрет создан в DefectDojo"
        local flag=$(echo "$result" | grep "CTF_FLAG:" | cut -d: -f2)
        echo "🔑 CTF Flag: $flag"
        return 0
    else
        echo "❌ Ошибка при создании CTF секрета:"
        echo "$result"
        return 1
    fi
}



# Главная функция
main() {
    echo "🎯 Запуск настройки CTF в DefectDojo..."
    echo "🔧 Используемый флаг: $CTF_FLAG"
    
    wait_for_dd
    create_ctf_secret_in_dd
    
    if [ "$1" = "with-service" ]; then
        create_rotation_service
    fi
    
    echo ""
    echo "✅ Настройка CTF завершена!"
    echo ""
    echo "📊 Информация:"
    echo "   DefectDojo: $DEFECTDOJO_URL"
    echo "   Проект: $PROJECT_NAME" 
    echo "   CTF Flag: $CTF_FLAG"
    echo "   Файл секрета: $CTF_SECRET_FILE"
    echo ""
    echo "🛠️ Команды управления:"
    echo "   change-ctf-secret                    # Сменить секрет вручную"
    echo "   CTF_FLAG='CTF{My_New_Flag}' ./setup-dd-ctf.sh  # Установить свой флаг"
    echo "   sudo systemctl start ctf-secret-rotation.service  # Запустить ротацию"
    echo ""
    echo "💡 Пример использования с своим флагом:"
    echo "   CTF_FLAG='CTF{My_Custom_Secret_123}' ./setup-dd-ctf.sh"
}

# Обработка аргументов
case "${1:-}" in
    "rotate")
        /usr/local/bin/change-ctf-secret
        ;;
    "with-service")
        main "with-service"
        ;;
    *)
        main "$1"
        ;;
esac