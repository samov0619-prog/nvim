# Spellcheck для Neovim: английский + программистика

Три файла:

- `en.dic` + `en.aff` — база английского (aspell/SCOWL, ~49k слов с affix-правилами: плюрали, суффиксы). Лицензия MIT/BSD.
- `dev-words.txt` — программистский словарь (~27.9k слов): software-terms из cspell + языки (lua, bash, python, css, html, ts, rust, go, docker, k8s, npm…) + супплемент под твой стек (nvim-опции, Wayland/Hyprland, NixOS, фронтенд). Составные на дефисе/подчёркивании разбиты по частям — в тексте они всё равно токенизируются отдельно.

## Установка (рекомендуемый вариант — два языка)

Базовый `en` и программистский `dev` — отдельные скомпилированные словари. Твои личные `zg`-слова копятся отдельно в `en.utf-8.add` и не мешаются с 28k тех-слов.

1. Положить исходники:

```sh
mkdir -p ~/.config/nvim/spell
cp en.dic en.aff dev-words.txt ~/.config/nvim/spell/
```

2. Скомпилировать `.spl` (один раз, из Neovim):

```vim
:mkspell! ~/.config/nvim/spell/en  ~/.config/nvim/spell/en
:mkspell! ~/.config/nvim/spell/ru ~/.config/nvim/spell/ru
:mkspell! ~/.config/nvim/spell/dev ~/.config/nvim/spell/dev-words.txt
```

Первая команда читает `en.dic`+`en.aff` → пишет `en.utf-8.spl`.
Вторая читает плоский список → пишет `dev.utf-8.spl`.
(Исходники `en.dic/en.aff/dev-words.txt` после этого можно удалить — нужны только `.spl`.)

3. Конфиг:

```lua
vim.opt.spelllang    = { "en", "ru", "dev" }
vim.opt.spellfile    = vim.fn.stdpath("config") .. "/spell/en.utf-8.add"  -- личные zg-слова
vim.opt.spelloptions = "camel"   -- FileManager1 -> File + Manager, проверяются по отдельности
```

`camel` разбивает CamelCase/PascalCase. Для «слипшихся» строчными (`relativenumber`) camel не помогает — их закрывает `dev`-словарь.

## Альтернатива (проще, один язык)

Не заводить `dev`-язык, а влить тех-слова в spellfile:

```sh
cp dev-words.txt ~/.config/nvim/spell/en.utf-8.add
```
```vim
:edit ~/.config/nvim/spell/en.utf-8.add
:mkspell! %      " генерит en.utf-8.add.spl
```
Минус: твои будущие `zg`-слова лягут в тот же файл вперемешку с 28k. Работает, но менее чисто.

## Замечания

- Конвенция имени — через ТОЧКИ: `en.utf-8.spl`, не `en_utf-8.spl`. С подчёркиванием Neovim не подхватит файл как язык `en`.
- Обновление `dev.utf-8.spl` после правок `dev-words.txt` — повторить `:mkspell!`.
- Регистр сохранён: `lua` матчит `lua`/`Lua`/`LUA`; `JavaScript` — только `JavaScript`/`JAVASCRIPT` (это правильно).
- Проверяется только там, где treesitter-капча `@spell` (комменты/строки/текст), если у тебя включён ts-хайлайт. Голые идентификаторы в коде не трогаются.

## zg / навигация

- `zg` — добавить слово под курсором как верное (пишется в `en.utf-8.add`)
- `zw` — пометить как ошибочное; `zug`/`zuw` — откат
- `]s` / `[s` — прыжки по ошибкам
- `z=` — список исправлений (это тот самый медленный `spellsuggest`, но по запросу — не на каждый символ)
