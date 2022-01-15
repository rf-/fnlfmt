(local fennel (require :fennel))

(set debug.traceback fennel.traceback)

(local {: format-file : version} (require :fnlfmt))

(fn help []
  (print "Usage: fnlfmt [--no-comments] [--fn-forms FORM1,FORM2...] [--body-forms FORM1,FORM2...] [--fix] FILENAME")
  (print "With the --fix argument, updates the file in-place; otherwise")
  (print "prints the formatted file to stdout."))

(local options {:body-forms {} :fn-forms {}})

(fn consume-array-option [flag-index]
  (let [raw-values (. arg (+ flag-index 1))
        values-table (collect [val (string.gmatch raw-values "[^,]+")]
                       (values val true))]
    (table.remove arg (+ flag-index 1))
    (table.remove arg flag-index)
    values-table))

(for [i (length arg) 1 -1]
  (when (= :--no-comments (. arg i))
    (set options.no-comments true)
    (table.remove arg i))
  (when (= :--body-forms (. arg i))
    (set options.body-forms (consume-array-option i)))
  (when (= :--fn-forms (. arg i))
    (set options.fn-forms (consume-array-option i))))

(match arg
  [:--version] (print (.. "fnlfmt version " version))
  [:--fix filename nil] (let [new (format-file filename options)
                              f (assert (io.open filename :w))]
                          (f:write new)
                          (f:close))
  [filename nil] (print (format-file filename options))
  _ (help))
