# Copypastik Roadmap

Останнє оновлення: 2026-10-22

Цей roadmap фіксує напрямок для версій 1.3 та 1.4. Ідея 1.3 — зробити Copypastik швидшою “памʼяттю контексту”, а 1.4 залишити для більших workflow-фіч, які можуть розширити застосунок за межі компактного clipboard picker.

## Copypastik 1.3 — Smart Recall

**Статус: implemented (2026-07-01).** Основний scope (source app + `@app`, type filter chips + `type:`, pinned clips, Quick Slots 1–9, privacy controls, unified search parser) реалізовано. OCR stretch goal не брали в цей реліз — залишається кандидатом для 1.4 (див. нижче), як і зазначалось у "Не беремо в 1.3".

### Концепція

Знайти за застосунком, типом або тегом. Закріпити один раз — вставляти одним натисканням.

### Product goal

Copypastik 1.3 має зробити пошук і повторне використання clips значно швидшим. Користувач часто памʼятає не точний текст, а контекст: з якого застосунку він його копіював, який це був тип контенту, або що це був “той самий постійний snippet”.

### Основний scope

#### 1. Source App для clips

Зберігати застосунок, з якого прийшов clip.

Потрібно:

- показувати app icon у картці clip;
- додати підпис на кшталт `Safari · 2 min ago`;
- підтримати пошук через `@Safari`;
- додати фільтр за застосунком;
- врахувати source app у результатах пошуку.

Це одна з найцінніших ідей з Supaste: пошук за джерелом часто природніший, ніж пошук за точним текстом.

#### 2. Type Filter Chips

Додати компактні chips у picker:

- All;
- Text;
- Links;
- Images;
- Code;
- Commands.

Пошуковий синтаксис:

- `type:image`;
- `type:link`;
- `type:code`;
- `type:command`;
- `#design`;
- `@Safari`;
- комбіновані запити на кшталт `@Xcode type:code` або `type:image #design`.

Частина визначення типів уже існує в picker як presentation logic, тому для 1.3 варто перетворити це на повноцінну фільтрацію.

#### 3. Pinned Clips

Додати можливість закріплювати clips без необхідності створювати tag.

Потрібно:

- `⌘P` у picker для pin/unpin selected item;
- pinned clips завжди показуються зверху;
- pinned clips зберігаються між запусками;
- pinned clips мають помітний badge або icon;
- pinned clips можуть бути призначені в Quick Slots 1–9.

Pinned clips мають відчуватись як “улюблені snippets”, але без зайвої організаційної роботи.

#### 4. Quick Slots 1–9

Headline-фіча релізу 1.3.

Потрібно:

- дозволити користувачу призначити pinned clip у слот 1–9;
- показувати номер слота прямо на картці;
- `Control + Option + 1…9` вставляє відповідний pinned clip;
- порядок слотів не змінюється автоматично;
- якщо слот порожній, показувати мʼяку підказку або відкривати picker.

Це краще, ніж автоматичні “останні 10 clips”, бо користувач сам контролює гарячі вставки й може довіряти shortcutʼам.

#### 5. Privacy Controls

Підсилити local-first позиціонування реальними privacy-контролами.

Потрібно:

- Pause capture на 5 хв;
- Pause capture на 30 хв;
- Pause capture до ручного ввімкнення;
- ignored apps list;
- дефолтний захист для Passwords, 1Password, Keychain-подібних застосунків;
- індикатор паузи в menu bar;
- зрозумілий статус, наприклад `Capture paused · 23 min left`.

Clipboard apps потребують довіри. Privacy Controls мають бути видимою частиною UX, а не прихованим налаштуванням.

### Stretch goal для 1.3

#### Local OCR для зображень

Через Apple Vision, без хмари.

Можливості:

- текст зі screenshots/images потрапляє в пошук;
- можна скопіювати розпізнаний текст;
- tagged screenshots залишаються searchable;
- OCR працює локально;
- користувач може вимкнути OCR, якщо не хоче додаткової обробки images.

OCR сильний, але може помітно збільшити обсяг 1.3. Якщо він почне роздувати реліз, його варто перенести в 1.4.

### Не беремо в 1.3

- Notch shelf — ефектно, але не універсально й трохи суперечить компактності Copypastik.
- Inline abbreviations на кшталт `;welcome` — потребують глибшого keyboard monitoring і більшої довіри користувача.
- Reminders — clipboard починає перетворюватися на task manager.
- Повноцінна Library, OCR, image editor і bulk actions одночасно — це вже радше scope 1.4–2.0.

### Фінальний набір 1.3

- Source app + `@app` search.
- Type filter chips.
- Pinned clips.
- Quick Slots 1–9.
- Pause capture + ignored apps.
- OCR — тільки якщо залишиться ресурс.

### Suggested implementation order

1. Data model: додати source app metadata, pin state, slot number.
2. Persistence: зберігати pinned clips і quick slots між запусками.
3. Capture layer: визначати frontmost/source app під час нового clip.
4. Search parser: підтримати `@app`, `type:`, `#tag`.
5. Picker UI: app icon, source label, type chips, pinned section, slot number.
6. Shortcuts: `⌘P`, `Control + Option + 1…9`.
7. Privacy settings: pause capture, ignored apps, default sensitive apps.
8. Polish: empty states, hints, menu bar pause indicator.
9. Stretch: local OCR через Apple Vision.

## Copypastik 1.4 — Power Library / Workflow Layer

