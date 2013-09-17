;;;; package.lisp

(defpackage #:deal 
  (:use #:cl #:optima #:json #:hunchentoot)
  (:import-from :cl-ppcre #:regex-replace-all)
  (:import-from :cl-fad #:list-directory)
  (:import-from :bordeaux-threads #:make-lock #:with-lock-held)
  (:import-from :drakma #:http-request)
  (:import-from :alexandria #:with-gensyms))

(in-package #:deal)
;;;;;;;;;; Config variables
(defparameter *server-port* 8080)
(defparameter *stream-server-uri* "http://localhost:9080/")
;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defparameter *handlers* (make-hash-table :test 'equal))

(defun dir->uris (dir)
  (let ((uri (concatenate 'string "/" dir)))
    (mapcar 
     (lambda (path)
       (namestring (merge-pathnames (file-namestring path) uri)))
     (list-directory (merge-pathnames dir)))))

(defparameter *mini-uris* (dir->uris "static/img/minis/"))
(defparameter *tablecloth-uris* (dir->uris "static/img/tablecloths/"))

;;;;;;;;;; Generic definitions
(defgeneric insert! (container item)
  (:documentation "A generic insertion function. It takes a container object and an item, and inserts the second into the first in a destructive manner. It takes care of updating object state related to, but not part of, naive item insertion."))

(defgeneric delete! (container item)
  (:documentation "The inverse of `insert!`. Takes a container and an item, and removes the second from the first in a destructive matter. Undoes the same related object state that an insert! would have touched."))

(defgeneric redact (thing)
  (:documentation "Returns a copy of its argument with private information removed. Notably, doesn't show card text for face-down cards or stacks."))

(defgeneric serialize (thing)
  (:documentation "Returns a copy of its argument with private information intact, but table-specific data (such as `id` and `belongs-to`) removed. Used to save table states for later reloading."))