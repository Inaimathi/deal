(in-package #:deal)

(proclaim '(inline sym->keyword))

;;;;; Simple anaphorics/custom flow control constructs
(defmacro aif (test-form then-form &optional else-form)
  `(let ((it ,test-form))
     (if it ,then-form ,else-form)))

(defmacro awhen (test-form &body then-form)
  `(aif ,test-form (progn ,@then-form)))

(defmacro if-up (thing up down)
  `(if (eq :up (face ,thing))
       ,up
       ,down))

;;;;; Basic macros
(defmacro with-gensyms ((&rest names) &body body)
  `(let ,(loop for n in names collect `(,n (gensym)))
     ,@body))

(defmacro set-props (target &rest props)
  (assert (every #'symbolp props))
  (with-gensyms (tgt)
    `(let ((,tgt ,target))
       (setf ,@(loop for p in props
		  collect `(,p ,tgt)
		  collect p)))))

;;;;; Basic functions
(defun hash-keys (hash-table)
  (loop for key being the hash-keys of hash-table collect key))

(defun hash-values (hash-table)
  (loop for val being the hash-values of hash-table collect val))

(defun hash-map (fn hash-table)
  (loop for key being the hash-keys of hash-table
     collect (funcall fn key (gethash key hash-table))))

(defun pick (a-list)
  "Randomly selects an element from the given list with equal probability."
  (nth (random (length a-list)) a-list))

(defun shuffle (a-list)
  "Returns a randomly sorted copy of the given list"
  (let ((l (copy-seq a-list)))
    (sort l #'> :key (lambda (n) (declare (ignore n)) (random 1.0)))))

(defun take (count a-list)
  (loop for elem in a-list repeat count
     collect elem))

(defun drop (count a-list)
  (loop for (elem . rest) on a-list repeat (- count 1)
     finally (return rest)))

(defun make-id () (sym->keyword (gensym)))

(defun sym->keyword (symbol)
  (intern (symbol-name symbol) :keyword))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;; All for the custom define-handler
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun type-expression (arg type)
  "Given a symbol name and a type, returns the expression to read that type from a string"
  (match type
    (:string 
     nil)
    (:int 
     `(parse-integer ,arg :junk-allowed t))
    (:json 
     `(decode-json-from-string ,arg))
    ((or :keyword :facing)
     `(intern (string-upcase ,arg) :keyword))
    (:table 
     (lookup-expression arg '(private-tables *server*) '(public-tables *server*)))
    ((list :list _)
     `(loop for elem in (decode-json-from-string ,arg)
	 collect (gethash elem (things table))))
    ((or :stack :flippable :placeable
	 (list :card :from-table))
     (lookup-expression arg '(things table)))
    ((list :card :from-hand)
     (lookup-expression arg '(hand *player*)))
    (_ (error "Invalid type label: '~a'" type))))

(defun lookup-expression (arg &rest places)
  (with-gensyms (sym)
    `(let ((,sym (intern (string-upcase ,arg) :keyword)))
       (or ,@(loop for p in places
		collect `(gethash ,sym ,p))))))

(defun lookup-assertion (arg type)
  (match type
    (:table `(assert (typep ,arg 'table)))
    (:stack `(assert (typep ,arg 'stack)))
    (:facing `(assert (or (eq ,arg :up) (eq ,arg :down))))
    (:placeable `(assert (typep ,arg 'placeable)))
    (:flippable `(assert (typep ,arg 'flippable)))
    ((list :card _) `(assert (typep ,arg 'card)))
    ((list :list lst-type)
     `(assert (every (lambda (a) (typep a ',lst-type)) ,arg)))
    (_ nil)))

(defun type-pieces (args)
  "Takes a list of arguments and returns three values:
- The conversion expressions
- The names (for use as final args)
- The lookup assertions"
  (loop for (name type) in args
     for table? = (eq type :table)
     for t-exp = (type-expression name type)
     for assn = (lookup-assertion name type)
     collect name into arguments 
     if table? collect (list name t-exp) into table-lookups and collect assn into table-assertions
     when (and (not table?) t-exp) collect (list name t-exp) into type-expressions
     when (and (not table?) assn) collect it into assertions
     finally (return (values arguments table-lookups table-assertions type-expressions assertions))))

(defmacro define-handler ((name) (&rest args) &body body)
  "Defines handlers with an eye for self-documentation, DRY and portability"
  (let* ((uri (concatenate 'string "/" (string-downcase (symbol-name name)))) 
	 (opts `(,name :uri ,uri)))
    (multiple-value-bind (final-args table-lookups table-assertions type-conversions lookup-assertions) (type-pieces args)
      `(progn
	 (setf (gethash ,uri *handlers*) '(,@args))
	 ,(if (not args)
	      `(define-easy-handler ,opts nil (encode-json-to-string (progn ,@body)))
	      (if (and (listp (car body)) (eq (caar body) 'with-table-lock) table-lookups)
		  `(define-easy-handler ,opts ,final-args
		     (assert (and ,@final-args))
		     (let* ,table-lookups
		       ,@table-assertions
		       (with-lock-held ((lock ,(caar table-lookups)))
			 (let* ,type-conversions
			   ,@lookup-assertions
			   (encode-json-to-string (progn ,@(cdar body)))))
		       ,@(cdr body)))
		  `(define-easy-handler ,opts ,final-args
		     (assert (and ,@final-args))
		     (let* ,(append table-lookups type-conversions)
		       ,@(append table-assertions lookup-assertions)
		       (encode-json-to-string ,@body)))))))))

(defmacro define-sse-handler ((name) (&rest args) &body body)
  `(define-handler (,name) (,@args)
     (setf (header-out :cache-control) "no-cache"
	   (content-type*) "text/event-stream")
     ,@body))