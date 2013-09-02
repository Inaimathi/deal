(in-package :deal)

(defclass table ()
  ((id :reader id :initform (make-id))
   (tag :accessor tag :initform "" :initarg :tag)
   (started :reader started :initform (get-universal-time))
   (max-players :accessor max-players :initform 12 :initarg :max-players)
   (player-count :accessor player-count :initform 0)
   (players :accessor players :initform nil)
   (things :accessor things :initform (make-hash-table))
   (passphrase :accessor passphrase :initform nil :initarg :passphrase)
   (tablecloth :accessor tablecloth :initform nil :initarg :tablecloth)
   (history :accessor history :initform nil)
   (lock :accessor lock :initform (make-lock))))

(defmethod full? ((table table)) 
  (with-slots (player-count max-players) table
    (>= player-count max-players)))

(defmethod last-action ((table table)) (cdaar history))

;;;;;;;;;; Game elements
(defclass deck ()
  ((deck-name :reader deck-name :initarg :deck-name)
   (card-type :reader card-type :initarg :card-type)
   (cards :reader cards :initarg :cards)))

(defclass placeable ()
  ((id :accessor id :initform (make-id))
   (x :accessor x :initform 0 :initarg :x)
   (y :accessor y :initform 0 :initarg :y)
   (z :accessor z :initform 0 :initarg :z)
   (rot :accessor rot :initform 0 :initarg :rot)
   (belongs-to :accessor belongs-to :initarg :belongs-to)))

(defclass card (placeable)
  ((content :accessor content :initarg :content)
   (face :accessor face :initform :up :initarg :face)
   (card-type :accessor card-type :initarg :card-type)))

(defclass stack (placeable)
  ((cards :accessor cards :initform nil :initarg :cards)
   (card-count :accessor card-count :initform 0 :initarg :card-count)
   (card-type :accessor card-type :initarg :card-type)))

(defclass counter (placeable)
  ((counter-value :accessor counter-value :initarg :counter-value)))

(defclass mini (placeable)
  ((sprite :accessor sprite :initarg :sprite)))

(defun make-card (content card-type belongs-to)
  (make-instance 'card :content content :face :down :card-type card-type :belongs-to belongs-to))

(defmethod stack<-deck (player (deck deck))
  "Takes a deck and creates a stack (a bag of cards suitable for placing on a table)"
  (with-slots (cards card-count card-type) deck
    (make-instance 
     'stack :belongs-to (id player) :card-type card-type :card-count (length cards)
     :cards (mapcar (lambda (c) (make-card c card-type (id player))) cards))))

(defun stack<-json (player json)
  "Takes a JSON representation of a deck and creates a stack (a bag of cards suitable for placing on a table)"
  (let ((cards (getj :cards json))
	(card-type (getj :card-type json))
	(id (id player)))
    (make-instance
     'stack :belongs-to id :card-type card-type :card-count (length cards)
     :cards (mapcar (lambda (c) (make-card c card-type id)) cards))))

(defmethod publish! ((table table) action-type &optional move (stream-server *stream-server-uri*))
  (let* ((player (session-value :player))
	 (full-move `((time . ,(get-universal-time))
		      (type . ,action-type) 
		      (player . ,(id player))
		      (player-tag . ,(tag player))
		      ,@move)))
    (push full-move (history table))
    (http-request (format nil "~apub?id=~a" stream-server (id table))
		  :method :post :content (encode-json-to-string full-move))))

;;;;;;;;;; delete/insert methods (more in model/server.lisp)
(defmethod delete! ((table table) (thing placeable))
  "Removes a thing from the given table"
  (remhash (id thing) (things table)))

(defmethod insert! ((table table) (card card))
  "Place a new card on the given table. Re-assigns (id card) to maintain secrecy about card properties."
  (setf (id card) (make-id)
	(gethash (id card) (things table)) card))

(defmethod insert! ((table table) (thing placeable))
  "Places a new thing on the given table."
  (setf (gethash (id thing) (things table)) thing))

(defmethod insert! ((stack stack) (card card))
  "Inserts the given card into the given stack."
  (setf (id card) (make-id))
  (incf (card-count stack))
  (push card (cards stack)))

(defmethod pop! ((stack stack))
  "First decrements the card-count, then pops a card from the stack."
  (decf (card-count stack))
  (pop (cards stack)))

(defmethod move! ((card card) from to)
  "Method specifically for naive moves. It happens in at least four places, 
and because of our ID system, delete! must be called before insert!, 
so it made sense to formalize this."
  (delete! from card)
  (insert! to card))

;;;;;;;;;; Redact methods
(defmethod redact ((table table))
  (with-slots (id tablecloth things players history) table
    (hash :type :table :id id
	  :tablecloth tablecloth :things (redact things)
	  :players (mapcar #'redact players)
	  :history (take 100 history))))

(defmethod redact ((hash-table hash-table))
  (hash-map (lambda (v) (redact v)) hash-table))

(defmethod redact ((stack stack))
  (obj->hash stack (:type :stack) id x y z rot belongs-to card-count card-type))

(defmethod redact ((card card))
  (obj->hash card (:type :card :content (when (eq :up face) content))
	     id x y z rot belongs-to face content card-type))

;;;;;;;;;; Serialize methods
;;; More or less like redact, but always shows all information (this one's meant for game saving)
(defmethod serialize ((card card))
  (obj->hash card (:type :card) content face card-type x y z rot))

(defmethod serialize-stacked ((card card))
  (obj->hash card (:type :card) content))

(defmethod serialize ((stack stack))
  (obj->hash stack (:type :stack :cards (mapcar #'serialize (cards stack))) 
	     cards face card-type x y z rot))

(defmethod serialize ((table table))
  (obj->hash table (:things (hash-map (lambda (v) (serialize v)) things))
	     tag things tablecloth))