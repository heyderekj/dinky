#!/usr/bin/env python3
"""Manual corrections for the worst Russian and Japanese MT outputs.

Apple/macOS conventions, correct verb forms for buttons/toggles, and fixes for
words that Google translated by the wrong sense (Watch->clock, Nice->city, etc.).

Run after `fill_xcstrings_translations.py` and `fix_brand_in_xcstrings.py`.
Idempotent — every override is a fixed value.
"""
import json
from pathlib import Path

CAT = Path(__file__).resolve().parent.parent / "Dinky" / "Localizable.xcstrings"

RU = {
    # Format/brand names — keep Latin
    "AVIF": "AVIF",
    "WebP": "WebP",
    "Spotlight": "Spotlight",
    "-dinky": "-dinky",
    "1920": "1920",
    # Apple/macOS standard terminology
    "Preferences": "Настройки",
    "Settings": "Настройки",
    "Settings…": "Настройки…",
    "OK": "ОК",
    "Done": "Готово",
    "Got it": "Понятно",
    "Nice": "Отлично",
    "Cancel": "Отменить",
    "Choose": "Выбрать",
    "Choose…": "Выбрать…",
    "Cut": "Вырезать",
    "Find": "Найти",
    "Find Next": "Найти далее",
    "Find Previous": "Найти ранее",
    "Print": "Печать",
    "Save": "Сохранить",
    "Save Location": "Место сохранения",
    "Add": "Добавить",
    "Edit": "Редактировать",
    "Delete": "Удалить",
    "Remove": "Убрать",
    "Reset": "Сбросить",
    "Retry": "Повторить",
    "Dismiss": "Закрыть",
    "Install": "Установить",
    "Hide App": "Скрыть приложение",
    "Quit App": "Завершить приложение",
    "New": "Создать",
    "New Tab": "Новая вкладка",
    "Open in New Window": "Открыть в новом окне",
    "Cycle Windows": "Переключение окон",
    "Get Info": "Свойства",
    "Select All": "Выбрать всё",
    "Minimize": "Свернуть",
    "Close Window": "Закрыть окно",
    "Watch": "Наблюдение",
    "Watch a folder": "Наблюдать за папкой",
    "Watch Folder": "Папка наблюдения",
    "Watch this folder": "Наблюдать за этой папкой",
    "Working": "Обработка",
    "Welcome": "Добро пожаловать",
    "Media": "Медиа",
    # Sense fixes
    "Appearance": "Внешний вид",
    "Advanced": "Дополнительно",
    "General": "Основные",
    "All caught up.": "Всё актуально.",
    "Couldn’t phone home.": "Не удалось связаться с сервером.",
    "No size gain": "Размер не уменьшился",
    "No gain": "Без выигрыша",
    "Compressed": "Сжато",
    "Crash diagnostics": "Диагностика сбоев",
    "Crash — Dinky": "Сбой — Dinky",
    "Dinky crashed last time": "В прошлый раз Dinky аварийно завершился",
    "Move to Trash": "Переместить в Корзину",
    "Permanent once the trash is emptied.": "После очистки Корзины — без возможности восстановления.",
    "Stay where they are": "Оставлять на месте",
    "Email Error…": "Сообщить об ошибке по email…",
    "Email Report…": "Отправить отчёт по email…",
    "Email Support…": "Написать в поддержку…",
    "Bug: ": "Ошибка: ",
    "Crash diagnostics from Apple are available for this device. Nothing was sent automatically — use the buttons below if you want to share them.":
        "Для этого устройства доступна диагностика сбоев от Apple. Ничего не отправлено автоматически — используйте кнопки ниже, если хотите поделиться.",
    "Share crash diagnostics with Dinky": "Делиться диагностикой сбоев с Dinky",
    "When on, Apple's MetricKit can deliver anonymous crash and hang diagnostics to Dinky on your Mac. Nothing leaves your device until you choose to send a report. Requires “Share with App Developers” in System Settings → Privacy & Security → Analytics & Improvements.":
        "Когда включено, MetricKit от Apple может анонимно передавать диагностику сбоев и зависаний приложению Dinky на вашем Mac. Ничего не покидает устройство, пока вы сами не отправите отчёт. Требуется параметр «Делиться с разработчиками приложений» в «Системные настройки → Конфиденциальность и безопасность → Аналитика и улучшения».",
    # Toggles/checkboxes — imperfective for ongoing behaviour
    "Open Dinky at login": "Открывать Dinky при входе в систему",
    "Open folder when done": "Открывать папку по завершении",
    "Open the folder when finished": "Открывать папку по завершении",
    "Notify when done": "Уведомлять по завершении",
    "Play sound when done": "Воспроизводить звук по завершении",
    "Auto-clear queue when done": "Автоматически очищать очередь по завершении",
    "Reduce motion": "Уменьшать анимацию",
    "Sanitize filenames": "Нормализовать имена файлов",
    "Strip audio track": "Удалять аудиодорожку",
    "Strip metadata": "Удалять метаданные",
    "Preserve original timestamps": "Сохранять исходные временные метки",
    "Preserve text & links": "Сохранять текст и ссылки",
    "Tune compression from content": "Настраивать сжатие по содержимому",
    "Use simple sidebar": "Использовать простую боковую панель",
    "Skip if savings below": "Пропускать, если экономия ниже",
    "Replace original": "Заменять оригинал",
    "Append \"-dinky\" suffix": "Добавлять суффикс «-dinky»",
    "Sections you turn off stay available in Settings and in the full sidebar.":
        "Разделы, которые вы отключите, остаются доступными в настройках и на полной боковой панели.",
    # Sidebar/help
    "History": "История",
    "History…": "История…",
    # Footnote with phantom RTL char
    "No folder set — configure in Presets": "Папка не задана — настройте в разделе «Пресеты»",
    # Watch
    "Edit global watch folder…": "Изменить глобальную папку наблюдения…",
    "Global watch folder…": "Глобальная папка наблюдения…",
    "Use global watch": "Использовать глобальное наблюдение",
    "Global watch — choose folder in Watch tab": "Глобальное наблюдение — выберите папку на вкладке «Наблюдение»",
    "Watch folders use this preset only for matching file types. Other files use the global sidebar settings.":
        "Папки наблюдения используют этот пресет только для подходящих типов файлов. Остальные используют общие настройки боковой панели.",
    # Misc
    "Compression in progress": "Идёт сжатие",
    "Compressing…": "Сжатие…",
    "Loving Dinky? Leave a review": "Нравится Dinky? Оставьте отзыв",
    "You’re on Dinky %@ — the latest and dinkyest.":
        "У вас Dinky %@ — самая последняя и самая dinky-версия.",
    "Version %@ is out. You’re on %@. Want it?":
        "Доступна версия %@. У вас %@. Установить?",
    "Maybe later": "Может, позже",
    "Total saved": "Всего сэкономлено",
    "Reset total saved statistics…": "Сбросить общую статистику экономии…",
    "Reset the running total of bytes saved across all sessions?":
        "Сбросить общий счётчик сэкономленных байтов за все сеансы?",
    "Clears the running total shown in History. Session history is unchanged — clear that from the History window.":
        "Очищает общий счётчик, показанный в окне «История». Список сеансов не меняется — очистите его в самом окне «История».",
    "This does not clear the per-session list in History.":
        "При этом список сеансов в «Истории» не очищается.",
    # PDF compression labels
    "Compress at High": "Сжать с высоким качеством",
    "Compress at Medium": "Сжать со средним качеством",
    "Compress at Low": "Сжать с низким качеством",
    "Re-compress at High": "Пересжать с высоким качеством",
    "Re-compress at Medium": "Пересжать со средним качеством",
    "Re-compress at Low": "Пересжать с низким качеством",
    # Help-menu line
    "Dinky Help": "Справка Dinky",
    "Crash report — Dinky": "Отчёт о сбое — Dinky",
    "Feedback — Dinky v%@": "Отзыв — Dinky v%@",
    "Support — Dinky v%@": "Поддержка — Dinky v%@",
    "Visit dinkyfiles.com": "Перейти на dinkyfiles.com",
    "Give Feedback…": "Отправить отзыв…",
    "Check for Updates…": "Проверить обновления…",
    "Leave a Review…": "Оставить отзыв…",
    "Report a Bug…": "Сообщить об ошибке…",
}

