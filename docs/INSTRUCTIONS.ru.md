# Развёртывание Java-приложения в Яндекс Облаке (Terraform)

## Что получится

```
 вы (Terraform, SSH)
        │
        ▼
 ┌──────────────┐  docker push   ┌─────────────────────────┐  docker pull  ┌──────────────┐
 │ demo-build   │ ─────────────► │ Yandex Container Registry│ ◄──────────── │ demo-prod    │
 │ собирает     │                │  (нативный репозиторий)  │               │ запускает    │
 │ образ (Maven)│                └─────────────────────────┘               │ контейнер    │
 └──────────────┘                                                          └──────────────┘
        └──────── одна сеть + одна группа безопасности (видят друг друга) ──────┘
```

* **Сборочный инстанс** (`demo-build`) — получает исходники, выполняет `docker build` по вашему `Dockerfile` (Maven собирает JAR) и пушит образ в Container Registry.
* **Продовый инстанс** (`demo-prod`) — тянет образ из реестра и запускает его на порту 8080. Имеет статический публичный IP.
* **Реестр** — Yandex Container Registry. Доступ без паролей: сервисные аккаунты ВМ (`build` — только push, `prod` — только pull), токен берётся из metadata-сервиса.
* Обе ВМ в одной подсети и одной группе безопасности, поэтому видят друг друга по внутренним IP и DNS (`demo-prod.ru-central1.internal`).

## Структура

```
Dockerfile, pom.xml, src/       приложение
terraform/
  main.tf variables.tf ...      сценарий п.2: build + prod + реестр
  modules/vm/                   шаблон ВМ (переиспользуемый)
  modules/network/              шаблон сети + security group
  templates/cloud-init.yaml.tpl cloud-init (Docker, скрипты логина/деплоя)
  examples/single-vm/           пример использования шаблонов в другом сценарии
docs/                           эта инструкция
```

## 1. Начальная настройка (один раз)

### 1.1. Установить инструменты
* Terraform ≥ 1.3, Yandex Cloud CLI (`yc`), SSH-клиент.

### 1.2. Настроить `yc` и получить идентификаторы
```bash
yc init
yc config get cloud-id
yc config get folder-id
```
Должен быть включён платёжный аккаунт, у вашего пользователя — роль `editor` (или выше) на каталог. Для создания IAM-привязок реестра нужна роль `admin` на каталог (или `container-registry.admin` + `iam.serviceAccounts.admin`).

### 1.3. Зеркало провайдеров (для РФ)
Создайте `~/.terraformrc`:
```hcl
provider_installation {
  network_mirror {
    url     = "https://terraform-mirror.yandexcloud.net/"
    include = ["registry.terraform.io/*/*"]
  }
  direct {
    exclude = ["registry.terraform.io/*/*"]
  }
}
```

### 1.4. Аутентификация Terraform
Простой вариант (токен живёт ~12 часов):
```bash
export YC_TOKEN=$(yc iam create-token)
```
Либо сервисный аккаунт с ключом:
```bash
yc iam service-account create --name terraform
yc resource-manager folder add-access-binding <folder-id> --role editor --subject serviceAccount:<sa-id>
yc iam key create --service-account-name terraform --output ~/.yc/terraform-key.json
```
и затем `sa_key_file = "~/.yc/terraform-key.json"` в `terraform.tfvars`.
(Для привязок реестра роли `editor` может не хватить — тогда выдайте `admin`.)

### 1.5. SSH-ключ
```bash
ssh-keygen -t ed25519      # если ключа ещё нет
```
Terraform использует его для входа на ВМ (загрузка исходников, деплой).

