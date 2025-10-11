#!/bin/bash

set -e

echo "🔧 Управление CTF секретами..."

# Переменные
DEFECTDOJO_URL="http://$(hostname -I | awk '{print $1}'):8080"
PROJECT_NAME="ctf-security-project"

case "${1:-}" in
    "status")
        echo "📊 Статус CTF секретов:"
        echo ""
        echo "DefectDojo: $DEFECTDOJO_URL"
        echo "Проект: $PROJECT_NAME"
        echo ""
        
        
        # Показываем текущий флаг из DefectDojo
        echo ""
        echo "🔍 Текущий флаг в DefectDojo:"
        docker-compose -f /opt/defectdojo/docker-compose.yml exec -T uwsgi python3 manage.py shell << EOF 2>/dev/null | grep "Flag:" | head -1
from dojo.models import Finding, Product
try:
    product = Product.objects.get(name="$PROJECT_NAME")
    finding = Finding.objects.get(title="[CTF] Hidden Secret Flag", test__engagement__product=product)
    lines = finding.description.split('\\n')
    for line in lines:
        if 'Flag:' in line:
            print(line.strip())
            break
except:
    print("Не удалось получить флаг из DefectDojo")
EOF
        ;;
        
    "rotate")
        echo "🔄 Смена CTF секрета..."
        /usr/local/bin/change-ctf-secret
        ;;
        
    "set")
        echo "🎯 Установка CTF секрета..."
        if [ -z "$2" ]; then
            echo "❌ Укажите флаг: $0 set 'CTF{Your_Flag}'"
            exit 1
        fi
        
        NEW_FLAG="$2"
        echo "📝 Устанавливаю флаг: $NEW_FLAG"
        
        # Устанавливаем переменную и запускаем настройку
        CTF_FLAG="$NEW_FLAG" ./setup-dd-ctf.sh
        ;;
        
    "list-findings")
        echo "📋 Список CTF находок:"
        
        docker-compose -f /opt/defectdojo/docker-compose.yml exec -T uwsgi python3 manage.py shell << EOF
from dojo.models import Finding, Product

try:
    product = Product.objects.get(name="$PROJECT_NAME")
    findings = Finding.objects.filter(test__engagement__product=product)
    
    print("Найдено CTF находок: {}".format(findings.count()))
    print("")
    
    for finding in findings:
        print("🔍 {} (Severity: {})".format(finding.title, finding.severity))
        if "[CTF]" in finding.title:
            print("   📝 CTF Challenge")
        print("")
        
except Exception as e:
    print("Ошибка: " + str(e))
EOF
        ;;
        
    "init")
        echo "🎯 Инициализация CTF с ручным вводом флага..."
        echo "📝 Введите CTF флаг (формат: CTF{...}):"
        read -r MANUAL_FLAG
        
        if [ -z "$MANUAL_FLAG" ]; then
            echo "❌ Флаг не может быть пустым"
            exit 1
        fi
        
        CTF_FLAG="$MANUAL_FLAG" ./setup-dd-ctf.sh "${2:-}"
        ;;
        
    *)
        echo "Usage: $0 {status|rotate|set|init|list-findings} [flag]"
        echo ""
        echo "Примеры:"
        echo "  $0 status                          # Показать статус"
        echo "  $0 rotate                          # Сменить секрет (интерактивно)"
        echo "  $0 set 'CTF{My_Custom_Flag}'       # Установить конкретный флаг"
        echo "  $0 init                            # Инициализация с ручным вводом"
        echo "  $0 list-findings                   # Показать CTF находки"
        echo ""
        echo "💡 Альтернативный способ:"
        echo "  CTF_FLAG='CTF{Your_Flag}' ./setup-dd-ctf.sh"
        exit 1
        ;;
esac