**Статус: implemented (2026-10-22), крім пунктів, позначених deferred нижче.** Реалізовано: Library window, локальний OCR, bulk actions, drag & drop з Library, Smart Transformations. Відкладено: archive mode, OCR language settings, export selected, drag з picker, grouping by app, Inline Abbreviations, Notch Shelf.

### Концепція

Більше контролю над великою історією, медіа та повторюваними робочими потоками.

Частину фіч можна було перенести, відкласти або взагалі не реалізовувати, якщо вони розмиватимуть компактність Copypastik — тому нижче для кожного пункту зафіксовано, що саме зроблено, а що відкладено.

### Candidate scope

#### 1. Full Library

**Implemented.** Окреме вікно (`Open Library` у menu bar, `⌃⌥L`, `⌘L` у picker), sidebar All Clips / Pinned / Apps / Types / Tags, групування за датою (Pinned / Today / Yesterday / Previous 7 Days / Earlier), richer previews, detail panel, той самий search parser (`#tag`, `@app`, `type:`), bounded локальна персистенція історії (налаштування "Keep History Between Launches", ліміт до 500). **Deferred:** архівний режим для старих clips; grouping by app у списку (є фільтр Apps у sidebar).

Початковий опис:

Можливості:

- більший layout, ніж picker;
- sidebar з Apps, Types, Tags, Pinned;
- grouping by date/app;
- richer previews для images, links, code;
- batch select;
- bulk delete/tag/pin;
- архівний режим для старих clips.

Library має бути не заміною picker, а “важчим режимом” для організації.

#### 2. OCR як повноцінна фіча

**Implemented** (Apple Vision, on-device): searchable screenshots у Library і picker, Copy Recognized Text, стан "Recognizing text…", перемикач "Recognize Text in Images". **Deferred:** налаштування мов (використовуються системні значення за замовчуванням), прогрес-індикатор понад discreet-статус.

Якщо OCR не потрапить у 1.3, у 1.4 він може стати центральною фічею.

Можливості:

- searchable screenshots;
- copy recognized text;
- OCR status/progress;
- налаштування мов, якщо це буде потрібно;
- можливість вимкнути OCR для privacy/performance.

#### 3. Bulk Actions

**Implemented** (тільки в Library): multi-select (click / Shift / Command), Copy Selected (текстові clips через новий рядок, зображення пропускаються), Delete з підтвердженням (pinned зберігаються, якщо не обрано "Delete Everywhere"), bulk tag add/remove, bulk pin/unpin. **Deferred:** export selected clips.

Можливості:

- multi-select;
- bulk copy;
- bulk delete;
- bulk tag;
- bulk pin/unpin;
- export selected clips як майбутній extension point.

Bulk actions логічніше додавати разом із Full Library, а не перевантажувати compact picker.

#### 4. Drag & Drop

**Implemented** для Library: текст як plain text, посилання як URL + текст, зображення як PNG (data + file). **Deferred:** drag із compact picker; drag pinned snippets/OCR-тексту окремо від рядка clip.

Можливості:

- drag text/image clip з picker або library;
- drop images у Figma, Slack, Notes тощо;
- drag pinned snippets;
- drag recognized OCR text.

Ця фіча може зробити Copypastik кориснішим для дизайнерів і контент-команд, але потребує акуратного macOS UX.

#### 5. Smart Transformations

**Implemented** у контекстному меню Library та панелі деталей: усі перелічені нижче перетворення, non-destructive, результат копіюється в clipboard без додавання в історію.

Дії перед вставкою або з контекстного меню.

Можливості:

- paste as plain text;
- trim whitespace;
- lowercase/uppercase;
- pretty JSON;
- URL decode/encode;
- remove tracking params;
- copy domain from URL;
- normalize line breaks.

Це добре пасує до характеру Copypastik: маленькі практичні магії без перетворення app у монстра.

#### 6. Inline Abbreviations як experimental

**Deferred (не в 1.4 за рішенням scope).**

Скорочення на кшталт `;welcome`, які розгортаються в готовий текст.

Ризики:

- глибший keyboard monitoring;
- більше permission friction;
- можливі конфлікти з іншими apps;
- більше питань довіри й privacy.

Якщо брати цю фічу, краще запускати як optional Labs/Experimental feature.

#### 7. Notch Shelf / Shelf UI

**Deferred.** Низький пріоритет.

Фіча виглядає ефектно, але не обовʼязково відповідає компактному характеру Copypastik. Варто повертатись до неї тільки якщо буде окремий візуальний напрямок або чіткий use case.

### Фінальний набір 1.4

- Full Library — implemented.
- OCR — implemented (не потрапив у 1.3).
- Bulk actions — implemented.
- Drag & drop — implemented для Library.
- Smart transformations — implemented.
- Experimental inline abbreviations — deferred, тільки після окремого рішення.

## Release positioning

### 1.3 Smart Recall

Фокус: швидко знайти й повторно вставити потрібний clip.

Ключова обіцянка:

> Copypastik remembers not only what you copied, but where it came from and how you reuse it.

### 1.4 Power Library

Фокус: організація, bulk workflows і робота з великою історією.

Ключова обіцянка:

> Turn clipboard history into a searchable, manageable workspace.

## Product principle

Copypastik має залишатися компактним, швидким і local-first. Кожна нова фіча має відповідати хоча б одному з трьох критеріїв:

- швидше знайти потрібний clip;
- безпечніше контролювати, що зберігається;
- швидше вставити або повторно використати важливий content.

Якщо фіча не проходить цей фільтр, її краще залишити для Labs або не брати в roadmap.
