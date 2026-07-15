;; extends
; ~/.config/nvim/after/queries/scss/textobjects.scm
;
; Только то, чего в css нет физически. Всё остальное приезжает по
; `; inherits: css` из стокового scss-файла плюс твоего after/queries/css.
;
; Парсер scss — serenadeai/tree-sitter-scss, отдельная грамматика от css,
; но общие узлы (rule_set, selectors, block, declaration, call_expression)
; называются так же, поэтому css-паттерны на ней компилируются.

; ============================================================================
; @mixin / @function                       -> af / if, ]m / [m
; Вот теперь ]m / [m в scss осмысленны: прыжки по миксинам и функциям.
; ============================================================================
[
  (mixin_statement)
  (function_statement)
] @function.outer

(mixin_statement
  (block
    .
    "{"
    _+ @function.inner
    "}"
    .))

(function_statement
  (block
    .
    "{"
    _+ @function.inner
    "}"
    .))

; ============================================================================
; @if                                      -> ai / ii  (добавляется к @media из css)
; ============================================================================
(if_statement) @conditional.outer

; ============================================================================
; @each / @for / @while                    -> al / il, ]o / [o
; ============================================================================
[
  (each_statement)
  (for_statement)
  (while_statement)
] @loop.outer

; ============================================================================
; @return                                  -> ar / ir
; ============================================================================
(return_statement) @return.outer

(return_statement
  (_) @return.inner)

; ============================================================================
; Параметры миксина/функции                -> aa / ia, ]a / [a
; (css отдаёт @parameter под селекторы — в scss работает и то, и то)
; ============================================================================
(parameters
  (parameter) @parameter.inner @parameter.outer)

; ============================================================================
; swap: параметры и аргументы              -> <leader>a / <leader>A
; ============================================================================
(parameters
  (parameter) @swappable.outer)

(arguments
  (argument) @swappable.outer)
