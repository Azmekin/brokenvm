#!/bin/bash

set -e

echo "🌐 Смена FQDN системы..."

# Проверка root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Скрипт должен запускаться с правами root"
    exit 1
fi

# Проверка аргументов
if [ $# -eq 0 ]; then
    echo "📝 Использование: $0 <новый_fqdn>"
    echo ""
    echo "Пример:"
    echo "  $0 gitlab.company.com"
    echo "  $0 defectdojo.local.lan"
    echo ""
    exit 1
fi

OLD_FQDN=$(hostname -f)
NEW_FQDN="$1"

echo "🔧 Текущий FQDN: $OLD_FQDN"
echo "🎯 Новый FQDN: $NEW_FQDN"
echo ""

# Подтверждение
read -p "⚠️  Вы уверены, что хотите сменить FQDN? (y/N): " confirm
case "$confirm" in
    [yY]|[yY][eE][sS])
        echo "🔄 Начинаю смену FQDN..."
        ;;
    *)
        echo "❌ Отменено"
        exit 0
        ;;
esac

# 1. Обновление /etc/hosts
echo "📝 Обновление /etc/hosts..."
cp /etc/hosts /etc/hosts.backup.$(date +%Y%m%d_%H%M%S)

sed -i "s/${OLD_FQDN}/${NEW_FQDN}/g" /etc/hosts
sed -i "s/$(echo $OLD_FQDN | cut -d'.' -f1)/$(echo $NEW_FQDN | cut -d'.' -f1)/g" /etc/hosts

echo "✅ /etc/hosts обновлен (создан бэкап)"

# 2. Обновление hostname
echo "📝 Обновление hostname..."
hostnamectl set-hostname "$NEW_FQDN"



# 4. Обновление Docker Compose файлов
echo "🔧 Обновление Docker конфигураций..."

# GitLab в Docker
if [ -f "/opt/gitlab/docker-compose.yml" ]; then
    echo "📝 Обновление GitLab Docker Compose..."
    sed -i "s/hostname: .*/hostname: '${NEW_FQDN}'/g" /opt/gitlab/docker-compose.yml
    sed -i "s/external_url .*/external_url 'http:\/\/${NEW_FQDN}'/g" /opt/gitlab/docker-compose.yml
    echo "✅ GitLab Docker Compose обновлен"
fi

# DefectDojo
if [ -f "/opt/defectdojo/docker-compose.yml" ]; then
    echo "📝 Обновление DefectDojo конфигурации..."
    # Обновляем ссылки в описаниях или env переменных если есть
    find /opt/defectdojo -type f -name "*.yml" -exec sed -i "s/${OLD_FQDN}/${NEW_FQDN}/g" {} \; 2>/dev/null || true
    echo "✅ DefectDojo конфигурация обновлена"
fi



# 6. Обновление systemd сервисов
echo "🔧 Обновление systemd сервисов..."
find /etc/systemd/system -name "*.service" -type f -exec sed -i "s/${OLD_FQDN}/${NEW_FQDN}/g" {} \; 2>/dev/null || true

# 7. Обновление конфигов приложений
echo "🔧 Обновление конфигурационных файлов..."




# 8. Перезапуск сервисов
echo "🔄 Перезапуск сервисов..."

# Перезапуск GitLab
if [ -f "/etc/gitlab/gitlab.rb" ]; then
    echo "🔄 Применение конфигурации GitLab..."
    gitlab-ctl reconfigure
fi

# Перезапуск Docker сервисов
if systemctl is-active --quiet gitlab-docker.service 2>/dev/null; then
    echo "🔄 Перезапуск GitLab Docker..."
    systemctl restart gitlab-docker.service
fi

if systemctl is-active --quiet defectdojo-docker.service 2>/dev/null; then
    echo "🔄 Перезапуск DefectDojo Docker..."
    systemctl restart defectdojo-docker.service
fi

if systemctl is-active --quiet security-stack.service 2>/dev/null; then
    echo "🔄 Перезапуск Security Stack..."
    systemctl restart security-stack.service
fi

# 9. Проверка изменений
echo ""
echo "✅ Смена FQDN завершена!"
echo ""
echo "📊 Итоговые изменения:"
echo "   Старый FQDN: $OLD_FQDN"
echo "   Новый FQDN: $NEW_FQDN"
echo "   Hostname: $(hostname)"
echo "   Полный FQDN: $(hostname -f)"
echo ""
echo "🔄 Для полного применения изменений рекомендуется перезагрузка."
echo ""
read -p "🔄 Выполнить перезагрузку сейчас? (y/N): " reboot_confirm
case "$reboot_confirm" in
    [yY]|[yY][eE][sS])
        echo "🔁 Перезагрузка системы..."
        reboot now
        ;;
    *)
        echo "ℹ️  Перезагрузка не выполнена. Для полного применения выполните:"
        echo "   sudo reboot"
        ;;
esac