## 2. Запуск сценария: сборка + прод

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # впишите cloud_id и folder_id
terraform init
terraform plan
terraform apply
```

Что происходит по порядку:
1. Создаются сеть, подсеть, security group, реестр, сервисные аккаунты и права.
2. Поднимается `demo-build`; cloud-init ставит Docker.
3. Terraform по SSH загружает zip с исходниками (без `terraform/`, `docs/`, `target/`), выполняет `docker build` и `docker push` (тег = хэш исходников + `latest`).
4. Поднимается `demo-prod` со статическим IP, затем Terraform по SSH запускает `deploy-app <образ>` и ждёт ответа приложения.

Проверка:
```bash
curl $(terraform output -raw app_url)      # Hello from Dockerized Java app!
terraform output
```

Обновление приложения: измените код и снова `terraform apply` — хэш изменится, образ пересоберётся и перезапустится на проде.

Удаление всего: `terraform destroy` (образы в реестре нужно удалить заранее или вручную: реестр с образами не удалится).

Первый запуск занимает ~5–8 минут (установка Docker, загрузка образов Maven/Alpine с Docker Hub).

### Важные параметры (`variables.tf`)
| Переменная | Назначение |
|---|---|
| `ssh_allowed_cidrs` | кто может заходить по SSH. **Укажите `["ваш_IP/32"]`** — Terraform тоже должен проходить по этому списку |
| `app_port` | внешний порт приложения (по умолчанию 8080) |
| `build_vm`, `prod_vm` | cores, memory, core_fraction, disk_size, preemptible |
| `zone` | зона доступности |
| `name_prefix` | префикс имён ресурсов |
| `app_source_dir` | каталог с `pom.xml` и `Dockerfile` |

Сборке нужно ≥ 4 ГБ RAM (Maven). Для экономии на сборке можно поставить `preemptible = true`.

## 3. Использование шаблонов в других сценариях

### Модуль `modules/vm` — шаблон ВМ
Обязательные параметры: `name`, `zone`, `subnet_id`, `ssh_public_key`. Остальное — по умолчанию (Ubuntu 22.04, 2 vCPU / 2 ГБ, 20 ГБ SSD, публичный IP).

| Параметр | Описание |
|---|---|
| `platform_id`, `cores`, `memory`, `core_fraction` | ресурсы ВМ |
| `preemptible` | прерываемая ВМ |
| `image_id` / `image_family` | образ ОС (`ubuntu-2204-lts`, `debian-12`, …) |
| `boot_disk_size`, `boot_disk_type` | загрузочный диск |
| `public_ip` / `nat_ip_address` | публичный адрес: временный или зарезервированный (`yandex_vpc_address`) |
| `security_group_ids` | группы безопасности |
| `service_account_id` | сервисный аккаунт ВМ |
| `user_data` | cloud-init (`#cloud-config`) |
| `extra_metadata`, `labels`, `hostname`, `ssh_user` | прочее |

Выходы: `id`, `name`, `fqdn`, `internal_ip`, `public_ip`, `ssh_user`.

### Модуль `modules/network` — сеть
Создаёт сеть, подсеть и security group, которая: пускает трафик внутри группы (ВМ видят друг друга), SSH с `ssh_allowed_cidrs`, TCP-порты `app_ports` с `app_allowed_cidrs`, весь исходящий трафик.
Если ваш каталог уже содержит сеть `default`, можно не использовать модуль, а передать в `modules/vm` её `subnet_id` — ВМ в одной сети по умолчанию видят друг друга.

### Пример
См. `terraform/examples/single-vm/main.tf` — две ВМ с nginx из одного модуля:
```bash
cd terraform/examples/single-vm
terraform init && terraform apply -var cloud_id=... -var folder_id=...
```
Подключение модуля из другого проекта:
```hcl
module "vm" {
  source         = "git::https://example.com/repo.git//terraform/modules/vm"
  name           = "my-vm"
  zone           = "ru-central1-b"
  subnet_id      = yandex_vpc_subnet.my.id
  ssh_public_key = file("~/.ssh/id_ed25519.pub")
}
```
Для шаблона cloud-init (`templates/cloud-init.yaml.tpl`) используйте `templatefile()`, параметры: `role` (`build`/`prod`), `extra_packages`, `app_port`.

## 4. Частые проблемы
* **`Permission denied` при создании привязок реестра** — выдайте себе/сервисному аккаунту Terraform роль `admin` на каталог.
* **Таймаут SSH в provisioner** — проверьте `ssh_allowed_cidrs` (ваш текущий внешний IP) и пути к ключам.
* **Ошибка pull образов Maven/Alpine** — лимиты Docker Hub; повторите `terraform apply` позже.
* **Ошибка `quota exceeded`** — проверьте квоты (IP-адреса, vCPU) в консоли.
* **Безопасность**: `0.0.0.0/0` для SSH оставлен для удобства обучения; на реальных окружениях ограничьте. `terraform.tfstate` содержит чувствительные данные — не коммитьте его.
