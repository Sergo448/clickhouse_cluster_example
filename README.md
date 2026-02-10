# ClickHouse Cluster Example

Кластер ClickHouse из 3 реплик с координацией через ZooKeeper-ансамбль (3 ноды), развёрнутый через Docker Compose. Настроен для работы на ноутбуке с ограниченными ресурсами.

## Архитектура

```
┌─────────────────────────────────────────────────┐
│                 clickhouse-net                   │
│                                                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐      │
│  │ zk-01    │  │ zk-02    │  │ zk-03    │      │
│  │ :2181    │  │ :2181    │  │ :2181    │      │
│  │ 256M/0.3C│  │ 256M/0.3C│  │ 256M/0.3C│      │
│  └──────────┘  └──────────┘  └──────────┘      │
│        │              │              │           │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐      │
│  │ ch-01    │  │ ch-02    │  │ ch-03    │      │
│  │ :8123    │  │ :8123    │  │ :8123    │      │
│  │ :9000    │  │ :9000    │  │ :9000    │      │
│  │  1G/0.75C│  │  1G/0.75C│  │  1G/0.75C│      │
│  └──────────┘  └──────────┘  └──────────┘      │
└─────────────────────────────────────────────────┘
```

**Топология кластера (`company_cluster`):** 1 шард, 3 реплики с `internal_replication=true`.

## Требования

- Docker Engine 20.10+
- Docker Compose v2
- **Минимум 4 GB RAM** (рекомендуется 8 GB)
- **Минимум 2 CPU ядра** (рекомендуется 4)

## Быстрый старт

```bash
# Запуск кластера
docker compose up -d

# Проверить, что все контейнеры поднялись
docker compose ps

# Подключиться к первой ноде через HTTP
curl http://localhost:8123/?query=SELECT+1

# Подключиться через clickhouse-client
docker exec -it clickhouse-01 clickhouse-client
```

## Порты

| Сервис         | HTTP порт | Native порт | ZooKeeper порт |
|----------------|-----------|-------------|----------------|
| clickhouse-01  | 8123      | 9000        | —              |
| clickhouse-02  | 8124      | 9001        | —              |
| clickhouse-03  | 8125      | 9002        | —              |
| zk-01          | —         | —           | 2181           |
| zk-02          | —         | —           | 2182           |
| zk-03          | —         | —           | 2183           |

## Ограничения ресурсов

Настройки оптимизированы для работы на ноутбуке. Запросы могут обрабатываться медленнее, но система не будет перегружать хост.

### Docker Compose (deploy.resources)

| Сервис      | CPU лимит | RAM лимит | CPU резерв | RAM резерв |
|-------------|-----------|-----------|------------|------------|
| zk-01/02/03 | 0.30      | 256 MB    | 0.10       | 64 MB      |
| ch-01/02/03 | 0.75      | 1 GB      | 0.20       | 256 MB     |

**Суммарное потребление (максимум):** ~3.15 CPU, ~3.75 GB RAM.

### ZooKeeper (zoo.cfg + JVM)

| Параметр              | Значение | Описание                                   |
|-----------------------|----------|--------------------------------------------|
| `ZOO_JVMFLAGS -Xmx`  | 128m     | Максимальный размер JVM-кучи               |
| `ZOO_JVMFLAGS -Xms`  | 64m      | Начальный размер JVM-кучи                  |
| `maxClientCnxns`      | 30       | Макс. подключений с одного IP              |
| `preAllocSize`        | 32768    | Размер преаллокации transaction log (KB)   |
| `snapCount`           | 50000    | Кол-во транзакций между снапшотами         |
| `globalOutstandingLimit` | 100   | Макс. очередь запросов в обработке         |

### ClickHouse — серверный уровень (resource-limits.xml)

| Параметр                              | Значение | Описание                                |
|---------------------------------------|----------|-----------------------------------------|
| `background_pool_size`                | 2        | Потоки фоновых мержей                   |
| `background_schedule_pool_size`       | 2        | Потоки планировщика                     |
| `background_fetches_pool_size`        | 1        | Потоки фоновых fetch (репликация)       |
| `background_common_pool_size`         | 1        | Общий фоновый пул                       |
| `max_connections`                     | 64       | Макс. одновременных соединений          |
| `max_concurrent_queries`              | 10       | Макс. одновременных запросов            |
| `mark_cache_size`                     | 128 MB   | Кэш меток (mark index)                 |
| `uncompressed_cache_size`             | 32 MB    | Кэш несжатых данных                    |
| `log level`                           | warning  | Уменьшен уровень логирования            |

