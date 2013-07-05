(in-package :deal)

(defclass table ()
  ((id :reader id :initform (intern (symbol-name (gensym)) :keyword))
   (started :reader started :initform (get-universal-time))
   (players :accessor players :initform nil)
   (things :accessor things :initform (make-hash-table))
   (passphrase :accessor passphrase :initform nil :initarg :passphrase)
   (tablecloth :accessor tablecloth :initform nil :initarg :tablecloth)
   (current-player :accessor current-player :initform nil)
   (events :accessor events :initform nil)
   (lock :accessor lock :initform (make-lock))))

;;;;;;;;;; Game elements
(defclass placeable ()
  ((id :reader id :initform (intern (symbol-name (gensym)) :keyword))
   (x :accessor x :initform 0 :initarg :x)
   (y :accessor y :initform 0 :initarg :y)
   (z :accessor z :initform 0 :initarg :z)
   (rot :accessor rot :initform 0 :initarg :rot)
   (belongs-to :accessor belongs-to :initarg :belongs-to)))

(defclass flippable (placeable)
  ((face :accessor face :initform :up :initarg :face)))

(defclass card (flippable)
  ((content :accessor content :initarg :content)
   (card-type :accessor card-type :initarg :card-type)))

(defclass stack (flippable)
  ((cards :accessor cards :initform nil :initarg :cards)
   (card-count :accessor card-count :initform 0 :initarg :card-count)
   (face :initform :down)))

(defclass counter (placeable)
  ((counter-value :accessor counter-value :initarg :counter-value)))

(defclass mini (placeable)
  ((sprite :accessor sprite :initarg :sprite)))

(defun deck->stack (player a-deck &key (face :down))
  "Takes a deck (a list of card texts) and creates a stack (a pile of cards suitable for placing on a table)"
  (make-instance 'stack
		 :face face
		 :belongs-to (id player)
		 :card-count (length (rest a-deck))
		 :cards (shuffle (loop for c in (rest a-deck)
				    collect (make-instance 
					     'card :content c :face face 
					     :card-type (first a-deck) :belongs-to (id player))))))

;;;;;;;;;; delete/insert methods (more in model/server.lisp)
(defmethod delete! ((table table) (thing placeable))
  "Removes a thing from the given table"
  (remhash (id thing) things))

(defmethod insert! ((table table) (thing placeable))
  "Places a new thing on the given table."
  (setf (gethash (id thing) (things table)) thing))

(defmethod insert! ((stack stack) (card card))
  "Inserts the given card into the given stack."
  (push card (cards stack)))

;;;;;;;;;; Redact methods
(defmethod redact ((table table))
  `((type . table)
    (tablecloth . ,(tablecloth table)) 
    (things . ,(hash-map (lambda (k v) (declare (ignore k)) (redact v))
			 (things table)))
    (players . ,(mapcar (lambda (p) `((id . ,(id p)) (hand . ,(hash-table-count (hand p))))) 
			(players table)))
    (started . ,(started table))
    (events . ,(events table))))

(defmethod redact ((stack stack))
  (if-up stack stack
	 (cons '(type . stack)
	       (cons `(cards, (mapcar #'redact (cards stack)))
		     (remove-if (lambda (pair) (eq (first pair) 'cards)) 
				(to-alist stack))))))

(defmethod redact ((card card))
  (cons '(type . card)
	(if-up card card
	       (remove-if (lambda (pair) (eq (first pair) 'content))
			  (to-alist card)))))