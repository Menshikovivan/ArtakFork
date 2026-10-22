# ArtakFork

Форк [Screamshow/forkop-x](https://github.com/Screamshow/forkop-x) без ограничения подписок по провайдеру. Базовый коммит: `2a0951294d9cdd24370ff97fc1bc09fcb8b7f484`.



## Установка одной командой

Для обновления уже установленного Forkop на стабильном OpenWrt 25.12 с APK выполните по SSH от root:

```sh
wget -O /tmp/artak-install.sh https://github.com/Menshikovivan/ArtakFork/releases/download/2.4.3-canary.2/artak-install.sh && sh /tmp/artak-install.sh
```

Пакеты backend, LuCI и русской локализации скачиваются из [Releases этого репозитория](https://github.com/Menshikovivan/ArtakFork/releases/tag/2.4.3-canary.2). Установщик проверяет контрольные суммы SHA256 и сохраняет конфигурацию в `/root/artakfork-backups/`. Самостоятельно собранные APK не подписаны, поэтому для этих трёх локальных файлов применяется `apk add --allow-untrusted`.

Для скачивания и проверки без установки: `sh /tmp/artak-install.sh --check`.

Установщик сохраняет имеющийся движок sing-box. Для XHTTP он должен поддерживать этот транспорт. Чистая установка, SNAPSHOT и OpenWrt с opkg этим установщиком не поддерживаются. Встроенная установка обновлений Forkop через старый интерфейс отключена: используйте установщик ArtakFork. Списки маршрутизации и отдельные компоненты сохраняют свои прежние источники.

## Проверка

На Linux/OpenWrt с ucode и модулем fs:

```sh
ucode -L forkop/files/usr/lib tests/subscription_source_entry.uc
```

Workflow `Subscription CI` собирает закреплённую версию ucode и запускает тест при push, pull request или вручную.

## Сборка

IPK/APK собираются исходным `build.sh` на Linux с OpenWrt SDK. Сборка и публикация собственных релизов настроены в `.github/workflows/artak-release.yml`. Версия установщика должна совпадать с версией релиза. Пример:

```sh
bash build.sh 2.4.3-canary.2 dist/ArtakFork
```

Для XHTTP требуется совместимый движок, например [forkop-x-engine](https://github.com/Screamshow/forkop-x-engine). Удаление фильтра подписок само по себе не добавляет XHTTP в штатный sing-box. Перед установкой необходимо проверить архитектуру и версию OpenWrt.

Исходный `install.sh` сохранён для истории upstream; для ArtakFork используйте только `artak-install.sh` из Releases. Нативный тест парсера и сборка пакетов выполняются в GitHub Actions. Реальное XHTTP-соединение на роутере ещё не проверено.

## Происхождение

Основан на Forkop X, Forkop (ранее Podkop Plus) и [Podkop](https://github.com/itdoginfo/podkop). Авторство и лицензии сохранены в исходниках и `LICENSE`. ArtakFork является самостоятельной модификацией и не заявляет о связи с авторами upstream.
