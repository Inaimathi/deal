;;;; house.asd

(asdf:defsystem #:house
    :serial t
    :description "Custom asynchronous HTTP server for the Deal project."
  :author "Inaimathi <leo.zovic@gmail.com>"
  :license "AGPL3"
  :depends-on (#:alexandria #:anaphora #:cl-base64 #:cl-ppcre #:cl-json #:bordeaux-threads #:cl-fad #:usocket #:cl-ppcre #:optima #:ironclad #:flexi-streams #:trivial-timeout)
  :components ((:file "house/package")
	       (:file "house/model")
	       (:file "house/util")
	       (:file "house/house")))