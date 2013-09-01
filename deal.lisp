;;;; deal.lisp
(in-package #:deal)

;;;;;;;;;; Handlers
;;;;; Getters
(define-handler (server-info) ()
  `((handlers . ,*handlers*)
    (public-tables . ,(hash-map 
		       (lambda (k v) 
			 `((id . ,k) (tag . ,(tag v)) (seated . ,(player-count v)) (of . ,(max-players v))))
		       (public-tables *server*)))
    (decks . ,(mapcar #'deck-name (decks *server*)))))

(define-handler (look-table) ((table :table)) (redact table))

(define-handler (table-history) ((table :table)) (history table))

(define-handler (my-hand) ()
   (hash-values (hand (session-value :player))))

;;;;; Lobby-related
(define-handler (lobby/session json:encode-json-alist-to-string) ()
  (if (session-value :player)
      (with-slots (id tag current-table hand) (session-value :player)
	`((id . ,id) (tag . ,tag) (current-table . ,(aif current-table (redact it))) (hand ,@hand)))
      (let ((player (make-instance 'player :tag "Anonymous Coward")))
	(setf (session-value :player) player)
	(with-slots (id tag) player
	  `((id . ,id) (tag . ,tag) (current-table) (hand))))))

(define-handler (lobby/speak) ((message (:string :min 2 :max 255)))
  (assert (session-value :player))
  (publish! *server* :said (escape-string message))
  :ok)

(define-handler (lobby/tag) ((new-tag (:string :max 255)))
  (assert (session-value :player))
  (let* ((player (session-value :player))
	 (old (tag player)))
    (setf (tag player) new-tag)
    (publish! *server* :changed-nick `((old-tag . ,old)))
    :ok))

(define-handler (lobby/new-private-table) ((tag :string) (passphrase :string))
  (assert (session-value :player))
  (with-lock-held ((lock *server*))
    (let ((player (session-value :player))
	  (table (make-instance 'table :tag tag :passphrase passphrase)))
      (insert! *server* table)
      (insert! table player)
      (redact table))))

(define-handler (lobby/new-public-table) ((tag :string))
  (assert (session-value :player))
  (with-lock-held ((lock *server*))
    (let ((player (session-value :player))
	  (table (make-instance 'table :tag tag)))
      (insert! *server* table)
      (insert! table player)
      (with-slots (id tag player-count max-players) table
	(publish! *server* :started-table `((id . ,id) (tag . ,tag) (seated . ,player-count) (of . ,max-players))))
      (redact table))))

(define-table-handler (lobby/join-table) ((table :table) (passphrase :string))
  (assert (and (session-value :player) (not (full? table))))
  (with-slots (id players) table
    (let ((player (session-value :player)))
      (unless (member player (players table))
	(insert! table player)
	(publish! table :joined `((table . ,(id table))))
	(publish! *server*
		  (if (full? table) :filled-table :joined)
		  `((id . ,id))))
      (redact table))))

