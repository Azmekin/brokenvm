#!/bin/bash

set -e

echo "🧹 Полная очистка системы от контейнеров и кешей..."

# Проверка root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Скрипт должен запускаться с правами root"
    exit 1
fi

# Переменные
CLEAN_IMAGES="${CLEAN_IMAGES:-false}"
CLEAN_VOLUMES="${CLEAN_VOLUMES:-false}"
CLEAN_NETWORKS="${CLEAN_NETWORKS:-false}"

# Парсинг аргументов
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--images)
            CLEAN_IMAGES="true"
            shift
            ;;
        -v|--volumes)
            CLEAN_VOLUMES="true"
            shift
            ;;
        -n|--networks)
            CLEAN_NETWORKS="true"
            shift
            ;;
        -a|--all)
            CLEAN_IMAGES="true"
            CLEAN_VOLUMES="true"
            CLEAN_NETWORKS="true"
            shift
            ;;
        *)
            echo "❌ Неизвестный аргумент: $1"
            exit 1
            ;;
    esac
done

echo "🔧 Настройки очистки:"
echo "   🗑️  Удаление образов: $CLEAN_IMAGES"
echo "   💾 Удаление томов: $CLEAN_VOLUMES"
echo "   🌐 Удаление сетей: $CLEAN_NETWORKS"
echo ""

# Подтверждение
read -p "⚠️  ВЫ ПОТЕРЯЕТЕ ВСЕ ДАННЫЕ! Продолжить? (y/N): " confirm
case "$confirm" in
    [yY]|[yY][eE][sS])
        echo "🔄 Начинаю очистку..."
        ;;
    *)
        echo "❌ Отменено"
        exit 0
        ;;
esac

# Функции
stop_services() {
    echo "🛑 Остановка systemd сервисов..."
    
    systemctl stop security-stack.service 2>/dev/null || true
    systemctl stop gitlab-docker.service 2>/dev/null || true
    systemctl stop defectdojo-docker.service 2>/dev/null || true
    systemctl stop security-setup.service 2>/dev/null || true
    systemctl stop ctf-secret-rotation.service 2>/dev/null || true
    
    echo "✅ Сервисы остановлены"
}

stop_containers() {
    echo "🛑 Остановка всех контейнеров..."
    
    # Останавливаем конкретные сервисы через docker-compose
    if [ -f "/opt/gitlab/docker-compose.yml" ]; then
        echo "🗑️  Остановка GitLab..."
        cd /opt/gitlab && docker-compose down 2>/dev/null || true
    fi
    
    if [ -f "/opt/defectdojo/docker-compose.yml" ]; then
        echo "🗑️  Остановка DefectDojo..."
        cd /opt/defectdojo && docker-compose down 2>/dev/null || true
    fi
    
    # Останавливаем все остальные контейнеры
    echo "🛑 Остановка всех Docker контейнеров..."
    docker stop $(docker ps -aq) 2>/dev/null || true
    
    echo "✅ Контейнеры остановлены"
}

remove_containers() {
    echo "🗑️  Удаление всех контейнеров..."
    docker rm -f $(docker ps -aq) 2>/dev/null || true
    echo "✅ Контейнеры удалены"
}


remove_volumes() {
    echo "🗑️  Удаление всех Docker томов..."
    docker volume rm -f $(docker volume ls -q) 2>/dev/null || true
    echo "✅ Тома удалены"
}

remove_networks() {
    echo "🗑️  Удаление всех Docker сетей (кроме стандартных)..."
    docker network rm $(docker network ls -q --filter "name=-default") 2>/dev/null || true
    echo "✅ Сети удалены"
}

clean_docker_system() {
    echo "🧹 Очистка Docker системы..."
    docker system prune -a -f --volumes
    echo "✅ Docker система очищена"
}

clean_app_data() {
    echo "🗑️  Очистка данных приложений..."
    
    # GitLab данные
    if [ -d "/opt/gitlab" ]; then
        echo "🗑️  Удаление данных GitLab..."
        rm -rf /opt/gitlab/data/* 2>/dev/null || true
        rm -rf /opt/gitlab/logs/* 2>/dev/null || true
        rm -rf /opt/gitlab/config/* 2>/dev/null || true
    fi
    
    # DefectDojo данные
    if [ -d "/opt/defectdojo" ]; then
        echo "🗑️  Удаление данных DefectDojo..."
        rm -rf /opt/defectdojo/* 2>/dev/null || true
    fi
    
    # CTF данные
    if [ -d "/opt/ctf" ]; then
        echo "🗑️  Удаление CTF данных..."
        rm -rf /opt/ctf/* 2>/dev/null || true
    fi
    
    # Docker кеши
    echo "🗑️  Очистка Docker кешей..."
    rm -rf /var/lib/docker/overlay2/* 2>/dev/null || true
    rm -rf /var/lib/docker/containers/* 2>/dev/null || true
    
    echo "✅ Данные приложений очищены"
}




clean_temp_files() {
    echo "🗑️  Очистка временных файлов..."
    
    rm -f /tmp/gitlab_token.txt 2>/dev/null || true
    rm -f /tmp/gitlab_ctf_token.txt 2>/dev/null || true
    rm -f /tmp/dd_readonly_token.txt 2>/dev/null || true
    rm -f /tmp/gitlab_project_id.txt 2>/dev/null || true
    
    # Очистка логов
    find /var/log -name "*.log" -type f -delete 2>/dev/null || true
    journalctl --vacuum-time=1d 2>/dev/null || true
    
    echo "✅ Временные файлы очищены"
}

show_status() {
    echo ""
    echo "📊 Статус после очистки:"
    echo "   Контейнеры: $(docker ps -aq 2>/dev/null | wc -l || echo 0)"
    echo "   Образы: $(docker images -q 2>/dev/null | wc -l || echo 0)"
    echo "   Тома: $(docker volume ls -q 2>/dev/null | wc -l || echo 0)"
    echo "   Сети: $(docker network ls -q 2>/dev/null | wc -l || echo 0)"
    echo ""
}

# Главный процесс очистки
main() {
    echo "🚀 Начало полной очистки..."
    
    stop_services
    stop_containers
    remove_containers
    
    if [ "$CLEAN_IMAGES" = "true" ]; then
        remove_images
    fi
    
    if [ "$CLEAN_VOLUMES" = "true" ]; then
        remove_volumes
    fi
    
    if [ "$CLEAN_NETWORKS" = "true" ]; then
        remove_networks
    fi
    
    clean_docker_system
    clean_app_data
    clean_systemd_services
    clean_scripts
    clean_temp_files
    
    show_status
    
    echo "✅ Полная очистка завершена!"
    echo ""
    echo "💡 Рекомендации:"
    echo "   - Для переустановки запустите скрипты установки заново"
    echo "   - Система готова к чистой установке"
    echo "   - Вы можете перезагрузить систему: sudo reboot"
}

main