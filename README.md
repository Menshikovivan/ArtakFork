# ArtakFork

Форк [Screamshow/forkop-x](https://github.com/Screamshow/forkop-x) без ограничения подписок по провайдеру. Базовый коммит: `2a0951294d9cdd24370ff97fc1bc09fcb8b7f484`.



В версии 2.4.3-canary.4 устранена также проверка разрешённых доменов в LuCI. Регрессионный тест проверяет исходный и поставляемый JavaScript интерфейса.

В версии 2.4.3-canary.5 исправлена публикация списков при наличии служебных community-*.json и других посторонних файлов. Эти файлы сохраняются; проверка обязательных списков и откат при повреждении управляемых файлов остаются включены.

## Установка одной командой

Для установки на стабильном OpenWrt 25.12 с APK и архитектурой aarch64_cortex-a53 (включая Cudy WR3000U v1) выполните по SSH от root:

```sh
wget -O /tmp/artak-install.sh https://github.com/Menshikovivan/ArtakFork/releases/download/2.4.3-canary.5/artak-install.sh && sh /tmp/artak-install.sh
```

Пакеты backend, LuCI и русской локализации скачиваются из [Releases этого репозитория](https://github.com/Menshikovivan/ArtakFork/releases/tag/2.4.3-canary.5). Установщик проверяет контрольные суммы SHA256 и сохраняет конфигурацию в `/root/artakfork-backups/`. Локальные APK устанавливаются с разрешением неподписанных пакетов через `apk add --allow-untrusted`.

Контрольные суммы охватывают также зеркальные bootstrap-пакеты. Их происхождение записано в `bootstrap-sources.json`, соответствующие исходники приложены к релизу. Новая сборка сверяет версии с upstream latest и останавливается, если версии установщика устарели.

После обновления перезагрузите страницу LuCI с очисткой кэша браузера (Ctrl+F5), чтобы загрузить новый JavaScript.

Для скачивания и проверки без установки: `sh /tmp/artak-install.sh --check`.

Установщик поддерживает чистую установку: устанавливает sing-box Extended и, если Forkop отсутствует, базовый Forkop, затем ArtakFork. Текущий релиз включает последние стабильные версии на момент сборки: Forkop 1.0.5 и sing-box Extended 1.14.3-extended-2.7.3. Уже установленный Extended этой версии повторно не устанавливается. SNAPSHOT, другие архитектуры и OpenWrt с opkg этим установщиком не поддерживаются. Системные зависимости загружаются из родных репозиториев OpenWrt; пакеты должны соответствовать установленному ядру. Конфликты с другими вариантами sing-box не обходятся принудительным удалением. Встроенная установка обновлений Forkop через старый интерфейс отключена: используйте установщик ArtakFork. Списки маршрутизации и отдельные компоненты сохраняют свои прежние источники.

## Проверка

На Linux/OpenWrt с ucode и модулем fs:

```sh
ucode -L forkop/files/usr/lib tests/subscription_source_entry.uc
```

Workflow `Subscription CI` собирает закреплённую версию ucode и запускает тест при push, pull request или вручную.

## Сборка

IPK/APK собираются исходным `build.sh` на Linux с OpenWrt SDK. Сборка и публикация собственных релизов настроены в `.github/workflows/artak-release.yml`. Версия установщика должна совпадать с версией релиза. Пример:

```sh
bash build.sh 2.4.3-canary.5 dist/ArtakFork
```

Для XHTTP требуется совместимый движок, например [forkop-x-engine](https://github.com/Screamshow/forkop-x-engine). Удаление фильтра подписок само по себе не добавляет XHTTP в штатный sing-box. Перед установкой необходимо проверить архитектуру и версию OpenWrt.

Исходный `install.sh` сохранён для истории upstream; для ArtakFork используйте только `artak-install.sh` из Releases. Нативный тест парсера и сборка пакетов выполняются в GitHub Actions. Реальное XHTTP-соединение на роутере ещё не проверено.

## Происхождение

Основан на Forkop X, Forkop (ранее Podkop Plus) и [Podkop](https://github.com/itdoginfo/podkop). Авторство и лицензии сохранены в исходниках и `LICENSE`. ArtakFork является самостоятельной модификацией и не заявляет о связи с авторами upstream.
