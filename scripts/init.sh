# 1. Сначала устанавливаем приложения (старые скрипты)
sudo ./gitlab-setup.sh
sudo ./defect-dojo-setup.sh
sudo ./gitlab-public-user.sh
# 2. Потом создаем сервисы (новые скрипты)
sudo ./create-gitlab-service.sh
sudo ./create-defectdojo-service.sh
sudo ./repo-init.sh
# 4. Генерируем ключ
sudo setup-ctf-secret.sh
