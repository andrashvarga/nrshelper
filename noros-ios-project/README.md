# Noros Helper для iPhone (нативное приложение)

Оболочка на WKWebView: интерфейс лежит внутри приложения (работает офлайн), а нативный мост даёт
открытие внешних ссылок и Telegram, сохранение/отправку файлов (PDF, HTML, скриншоты) через системное меню
и смену иконки приложения (Noros / Valutix / RioPay).

## Вариант А. Есть Mac с Xcode (проще всего)
1. `brew install xcodegen`, затем в папке проекта: `xcodegen generate`
2. Откройте `NorosHelper.xcodeproj`, в Signing & Capabilities выберите свою Team (Apple ID).
3. Подключите iPhone → Run. Для TestFlight: Product → Archive → Distribute App → App Store Connect.

## Вариант Б. Без Mac — облачная сборка (GitHub Actions)
1. Создайте приватный репозиторий на GitHub и загрузите туда содержимое этой папки.
2. Вкладка Actions → «Build iOS» → Run workflow. Через несколько минут появится артефакт `NorosHelper-unsigned.ipa`.
3. Установка:
   - **Бесплатный Apple ID:** Sideloadly или AltStore подписывают .ipa вашим Apple ID (действует 7 дней, потом переустановка).
   - **Платный Apple Developer ($99/год):** подпишите сборку (Xcode/Transporter) и загрузите в TestFlight.

## Ограничения iOS
- Название под иконкой на iOS не меняется (всегда «Noros Helper»); меняется только картинка иконки.
- При смене иконки iOS показывает системное окно «Вы изменили иконку».
- Bundle ID: `com.noros.helper` (при необходимости поменяйте в project.yml).
- Иконки получены увеличением 192-px исходников; для публикации в App Store пришлите 1024-px версии.
