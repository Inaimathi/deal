(in-package :deal)

(defclass server ()
  ((public-tables :accessor public-tables :initform (make-hash-table))
   (private-tables :accessor private-tables :initform (make-hash-table))
   (decks :accessor decks :initform nil :initarg :decks)
   (players :accessor players :initform (make-hash-table))
   (table-count :accessor table-count :initform 0)
   (max-tables :accessor max-tables :initform 10)
   (player-count :accessor player-count :initform 0)
   (max-players :accessor max-players :initform 50)
   (lock :accessor lock :initform (make-lock))))

(defclass player ()
  ((id :reader id :initform (intern (symbol-name (gensym)) :keyword))
   (hand :accessor hand :initform (make-hash-table) :initarg :hand)))

(defmethod delete! ((player player) (card card))
  (remhash (id card) (hand player)))

(defmethod insert! ((server server) (table table))
  "Adds a new table to the server"
  (with-slots (table-count max-tables private-tables public-tables) server
    (when (> max-tables table-count)
      (setf (gethash (id table)
		     (if (passphrase table) 
			 private-tables
			 public-tables)) table)
      (incf table-count))))

(defmethod insert! ((server server) (player player))
  "Adds a new player to the server"
  (with-slots (player-count max-players players) server
    (when (> max-players player-count)
      (setf (gethash (id player) players) player)
      (incf player-count))))

(defmethod insert! ((table table) (player player))
  "Sits a new player down at the given table"
  (push player (players table)))