; textobjects.scm — js/ts/tsx
; ---- objects anywhere ----
(object) @obj.outer
(object) @obj.inner

; ---- objects that are direct children of an array (array of objects) ----
(array (object) @obj_in_array.outer)
(array (object) @obj_in_array.inner)

; ---- any array element (element may be object/array/string/number/call_expression/identifier/..) ----
; (_ ) matches any node, but (_) matches any *named* node — используем (_) чтобы поймать именованные элементы.
(array (_) @elem.outer)
(array (_) @elem.inner)

; ---- bonus: capture objects that are values in property pairs (useful for object properties) ----
(pair value: (object) @obj.value)
