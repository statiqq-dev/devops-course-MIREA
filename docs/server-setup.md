# Конфигурация виртуальной машины devops-vm

Документ описывает конфигурацию сервера после практической работы № 5 и порядок её
восстановления со снимка `01-clean-install`. Команды выполняются по порядку сверху вниз.

Обозначения: **[Mac]** — терминал хостовой системы, **[VM]** — терминал сервера.

---

## 1. Параметры машины

| Параметр | Значение |
|---|---|
| Средство виртуализации | Parallels Desktop (macOS, Apple Silicon) |
| Гостевая ОС | Ubuntu Server 24.04 LTS, ARM64 (aarch64) |
| Имя узла / FQDN | `devops-vm` / `devops-vm.devops.local` |
| Оперативная память | 4096 мб |
| Количество ядер | 2 |
| Объём диска | 64 ГБ |
| Пакеты при установке | OpenSSH server; featured snaps не выбирались |

## 2. Сетевые интерфейсы

| Интерфейс | Тип адаптера | Адрес | Назначение |
|---|---|---|---|
| `enp0s5` | Parallels Shared Network | `10.211.55.6/24` (DHCP) | Выход в Интернет (NAT) и прямой доступ с Mac |
| `lo` | loopback | `127.0.0.1/8` | Локальные службы |

Shared Network в Parallels совмещает роли адаптеров NAT и Host-only из методических
указаний (VirtualBox), поэтому второй адаптер не требуется.

Проверка адреса после отката (адрес выдаётся по DHCP и теоретически может измениться):

```bash
# [VM] в консоли Parallels
ip -brief address
```

Если адрес изменился — обновить его в `/etc/hosts` и `~/.ssh/config` на Mac (разделы 3 и 4).

## 3. Правило проброса портов

Проброс портов **не используется**: в Shared Network Mac обращается к адресу
`10.211.55.6` напрямую.

| Порт хоста | Порт гостя | Примечание |
|---|---|---|
| — | 22 → 2222 | SSH-сервер переведён на порт 2222 (раздел 5) |

Файлы на Mac, которые **не затрагиваются** откатом снимка и уже готовы:

- ключевая пара `~/.ssh/devops_vm` и `~/.ssh/devops_vm.pub`;
- `~/.ssh/config`:

  ```
  Host devops
      HostName 10.211.55.6
      Port 2222
      User devops
      IdentityFile ~/.ssh/devops_vm
      IdentitiesOnly yes
  ```

- запись в `/etc/hosts` на Mac: `10.211.55.6   devops.local`.

## 4. Учётные записи

| Пользователь | Группы | Способ аутентификации | Назначение |
|---|---|---|---|
| `student` | `student`, `sudo` | пароль (только в консоли VM после hardening) | создан при установке |
| `devops` | `devops`, `sudo` | ключ `devops_vm` (ed25519), пароль только для `sudo` | администрирование и деплой |
| `root` | — | вход запрещён | — |

Пароли в документе не хранятся.

**Восстановление.** Сразу после отката SSH работает на порту 22 и принимает пароль:

```bash
# [Mac]
ssh student@10.211.55.6
```

```bash
# [VM] под student
sudo adduser devops            # задать пароль, остальные поля — Enter
sudo usermod -aG sudo devops
groups devops                  # ожидается: devops : devops sudo
```

```bash
# [Mac] в новой вкладке — разместить открытый ключ (порт пока 22)
ssh-copy-id -i ~/.ssh/devops_vm.pub devops@10.211.55.6
ssh -i ~/.ssh/devops_vm devops@10.211.55.6     # должен войти без пароля
```

## 5. Служба SSH

- Файл конфигурации: `/etc/ssh/sshd_config.d/99-hardening.conf`
  (основной `/etc/ssh/sshd_config` не изменяется, копия — `/etc/ssh/sshd_config.backup`).
- Служба запускается через `ssh.service`, активация по сокету (`ssh.socket`) отключена,
  иначе порт остаётся 22.

| Директива | Значение |
|---|---|
| Port | 2222 |
| PermitRootLogin | no |
| PasswordAuthentication | no |
| PubkeyAuthentication | yes |
| PermitEmptyPasswords | no |
| MaxAuthTries | 3 |
| LoginGraceTime | 30 |
| AllowUsers | devops |
| X11Forwarding | no |
| ClientAliveInterval | 300 |
| ClientAliveCountMax | 2 |

**Восстановление** (в сессии из раздела 4; сессию НЕ закрывать до проверки):

