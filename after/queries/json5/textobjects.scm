;; extends
; ~/.config/nvim/after/queries/json5/textobjects.scm
;
; json5 — самостоятельный парсер (Joakker/tree-sitter-json5), НЕ алиас json.
; Имена узлов отличаются, скопировать json-файл нельзя:
;
;   json   : (pair   key:  (_) value: (_))   корень (document)
;   json5  : (member name: (_) value: (_))   корень (file)
;
; Общее подмножество — только (object) и (array). Именно поэтому твоя
; копия json-файла тут частично выживала.
;
; `;; extends` здесь не обязателен (стоковых textobjects для json5 в
; апстриме нет, файл сам стал бы базой), но безвреден и защищает на случай,
; если апстрим их однажды добавит.

(object) @obj.outer
(object) @block.outer

(object
  .
  "{"
  _+ @obj.inner
  "}"
  .)

(object
  .
  "{"
  _+ @block.inner
  "}"
  .)

(array
  (_) @elem.outer)

; member вместо pair, name: вместо key:
(object
  (member
    name: (_) @assignment.lhs
    value: (_) @assignment.inner @assignment.rhs) @assignment.outer)

(object
  (member) @swappable.outer)

(array
  (_) @swappable.outer)
