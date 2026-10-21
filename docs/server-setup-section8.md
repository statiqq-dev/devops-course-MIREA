
## 8. Веб-сервер

| Параметр | Значение |
|---|---|
| Пакет | `nginx` из репозитория Ubuntu (`sudo apt install -y nginx`) |
| Конфигурация ресурса | `/etc/nginx/sites-available/devops-site`, ссылка в `/etc/nginx/sites-enabled/` |
| Стандартный ресурс | отключён (ссылка `/etc/nginx/sites-enabled/default` удалена) |
| Каталог ресурса | `/var/www/devops-site`, владелец `devops:devops`, каталоги `755`, файлы `644` |
| Сертификат | `/etc/ssl/certs/devops.crt`, `root`, права `644` |
| Закрытый ключ | `/etc/ssl/private/devops.key`, `root`, права `600` |
| Срок действия сертификата | 365 дней, до ⚠ ЗАПОЛНИТЬ (`openssl x509 -enddate -noout -in /etc/ssl/certs/devops.crt`) |
| Журналы | `/var/log/nginx/devops-site.access.log`, `/var/log/nginx/devops-site.error.log` |
| Порты UFW | 80/tcp и 443/tcp уже разрешены (раздел 6) |

**Восстановление:**

```bash
# [VM]
sudo apt update && sudo apt install -y nginx rsync
sudo mkdir -p /var/www/devops-site
sudo chown -R devops:devops /var/www/devops-site

sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj "/CN=devops.local" \
  -addext "subjectAltName=DNS:devops.local"

sudo tee /etc/nginx/sites-available/devops-site > /dev/null <<'EOF'
server {
    listen 80;
    listen [::]:80;
    server_name devops.local;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name devops.local;

    ssl_certificate     /etc/ssl/certs/devops.crt;
    ssl_certificate_key /etc/ssl/private/devops.key;
    ssl_protocols       TLSv1.2 TLSv1.3;

    root /var/www/devops-site;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    error_page 404 /404.html;

    access_log /var/log/nginx/devops-site.access.log;
    error_log  /var/log/nginx/devops-site.error.log;
}
EOF

sudo ln -s /etc/nginx/sites-available/devops-site /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

```bash
# [Mac] — сертификат был пересоздан, поэтому его нужно скачать заново
scp devops:/etc/ssl/certs/devops.crt ~/devops.crt
scripts/deploy.sh                      # доставка содержимого site/
```
