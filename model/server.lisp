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
  ((id :reader id :initform (make-id))
   (tag :accessor tag :initform nil :initarg :tag)
   (current-table :accessor current-table :initform nil)
   (last-seen :accessor last-seen :initform (get-universal-time))
   (hand :accessor hand :initform (make-hash-table) :initarg :hand)))

(defun find-deck (deck-name &optional (decks-list (decks *server*)) )
  (find deck-name decks-list :key #'deck-name :test #'string=))

(defmethod redact ((player player))
  (hash :id (id player) :hand (hash-table-count (hand player))))

(defmethod delete! ((player player) (card card))
  "Removes the given card from the given players' hand"
  (remhash (id card) (hand player)))

(defmethod delete! ((table table) (player player))
  (setf (players table) (remove player (players table)))
  (decf (player-count table)))

(defmethod insert! ((player player) (card card))
  "Adds the given card to the given players' hand"
  (setf (id card) (make-id)
	(gethash (id card) (hand player)) card))

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
  (setf (current-table player) table)
  (incf (player-count table))
  (push player (players table)))

(defmethod publish! ((target server) action-type &optional message (stream-server *stream-server-uri*))
  (let* ((player (session-value :player))
	 (full-message `((type . ,action-type) 
			 (time . ,(get-universal-time))
			 (player . ,(id player))
			 (player-tag . ,(tag player))
			 ,@message)))
    (http-request (format nil "~apub?id=lobby" stream-server)
		  :method :post :content (encode-json-to-string full-message))))