JA = {
    # Format/brand names — keep Latin
    "AVIF": "AVIF",
    "WebP": "WebP",
    "Spotlight": "Spotlight",
    "-dinky": "-dinky",
    "1920": "1920",
    # macOS conventions
    "Preferences": "設定",
    "OK": "OK",
    "Done": "完了",
    "Nice": "OK",
    "Got it": "了解",
    "Cancel": "キャンセル",
    "Choose": "選択",
    "Choose…": "選択…",
    "Cut": "切り取り",
    "Find": "検索",
    "Find Next": "次を検索",
    "Find Previous": "前を検索",
    "Print": "プリント",
    "Save": "保存",
    "Save Location": "保存場所",
    "Add": "追加",
    "Edit": "編集",
    "Delete": "削除",
    "Remove": "取り除く",
    "Reset": "リセット",
    "Retry": "再試行",
    "Dismiss": "閉じる",
    "Install": "インストール",
    "Hide App": "アプリを非表示",
    "Quit App": "アプリを終了",
    "Cycle Windows": "ウインドウを切り替える",
    "Get Info": "情報を見る",
    "Open Files…": "ファイルを開く…",
    # Sense / wrong word
    "Watch": "監視",
    "Watch a folder": "フォルダを監視する",
    "Watch Folder": "監視フォルダ",
    "Watch this folder": "このフォルダを監視する",
    "Edit global watch folder…": "グローバル監視フォルダを編集…",
    "Global watch folder…": "グローバル監視フォルダ…",
    "Use global watch": "グローバル監視を使用する",
    "Welcome": "ようこそ",
    "Working": "処理中",
    "History": "履歴",
    "History…": "履歴…",
    # Crash terminology
    "Dinky crashed last time": "前回 Dinky がクラッシュしました",
    "Crash diagnostics": "クラッシュ診断",
    "Crash — Dinky": "クラッシュ — Dinky",
    # Email-action verbs
    "Email Error…": "エラーをメール送信…",
    "Email Report…": "レポートをメール送信…",
    "Email Support…": "サポートにメールを送る…",
    "Visit dinkyfiles.com": "dinkyfiles.com を開く",
    "Give Feedback…": "フィードバックを送信…",
    "Check for Updates…": "アップデートを確認…",
    "Couldn’t phone home.": "サーバーに接続できませんでした。",
    "All caught up.": "すべて最新です。",
    "Bug: ": "バグ: ",
    # Numeric/size/state
    "No size gain": "サイズが減りませんでした",
    "No gain": "削減なし",
    "Compressed": "圧縮済み",
    "Total saved": "合計節約サイズ",
    "Reset total saved statistics…": "節約量の合計をリセット…",
    # Toggle / settings labels
    "Open Dinky at login": "ログイン時に Dinky を開く",
    "Open folder when done": "完了したらフォルダを開く",
    "Open the folder when finished": "完了したらフォルダを開く",
    "Notify when done": "完了したら通知する",
    "Play sound when done": "完了時にサウンドを鳴らす",
    "Auto-clear queue when done": "完了時にキューを自動クリア",
    "Reduce motion": "視差効果を減らす",
    "Sanitize filenames": "ファイル名を整える",
    "Strip audio track": "オーディオトラックを削除",
    "Strip metadata": "メタデータを削除",
    "Replace original": "オリジナルを置き換える",
    "Append \"-dinky\" suffix": "「-dinky」サフィックスを追加",
    "Use simple sidebar": "シンプルなサイドバーを使用",
    "Stay where they are": "そのままにする",
    "Move to Backup folder": "バックアップフォルダに移動",
    "Move to Trash": "ゴミ箱に入れる",
    "Permanent once the trash is emptied.": "ゴミ箱を空にすると元に戻せません。",
    # PDF compress phrasing
    "Compress at High": "高で圧縮",
    "Compress at Medium": "中で圧縮",
    "Compress at Low": "低で圧縮",
    "Re-compress at High": "高で再圧縮",
    "Re-compress at Medium": "中で再圧縮",
    "Re-compress at Low": "低で再圧縮",
    # Help/window
    "Dinky Help": "Dinky ヘルプ",
    "Crash report — Dinky": "クラッシュレポート — Dinky",
    "Feedback — Dinky v%@": "フィードバック — Dinky v%@",
    "Support — Dinky v%@": "サポート — Dinky v%@",
    "Loving Dinky? Leave a review": "Dinky を気に入っていただけましたか? レビューを書く",
    "You’re on Dinky %@ — the latest and dinkyest.":
        "Dinky %@ をご利用中です — 最新かつ最も dinky なバージョンです。",
    "Version %@ is out. You’re on %@. Want it?":
        "バージョン %@ が公開されました。現在は %@ です。インストールしますか?",
    "Maybe later": "後で",
    # Smart quality
    "Sections you turn off stay available in Settings and in the full sidebar.":
        "オフにしたセクションは「設定」と完全なサイドバーから引き続き利用できます。",
    "Tune compression from content": "コンテンツから圧縮を調整する",
    "Skip if savings below": "節約が下回ったらスキップ",
    "Force compress even if savings are minimal": "節約が最小限でも強制的に圧縮する",
    # Crash sheet
    "Crash diagnostics from Apple are available for this device. Nothing was sent automatically — use the buttons below if you want to share them.":
        "このデバイスで Apple のクラッシュ診断が利用できます。何も自動送信されません — 共有したい場合は下のボタンを使ってください。",
    "Share crash diagnostics with Dinky": "クラッシュ診断を Dinky と共有",
}


def main():
    data = json.loads(CAT.read_text())
    fixes = 0
    for lang, table in (("ru", RU), ("ja", JA)):
        for key, value in table.items():
            entry = data["strings"].get(key)
            if entry is None:
                print(f"  [skip] {lang} key not found: {key!r}")
                continue
            locs = entry.setdefault("localizations", {})
            payload = locs.setdefault(lang, {"stringUnit": {"state": "translated", "value": ""}})
            su = payload.setdefault("stringUnit", {"state": "translated", "value": ""})
            if su.get("value") != value:
                old = su.get("value", "")
                su["value"] = value
                su["state"] = "translated"
                fixes += 1
                print(f"  [{lang}] {key!r}\n    - {old!r}\n    + {value!r}")
    CAT.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    print(f"\nApplied {fixes} corrections.")


if __name__ == "__main__":
    main()
