(local fennel (require :fennel))
(local unpack (or table.unpack _G.unpack))

(local body-specials {"let" true "fn" true "lambda" true "λ" true "when" true
                      "do" true "eval-compiler" true "for" true "each" true
                      "while" true "macro" true "match" true "doto" true
                      "with-open" true "collect" true "icollect" true})

(fn colon-string? [s]
  (and (= :string (type s)) (s:find "^[-%w?\\^_!$%&*+./@:|<=>]+$")))

(fn last-line-length [line] (length (line:match "[^\n]*$")))

(fn line-exceeded? [inspector indent viewed]
  (< inspector.line-length (+ indent (last-line-length viewed))))

(fn view-fn-args [t view inspector indent out callee]
  (if (or (fennel.sym? (. t 2))
          (= :string (type (. t 3))))
      (let [third (view (. t 3) inspector indent)]
        (table.insert out " ")
        (table.insert out third)
        4)
      3))

(fn view-let [bindings view inspector indent]
  (let [out ["["]]
    (var offset 0)
    (for [i 1 (length bindings) 2]
      ;; when a let binding has a comment in it, emit it but don't let it throw
      ;; off the name/value pair counting
      (while (fennel.comment? (. bindings (+ i offset)))
        (table.insert out (view (. bindings (+ i offset))))
        (table.insert out (.. "\n " (string.rep " " indent)))
        (set offset (+ offset 1)))
      (let [i (+ offset i)
            name (view (. bindings i) inspector (+ indent 1))
            indent2 (+ indent 2 (last-line-length name))
            value (view (. bindings (+ i 1)) inspector indent2)]
        (when (<= i (length bindings))
          (table.insert out name)
          (table.insert out " ")
          (table.insert out value)
          (when (< i (- (length bindings) 1))
            (table.insert out (.. "\n " (string.rep " " indent)))))))
    (table.insert out "]")
    (table.concat out)))

(fn view-init-body [t view inspector indent out callee]
  (table.insert out " ")
  (let [indent (+ indent (length callee))
        second (match callee
                 :let (view-let (. t 2) view inspector indent)
                 _ (view (. t 2) inspector indent))]
    (table.insert out second)
    (if (. {:fn true :lambda true :λ true} callee)
        (view-fn-args t view inspector (+ indent (length second)) out callee)
        3)))

(fn match-same-line? [callee i out viewed]
  (and (= :match callee) (= 0 (math.fmod i 2))
       (< (+ (or (string.find viewed "\n") (length viewed)) 1
             (last-line-length (. out (length out)))) 80)))

(fn view-body [t view inspector start-indent out callee]
  (let [start-index (view-init-body t view inspector start-indent out callee)
        indent (if (= callee :do) (+ start-indent 2) start-indent)]
    (for [i start-index (length t)]
      (let [viewed (view (. t i) inspector indent)
            body-indent (+ indent 1 (last-line-length (. out (length out))))]
        (if (match-same-line? callee i out viewed)
            (do (table.insert out " ")
                (table.insert out (view (. t i) inspector body-indent)))
            (do (table.insert out (.. "\n" (string.rep " " indent)))
                (table.insert out viewed)))))))

(fn view-call [t view inspector start-indent out]
  (var indent start-indent)
  (for [i 2 (length t)]
    (table.insert out " ")
    (set indent (+ indent 1))
    (let [viewed (if (and (= :require (tostring (. t 1)))
                          (colon-string? (. t i)))
                     (.. ":" (. t i))
                     (view (. t i) inspector (- indent 1)))]
      (if (and (line-exceeded? inspector indent viewed) (< 2 i))
          (do (when (= " " (. out (length out)))
                (table.remove out))
              (table.insert out (.. "\n" (string.rep " " start-indent)))
              (set indent start-indent)
              (let [viewed2 (view (. t i) inspector indent)]
                (table.insert out viewed2)
                (set indent (+ indent (length viewed2)))))
          (do (table.insert out viewed)
              (set indent (+ indent (length viewed))))))))

(fn list-view [t view inspector indent]
  (let [first-viewed (view (. t 1) inspector (+ indent 1))
        out ["(" first-viewed]]
    (if (. body-specials first-viewed)
        (view-body t view inspector (+ indent 2) out first-viewed)
        (view-call t view inspector (+ indent (length first-viewed) 2) out))
    (table.insert out ")")
    (table.concat out)))

(fn fnlfmt [ast]
  (let [{: __fennelview &as list-mt} (getmetatable (fennel.list))
        ;; override fennelview method for lists!
        _ (set list-mt.__fennelview list-view)
        (ok val) (pcall fennel.view ast {:empty-as-sequence? true})]
    ;; clean up after the metamethod patching
    (set list-mt.__fennelview __fennelview)
    (when (not ok) (error val))
    val))

(fn format-file [filename]
  (let [f (match filename
            :- io.stdin
            _ (assert (io.open filename :r) "File not found."))
        parser (-> (f:read :*all)
                   (fennel.stringStream)
                   (fennel.parser filename {:comments true}))
        out []]
    (f:close)
    (each [ok? value parser]
      (let [formatted (fnlfmt value)
            prev (. out (length out))]
        (if (and (formatted:match "^ *;") prev (string.match prev "^ *;"))
            (table.insert out formatted)
            (table.insert out (.. formatted "\n")))))
    (table.concat out "\n")))

{: fnlfmt : format-file}
