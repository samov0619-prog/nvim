;; extends
; ~/.config/nvim/after/queries/ecma/textobjects.scm
;
; ЕДИНСТВЕННЫЙ файл. Наследование апстрима разносит его по всем нужным языкам:
;   javascript : ; inherits: ecma,jsx
;   typescript : ; inherits: ecma
;   tsx        : ; inherits: typescript,jsx
;   jsx        : ; inherits: ecma
; Поэтому after/queries/{javascript,typescript,tsx,jsx}/textobjects.scm — УДАЛИТЬ.
; Дубли не дедуплицируются: одинаковый паттерн в 5 файлах = 5 совпадений на узел.
;
; ВАЖНО: строка `;; extends` обязана быть до первой не-';' строки.
; Без неё nvim молча выбрасывает файл целиком (стоковый уже занял роль базы).

; ============================================================================
; Объектный литерал
; ============================================================================
(object) @obj.outer

; inner через quantified capture (_+), а НЕ через #make-range! —
; на ветке main апстрим от директивы отказался, а в ядре хендлера для неё нет.
(object
  .
  "{"
  _+ @obj.inner
  "}"
  .)

; ============================================================================
; Элемент массива — для ]e / [e
; (_) матчит только именованные узлы, запятые не попадут.
; ============================================================================
(array
  (_) @elem.outer)

; УБРАНО из твоего набора:
;   (object) @obj.inner        — был копией @obj.outer, скобки не срезались
;   (array (_) @elem.inner)    — то же самое, копия @elem.outer
;   @obj_in_array.*            — подмножество @obj.outer; объекты в массивах
;                                и так ловит @elem.outer
;   @obj.value                 — это просто (object), его ловит @obj.outer

; ============================================================================
; @swappable.outer — всё, что осмысленно менять местами с соседом.
; Читается smart_swap'ом. Захваты под общим родителем -> swap видит их
; как соседей.
; ============================================================================

; свойства объекта: { a: 1, b: 2 } -> pair / shorthand / spread / метод
(object
  (_) @swappable.outer)

; элементы массива: [a, b, c]
(array
  (_) @swappable.outer)

; поля и методы класса
(class_body
  (_) @swappable.outer)

; ветки тернарника: cond ? A : B
; оба захвата в ОДНОМ паттерне и под общим родителем
(ternary_expression
  consequence: (_) @swappable.outer
  alternative: (_) @swappable.outer)

; JSX-пропсы сюда НЕ нужны: стоковый queries/jsx/textobjects.scm уже даёт
;   (jsx_attribute) @attribute.outer
; а javascript/tsx наследуют jsx. В swap_candidates он идёт отдельной строкой.
