#!/bin/bash

set -e

echo "🚀 Установка DefectDojo в Docker..."

# Проверка root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Скрипт должен запускаться с правами root"
    exit 1
fi

# Переменные
DD_DIR="/opt/defectdojo"
DOCKER_COMPOSE_FILE="$DD_DIR/docker-compose.yml"

echo "📦 Установка Docker..."
apt-get update
apt-get install -y curl git docker.io docker-compose
systemctl enable docker
systemctl start docker

echo "📥 Загрузка DefectDojo..."
mkdir -p $DD_DIR
cd $DD_DIR

if [ ! -d "$DD_DIR/django-DefectDojo" ]; then
    git clone https://github.com/DefectDojo/django-DefectDojo.git .
else
    echo "⚠️ DefectDojo уже установлен, обновление..."
    git pull
fi

git checkout master

echo "🐳 Запуск DefectDojo..."
docker-compose up -d

echo "⏳ Ожидание запуска сервисов (это может занять несколько минут)..."
for i in {1..60}; do
    if docker-compose logs uwsgi 2>/dev/null | grep -q "Listening at"; then
        break
    fi
    echo -n "."
    sleep 5
done

echo ""
echo "🔐 Настройка администратора..."
docker-compose exec -T uwsgi /bin/bash -c "
python3 manage.py migrate && \
python3 manage.py createsuperuser --noinput --username admin --email admin@example.com || true"

echo "✅ DefectDojo установлен в Docker!"
echo "🌐 URL: http://$(hostname -I | awk '{print $1}'):8080"
echo "🔑 Логин: admin"
echo "🔒 Пароль: admin"
echo ""
echo "🛠️ Команды управления:"
echo "   cd /opt/defectdojo"
echo "   sudo docker-compose up -d     # Запуск"
echo "   sudo docker-compose down      # Остановка"
echo "   sudo docker-compose restart   # Перезапуск"
echo "   sudo docker-compose logs -f   # Логи"

# Создание скрипта управления
cat > /usr/local/bin/defectdojo-docker-manage << EOF
#!/bin/bash
cd /opt/defectdojo
case "\$1" in
    start) docker-compose up -d ;;
    stop) docker-compose down ;;
    restart) docker-compose restart ;;
    status) docker-compose ps ;;
    logs) docker-compose logs -f ;;
    update) 
        git pull
        docker-compose down
        docker-compose build --no-cache
        docker-compose up -d
        ;;
    *) echo "Usage: defectdojo-docker-manage {start|stop|restart|status|logs|update}" ;;
esac
EOF

chmod +x /usr/local/bin/defectdojo-docker-manage