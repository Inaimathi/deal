(defpackage :house  
  (:use :cl #:optima #:cl-ppcre #:usocket)
  (:import-from #:alexandria :starts-with-subseq)
  (:import-from #:deal :aif :awhen :it))