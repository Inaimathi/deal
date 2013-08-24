;;;; package.lisp

(defpackage #:deal 
  (:use #:cl #:optima #:json #:cl-mop #:hunchentoot)
  (:import-from #:cl-ppcre #:regex-replace-all)
  (:import-from #:bordeaux-threads #:make-lock #:with-lock-held)
  (:import-from #:drakma #:http-request))

(in-package #:deal)
;;;;;;;;;; Config variables
(defparameter *server-port* 8080)
(defparameter *stream-server-uri* "http://localhost:9080/")
;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defparameter *handlers* (make-hash-table :test 'equal))

;;;;;;;;;; Generic definitions
(defgeneric insert! (container item)
  (:documentation "A generic insertion function. It takes a container object and an item, and inserts the second into the first in a destructive manner. It takes care of updating object state related to, but not part of, naive item insertion."))

(defgeneric delete! (container item)
  (:documentation "The inverse of `insert!`. Takes a container and an item, and removes the second from the first in a destructive matter. Undoes the same related object state that an insert! would have touched."))

(defgeneric redact (thing)
  (:documentation "Returns a copy of its argument with private information removed. Notably, doesn't show card text for face-down cards or stacks."))