;;;; Game related (once you're already at a table)
(define-player-handler (play/leave-table) ((table :table))
  (let ((player (session-value :player)))
    (delete! table player)
    (setf (current-table player) nil)
    (unless (passphrase table)
      (publish! table :left)
      (publish! *server* :left 
		`((id . ,(id table)) (tag . ,(tag table)) (seated . ,(player-count table)) (of . ,(max-players table)))))
    :ok))

(define-player-handler (play/speak) ((table :table) (message (:string :min 2 :max 255)))
  (publish! table :said `((message . ,(escape-string message))))
  :ok)

(define-player-handler (play/roll) ((table :table) (num-dice (:int :min 1 :max 128)) (die-size (:int :min 2 :max 4096)) (modifier (:int :min -4096 :max 4096)))
  (let ((mod (cond ((> modifier 0) (format nil "+~a" modifier))
		   ((> 0 modifier) modifier)
		   (t nil))))
    (multiple-value-bind (total rolls) (roll num-dice die-size)
      (publish! table :rolled
		`((dice . ,(format nil "~ad~a~@[~a~]" num-dice die-size mod)) 
		  (total . ,(+ total modifier))
		  (rolls . ,rolls)))))
  :ok)

(define-player-handler (play/coin-toss) ((table :table))
  (publish! table :flipped-coin `((result . ,(pick (list :heads :tails)))))
  :ok)

(define-player-handler (play/move) ((table :table) (thing :placeable) (x :int) (y :int) (z :int) (rot :int))
  (set-props thing x y z rot)
  (publish! table :moved  `((thing . ,(id thing)) (x . ,x) (y . ,y) (z . ,z) (rot . ,rot)))
  :ok)

(define-player-handler (play/take-control) ((table :table) (thing :placeable))
  (setf (belongs-to thing) (id (session-value :player)))
  (publish! table :took-control `((thing . ,(id thing))))
  :ok)

(define-player-handler (play/flip) ((table :table) (card (:card :from-table)))
  (setf (face card) (if (eq (face card) :up) :down :up))
  (publish! table :flipped `((card . ,(redact card))))
  :ok)

(define-player-handler (play/new-stack-from-cards) ((table :table) (cards (:list card)))
  (let* ((c (first cards))
	 (stack (make-instance 'stack :belongs-to (id (session-value :player)) :x (x c) :y (y c) :z (z c) :rot (rot c))))
    (loop for card in cards 
       do (delete! table card) do (insert! stack card))
    (publish! table :stacked-up `((stack . ,(redact stack)) (cards . ,(mapcar #'id cards))))
    :ok))

(define-player-handler (play/new-stack-from-deck) ((table :table) (deck-name :string) (x :int) (y :int) (z :int) (rot :int))
  (let ((stack (stack<-deck (session-value :player) (find-deck deck-name))))
    (set-props stack x y z rot)
    (insert! table stack)
    (publish! table :new-deck `((name . ,deck-name) (stack . ,(redact stack))))
    :ok))

(define-player-handler (play/new-stack-from-json) ((table :table) (deck :json) (x :int) (y :int) (z :int) (rot :int))
  (let ((stack (stack<-json (session-value :player) deck)))
    (set-props stack x y z rot)
    (insert! table stack)
    (publish! table :new-deck `((name . ,(getj :deck-name deck)) (stack . ,(redact stack))))
    :ok))

;;;;; Stacks
(define-player-handler (stack/play) ((table :table) (stack :stack) (x :int) (y :int) (z :int) (rot :int))
  (let ((card (pop! stack)))
    (set-props card x y z rot)
    (insert! table card)
    (publish! table :played-from-stack `((stack . ,(id stack)) (card . ,(redact card))))
    :ok))

(define-player-handler (stack/add-to) ((table :table) (stack :stack) (card (:card :from-table)))
  (publish! table :added-to-stack `((stack . ,(id stack)) (card . ,(id card))))
  (move! card table stack)
  :ok)

(define-player-handler (stack/merge) ((table :table) (stack :stack) (stack-two :stack))
  (dolist (c (cards stack-two)) (insert! stack c))
  (delete! table stack-two)
  (publish! table :merged-stacks `((stack . ,(redact stack)) (merged ,(id stack-two))))
  :ok)

(define-player-handler (stack/shuffle) ((table :table) (stack :stack))
  (setf (cards stack) (shuffle (cards stack)))
  (publish! table :shuffled `((stack . ,(id stack))))
  :ok)

;;;;; Hand
(define-player-handler (hand/play) ((table :table) (card (:card :from-hand)) (face :facing) (x :int) (y :int) (z :int) (rot :int))
  (set-props card face x y z rot)
  (move! card (session-value :player) table)
  (publish! table :played-from-hand `((card . ,(redact card))))
  :ok)

(define-player-handler (hand/play-to) ((table :table) (card (:card :from-hand)) (stack :stack))
  (move! card (session-value :player) stack)
  (publish! table :played-to-stack `((stack . ,(id stack)) (card . ,(redact card))))
  :ok)

;;;;; Non-table handlers
;;; These handlers don't respond with a redacted table object because it wouldn't make sense in context
(define-player-handler (stack/draw) ((table :table) (stack :stack) (num :int))
  (loop with rep = (min num (card-count stack)) repeat rep
     do (let ((card (pop! stack)))
	  (setf (face card) :up)
	  (insert! (session-value :player) card)))
  (when (zerop (card-count stack))
    (delete! table stack))
  (publish! table :drew-from `((stack . ,(id stack)) (count . ,num)))
  (hash-values (hand (session-value :player))))

(define-player-handler (hand/pick-up) ((table :table) (card (:card :from-table)))
  (move! card table (session-value :player))
  (publish! table :picked-up `((card . ,(id card))))
  (hash-values (hand (session-value :player))))
 
(define-player-handler (stack/peek-cards) ((table :table) (stack :stack) (min :int) (max :int))
  (publish! table :peeked `((stack . ,(id stack)) (count . ,(- max min))))
  (take (- max min) (drop (+ min 1) (cards stack))))

(define-player-handler (stack/show) ((table :table) (stack :stack) (min :int) (max :int))
  (publish! table :revealed `((stack . ,(id stack)) (cards ,@(take (- max min) (drop (+ min 1) (cards stack))))))
  :ok)

;; (define-handler (stack/reorder) ((table :table) (stack :stack) (min :int) (max :int))
;;   ;; TODO
;;   (list :reordering-cards min :to max :from stack))