# 1. Сначала устанавливаем приложения (старые скрипты)
sudo ./gitlab-setup.sh
sudo ./defect-dojo-setup.sh

# 2. Потом создаем сервисы (новые скрипты)
sudo ./create-gitlab-service.sh
sudo ./create-defectdojo-service.sh
sudo ./create-security-stack-service.sh
sudo ./setup-boot-service.sh

# 3. Проверяем
sudo systemctl status security-stack
sudo systemctl status security-setup
# 4. Генерируем ключ
sudo setup-ctf-secret.sh
# 5. Перезагружаем для проверки
sudo reboot