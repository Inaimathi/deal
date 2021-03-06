(in-package :deal)

(defclass table ()
  ((id :reader id :initform (make-id "TABLE"))
   (tag :accessor tag :initform "" :initarg :tag)
   (started :reader started :initform (get-universal-time))
   (max-players :accessor max-players :initform 12 :initarg :max-players)
   (player-count :accessor player-count :initform 0)
   (players :accessor players :initform nil)
   (things :accessor things :initform (make-hash-table))
   (passphrase :accessor passphrase :initform nil :initarg :passphrase)
   (tablecloth :accessor tablecloth :initform nil :initarg :tablecloth)
   (history :accessor history :initform nil)))

(defmethod full? ((table table)) 
  (with-slots (player-count max-players) table
    (>= player-count max-players)))

(defmethod last-action ((table table)) (cdaar history))

;;;;;;;;;; Game elements
(defclass deck ()
  ((deck-name :reader deck-name :initarg :deck-name)
   (card-type :reader card-type :initarg :card-type)
   (cards :reader cards :initarg :cards)
   (image-uri :accessor image-uri :initarg :image-uri :initform nil)))

(defclass placeable ()
  ((id :accessor id :initform (make-id))
   (x :accessor x :initform 0 :initarg :x)
   (y :accessor y :initform 0 :initarg :y)
   (z :accessor z :initform 0 :initarg :z)
   (rot :accessor rot :initform 0 :initarg :rot)
   (width :accessor width :initarg :width :initform nil)
   (height :accessor height :initarg :height :initform nil)
   (depth :accessor depth :initarg :depth :initform nil)
   (belongs-to :accessor belongs-to :initarg :belongs-to)
   (attached-to :accessor attached-to :initarg :attached-to :initform nil)
   (image-uri :accessor image-uri :initarg :image-uri :initform nil)))

(defclass card (placeable)
  ((id :initform (make-id "CARD"))
   (content :accessor content :initarg :content)
   (face :accessor face :initform :up :initarg :face)
   (card-type :accessor card-type :initarg :card-type)
   (back-image-uri :accessor back-image-uri :initarg :back-image-uri :initform nil)))

(defclass stack (placeable)
  ((id :initform (make-id "STACK"))
   (cards :accessor cards :initform nil :initarg :cards)
   (card-count :accessor card-count :initform 0 :initarg :card-count)
   (card-type :accessor card-type :initarg :card-type)))

(defclass note (placeable)
  ((id :initform (make-id "NOTE"))
   (text :accessor text :initarg :text)))

(defclass mini (placeable)
  ((id :initform (make-id "MINI"))))

(defun make-card (content card-type belongs-to &key back-image image (x 0) (y 0) (z 0) (rot 0))
  (make-instance 'card :content content :face :down :back-image-uri back-image :image-uri image 
		 :card-type card-type :belongs-to belongs-to
		 :x x :y y :z z :rot rot))

(defmethod stack<-deck (player (deck deck))
  "Takes a deck and creates a stack (a bag of cards suitable for placing on a table)"
  (with-slots (cards card-count card-type) deck
    (let ((id (id player)))
      (make-instance 
       'stack :belongs-to id :card-type card-type :card-count (length cards)
       :cards (mapcar (lambda (c) (make-card c card-type id)) cards)))))

(defun stack<-json (player json)
  "Takes a JSON representation of a deck and creates a stack (a bag of cards suitable for placing on a table)"
  (macrolet ((gets (k) `(getj ,k json))
	     (getd (k &optional (default 0)) `(or (getj ,k json) ,default)))
    (let ((cards (gets :cards))
	  (card-type (gets :card-type))
	  (player-id (id player))
	  (card-count 0)
	  (back-image (gets :image-uri)))
      (let ((stack
	     (make-instance
	      'stack :belongs-to player-id :card-type card-type :image-uri back-image
	      :x (getd :x) :y (getd :y) :z (getd :z) :rot (getd :rot)
	      :cards (loop for content in cards
			append (loop repeat (or (getj :count content) 1)
				  do (incf card-count)
				  collect (make-card (remove-if (lambda (elem) 
								  (member (car elem) (list :count :image-uri)))
								content)
						     card-type player-id :back-image back-image 
						     :image (getj :image-uri content)))))))
	(setf (card-count stack) card-count)
	stack))))

;;;;;;;;;; delete/insert methods (more in model/server.lisp)
(defmethod delete! ((table table) (thing placeable))
  "Removes a thing from the given table"
  (setf (attached-to thing) nil)
  (remhash (id thing) (things table)))

(defmethod delete! ((stack stack) (card card))
  (setf (cards stack) (remove card (cards stack)))
  (decf (card-count stack)))

(defmethod insert! ((table table) (card card))
  "Place a new card on the given table. Re-assigns (id card) to maintain secrecy about card properties."
  (let ((new-id (make-id "CARD")))
    (setf (id card) new-id
	  (gethash new-id (things table)) card)))

(defmethod insert! ((table table) (thing placeable))
  "Places a new thing on the given table."
  (setf (gethash (id thing) (things table)) thing))

(defmethod insert! ((stack stack) (card card))
  "Inserts the given card into the given stack."
  (setf (id card) (make-id "CARD"))
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
  (with-slots (id tablecloth things players history tag) table
    (hash :type :table :id id :tag tag
	  :tablecloth tablecloth :things (redact things)
	  :players (mapcar #'redact players)
	  :history (take 100 history))))

(defmethod redact ((hash-table hash-table))
  (hash-map (lambda (v) (redact v)) hash-table))

(defmethod redact ((stack stack))
  (obj->hash stack (:type :stack) id x y z rot belongs-to card-count card-type image-uri attached-to))

(defmethod redact ((card card))
  (obj->hash card (:type :card :content (when (eq :up face) content) :image-uri (when (eq :up face) image-uri))
	     id x y z rot belongs-to face content card-type image-uri back-image-uri attached-to))

(defmethod redact ((mini mini))
  (obj->hash mini (:type :mini) id x y z rot belongs-to image-uri attached-to))

(defmethod redact ((note note))
  (obj->hash note (:type :note) id x y z rot belongs-to attached-to text))

;;;;;;;;;; Serialize methods
;;; More or less like redact, but always shows all information (this one's meant for game saving)
(defmethod serialize ((note note))
  (obj->hash note (:type :note) id x y z rot belongs-to attached-to text))

(defmethod serialize ((mini mini))
  (obj->hash mini (:type :mini) id x y z rot belongs-to image-uri attached-to))

(defmethod serialize ((card card))
  (obj->hash card (:type :card) content face card-type x y z rot attached-to))

(defmethod serialize-stacked ((card card))
  (obj->hash card (:type :card) content))

(defmethod serialize ((stack stack))
  (obj->hash stack (:type :stack :cards (mapcar #'serialize (cards stack))) 
	     cards card-type x y z rot attached-to))

(defmethod serialize ((table table))
  (obj->hash table (:things (mapcar #'serialize (hash-values things)))
	     things tablecloth))