### ClickHouse — уровень пользователя (users.xml, профиль `default`)

| Параметр                   | Значение  | Описание                               |
|----------------------------|-----------|----------------------------------------|
| `max_memory_usage`         | 150 MB    | Лимит RAM на один запрос               |
| `max_memory_usage_for_user`| 300 MB    | Лимит RAM на все запросы пользователя  |
| `max_threads`              | 2         | Потоки на SELECT-запрос                |
| `max_insert_threads`       | 1         | Потоки на INSERT                       |
| `max_read_buffer_size`     | 1 MB      | Размер буфера чтения                   |

## Структура проекта

```
clickhouse_cluster_example/
├── docker-compose.yml                  # Основной файл, все сервисы + лимиты ресурсов
├── README.md
├── clickhouse/
│   ├── config.d/
│   │   ├── cluster.xml                 # Топология кластера и ZooKeeper-ноды
│   │   ├── resource-limits.xml         # Серверные лимиты ClickHouse (пулы, кэши, соединения)
│   │   ├── macros-node1.xml            # Макросы для ноды 1 (shard/replica)
│   │   ├── macros-node2.xml            # Макросы для ноды 2
│   │   └── macros-node3.xml            # Макросы для ноды 3
│   └── users.d/
│       └── users.xml                   # Пользователи, профили, лимиты на запросы
└── zookeeper/
    └── zoo.cfg                         # Конфигурация ZooKeeper
```

## Работа с кластером

### Создание реплицированной таблицы

```sql
CREATE TABLE events ON CLUSTER company_cluster
(
    event_date Date,
    event_type String,
    value      UInt64
)
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/events', '{replica}')
PARTITION BY toYYYYMM(event_date)
ORDER BY (event_date, event_type);
```

### Проверка состояния кластера

```sql
-- Список нод кластера
SELECT * FROM system.clusters WHERE cluster = 'company_cluster';

-- Статус репликации
SELECT
    database, table, replica_name,
    is_leader, total_replicas, active_replicas
FROM system.replicas
FORMAT Pretty;

-- Потребление памяти сервером
SELECT
    formatReadableSize(sum(value)) AS memory_usage
FROM system.metrics
WHERE metric LIKE '%Memory%';
```

### Проверка здоровья ZooKeeper

```bash
# Статус ансамбля
echo ruok | docker exec -i zk-01 nc localhost 2181

# Подробная статистика
echo mntr | docker exec -i zk-01 nc localhost 2181
```

## Управление кластером

```bash
# Запуск
docker compose up -d

# Остановка
docker compose down

# Остановка с удалением данных
docker compose down -v

# Просмотр логов конкретного сервиса
docker compose logs -f clickhouse-01

# Перезапуск одной ноды
docker compose restart clickhouse-01

# Просмотр потребления ресурсов
docker stats
```

## Тюнинг под ваше железо

Если ноутбук продолжает тормозить, уменьшите лимиты в `docker-compose.yml`:

```yaml
deploy:
  resources:
    limits:
      cpus: "0.50"    # было 0.75 для ClickHouse
      memory: 768M     # было 1G
```

Если, наоборот, ресурсов достаточно и хочется ускорить работу:

1. Увеличьте `cpus` и `memory` в `docker-compose.yml`
2. Увеличьте `max_threads`, `max_memory_usage` в `clickhouse/users.d/users.xml`
3. Увеличьте `background_pool_size` в `clickhouse/config.d/resource-limits.xml`
4. Увеличьте `-Xmx` в `ZOO_JVMFLAGS` в `docker-compose.yml`

## Известные особенности

- При заданных лимитах кластер стартует **30-60 секунд** (ZooKeeper формирует кворум).
- Фоновые мержи замедлены — таблицы с частыми INSERT могут иметь больше партов.
- При `max_memory_usage=150MB` сложные аналитические запросы на больших данных могут упасть с ошибкой `Memory limit exceeded`. Увеличьте лимит для конкретного запроса: `SET max_memory_usage = 500000000;`
