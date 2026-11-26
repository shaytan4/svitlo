# Svitlo

Android-приложение для просмотра графика отключений электроэнергии (УЗ).

Данные берутся со страницы графика на сайте УЗ.

Вкладки:

- **Сьогодні** — график на сегодня и таймер: сколько ещё будет свет / отключение
- **Завтра** — график на завтра, если он уже опубликован
- **Налаштування** — настройки
- **Сайт** — открывает страницу графика в браузере

Каждый временной диапазон показан карточкой: 🟢 зелёная — свет есть, 🔴 красная — отключение. Текущий диапазон подсвечен, список сам прокручивается к нему.

Настройки (сохраняются между запусками):

- **Группа** — очередь отключений
- **Группировать время** — объединяет подряд идущие диапазоны с одинаковым статусом в один блок (например, `10-30 13-00` + `13-00 14-00` → `10-30 14-00`); таймер тогда считает до реальной смены статуса
- **Тема** — светлая / тёмная
- **Язык** — УКР / РУ
- **Обновления** — проверяет последний GitHub Release, скачивает и устанавливает APK

Данные обновляются кнопкой ↻ в шапке; при отсутствии сети показывается ошибка.

---

## Зависимости для сборки

- **Flutter SDK** (Dart 3+) — https://docs.flutter.dev/get-started/install/linux, `bin` должен быть в `$PATH`
- **Java JDK 17+**
- **Android SDK** (через Android Studio или `sdkmanager`). Скрипт ищет его в `$ANDROID_HOME`, `$ANDROID_SDK_ROOT`, `~/Android/Sdk` и т.п.

---

## Сборка

```bash
./build-android-flutter.sh
```

Скрипт:
1. Проверяет наличие Flutter и Android SDK
2. Генерирует `flutter/android/local.properties`
3. Выполняет `flutter pub get`
4. Собирает release APK, разделённые по ABI (`arm64-v8a`, `armeabi-v7a`)
5. Копирует arm64 APK в корень репозитория как `svitlo-flutter.apk`

Все APK также доступны в `flutter-apk/` (симлинк на `flutter/build/app/outputs/flutter-apk/`).

---

## Подпись release APK

Release-сборка подписывается ключом из `flutter/android/key.properties` (в git не попадает):

```properties
storeFile=/home/<user>/.android/svitlo-release.jks
storePassword=...
keyAlias=svitlo
keyPassword=...
```

Если файла нет, APK подписывается debug-ключом.

> ⚠️ Сохрани `svitlo-release.jks` и пароль в надёжном месте (менеджер паролей, бэкап).
> Без этого ключа нельзя выпустить обновление: Android не установит APK с другой подписью поверх старого.

---

## Публикация на GitHub

Workflow [`.github/workflows/release.yml`](.github/workflows/release.yml) собирает подписанные APK и создаёт GitHub Release.

**Один раз** добавить секреты репозитория (Settings → Secrets and variables → Actions):

| Секрет | Значение |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 ~/.android/svitlo-release.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | `storePassword` из `key.properties` |

Или через `gh`:

```bash
base64 -w0 ~/.android/svitlo-release.jks | gh secret set ANDROID_KEYSTORE_BASE64
grep storePassword flutter/android/key.properties | cut -d= -f2- | gh secret set ANDROID_KEYSTORE_PASSWORD
```

**Выпустить релиз:**

```bash
git tag v1.0.1
git push origin v1.0.1
```

Версия приложения берётся из тега (`v1.0.1` → `1.0.1`), номер сборки — из номера запуска Actions.
В релиз попадают `svitlo-<версия>-arm64-v8a.apk` и `svitlo-<версия>-armeabi-v7a.apk`.
Workflow можно запустить и вручную во вкладке Actions: тогда APK будут в артефактах запуска, без релиза.

---

## Установка на телефон

```bash
# Подключить телефон по USB с включённой отладкой по USB
adb install svitlo-flutter.apk
```

Или передать файл `svitlo-flutter.apk` на телефон и установить через файловый менеджер.
На телефоне нужно включить **Установку из неизвестных источников** (Настройки → Безопасность).