```bash
# [VM]
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

sudo tee /etc/ssh/sshd_config.d/99-hardening.conf > /dev/null <<'EOF'
Port 2222

PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30

AllowUsers devops

X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
EOF

# 50-cloud-init.conf содержит "PasswordAuthentication yes" и читается раньше 99-го — закомментировать
grep -r "PasswordAuthentication" /etc/ssh/sshd_config.d/ /etc/ssh/sshd_config
sudo sed -i 's/^PasswordAuthentication yes/#&/' /etc/ssh/sshd_config.d/50-cloud-init.conf 2>/dev/null

sudo sshd -t && echo "Конфигурация корректна"
sudo sshd -T | grep -Ei "^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers)"

sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh
sudo ss -tlnp | grep sshd      # ожидается 0.0.0.0:2222
```

Проверка в **новой** вкладке, старую не закрывать:

```bash
# [Mac]
ssh devops                     # успех, без пароля
```

Если вход прошёл — старую сессию можно закрыть и дальше работать через `ssh devops`.

## 6. Правила межсетевого экрана

| Параметр | Значение |
|---|---|
| Политика входящего трафика | deny |
| Политика исходящего трафика | allow |
| 2222/tcp | LIMIT — SSH (блокировка при 6+ подключениях за 30 с) |
| 80/tcp | ALLOW — HTTP (для ПР № 6) |
| 443/tcp | ALLOW — HTTPS (для ПР № 6) |
| Журналирование | medium, `/var/log/ufw.log` |

Правило для 2222 создаётся **до** `ufw enable`. `ufw allow ssh` не использовать —
оно открывает порт 22 из `/etc/services`, а не 2222.

**Восстановление:**

```bash
# [VM] через ssh devops
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw allow 80/tcp  comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw --force enable
sudo ufw logging medium
sudo ufw status verbose
```

Проверка: в новой вкладке Mac снова выполнить `ssh devops`.

### Доменное имя узла

```bash
# [VM]
sudo hostnamectl set-hostname devops-vm
sudo sed -i 's/^127.0.1.1.*/127.0.1.1 devops-vm.devops.local devops-vm/' /etc/hosts
hostname -f                    # ожидается devops-vm.devops.local
```

## 7. Снимки состояния

| Снимок | Дата и время | Состояние |
|---|---|---|
| `01-clean-install` | 08.10.2026 10:34 | ОС установлена и обновлена, пользователь `student`, SSH на 22 |
| `02-keys-configured` | 08.10.2026 11:03 | Пользователь `devops`, вход по ключу, `~/.ssh/config` на Mac |
| `03-ssh-hardened` | 08.10.2026 11:44 | SSH на 2222, root и пароли запрещены |

UFW и доменное имя настроены после `03-ssh-hardened` и в снимки не входят.

## Итоговая проверка

```bash
# [Mac]
scp scripts/audit.sh devops:~/audit.sh
ssh -t devops '~/audit.sh; echo "Код возврата: $?"'    # ожидается 0
ssh devops.local -p 2222 -i ~/.ssh/devops_vm -l devops 'hostname -f'
```


## 9. Контейнеризация

| Параметр | Значение |
|---|---|
| Docker Engine | из официального репозитория `download.docker.com` (пакет `docker.io` не используется), версия 29.9.2 (`docker version --format '{{.Server.Version}}'`) |
| Docker Compose | плагин `docker-compose-plugin`, v5.6.1 (`docker compose version`) |
| Группа docker | `devops` (имеет sudo; учётные записи без sudo в группу не включаются) |
| Проект на сервере | `/home/devops/app` (доставляется из `app/` репозитория через rsync) |
| Файл `.env` | `/home/devops/app/.env`, владелец `devops`, права `600`, только на сервере, в репозиторий не добавляется |
| Сервисы | `app` (образ `devops-app:1.0`, пользователь `app`), `db` (`postgres:16-alpine`) |
| Публикуемые порты | `127.0.0.1:5000 → app:5000`; порт СУБД 5432 не публикуется |
| Сеть | `app_backend` (bridge), СУБД доступна приложению по имени `db` |
| Именованный том | `app_db_data` → `/var/lib/postgresql/data` |
| Обратный прокси | `location /app/` в HTTPS-блоке `/etc/nginx/sites-available/devops-site`, `proxy_pass http://127.0.0.1:5000/` |

**Восстановление:**

```bash
# [VM] установка Docker Engine из официального репозитория
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker devops
exit                                   # перезайти, чтобы группа применилась
```

```bash
# [Mac] доставка проекта
rsync -avz --delete --exclude=.env app/ devops:app/
```

```bash
# [VM] секреты и запуск
cd ~/app
cp .env.example .env
chmod 600 .env
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 16)/" .env
docker compose up -d --build
docker compose ps                      # db: (healthy)
```

В HTTPS-блок `/etc/nginx/sites-available/devops-site` (после `location /`) добавить:

```nginx
location /app/ {
    proxy_pass http://127.0.0.1:5000/;
    proxy_set_header Host              $host;
    proxy_set_header X-Real-IP         $remote_addr;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

```bash
# [VM]
sudo nginx -t && sudo systemctl reload nginx
```
