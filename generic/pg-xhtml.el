;; pg-xhtml.el	 XHTML goal display for Proof General
;;
;; Copyright (C) 2002 LFCS Edinburgh. 
;; Author:     David Aspinall <da@dcs.ed.ac.uk>
;; License:    GPL (GNU GENERAL PUBLIC LICENSE)
;;
;; $Id$
;;

(require 'pg-xml)

;;
;; Names for temporary files
;;
(defvar pg-xhtml-dir nil
  "Default value for XHTML directory.")

(defun pg-xhtml-dir ()
  "Temporary directory for storing XHTML files."
  (or pg-xhtml-dir
      (setq pg-xhtml-dir
	    (concat (if proof-running-on-win32
			"c:\\windows\\temp\\" ;; temp dir from env?
		      (or (concat (getenv "TMP") "/") "/tmp/"))
		    "pg"
		    (getenv "USER")
		    (int-to-string (emacs-pid))
		    (char-to-string directory-sep-char)))))

(defvar pg-xhtml-file-count 0
  "Counter for generating XHTML files.")

(defun pg-xhtml-next-file ()
  "Return new file name for XHTML storage."
  (concat 
   (pg-xhtml-dir)
   (int-to-string  (incf pg-xhtml-file-count))
   (if proof-running-on-win32 ".htm" ".html")))


;;
;; Writing an XHMTL file
;;

(defvar pg-xhtml-header 
  "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN
http://www.w3.org/TR/xhtml11/DTD/xhtml11-strict.dtd\">\n
<!-- This file was automatically generated by Proof General -->\n\n"
  "Header for XHTML files.")

(defmacro pg-xhtml-write-tempfile (&rest body)
  "Write a new temporary XHTML file, returning its location.
BODY should contain a sequence of pg-xml writing commands."
  (let ((dir (pg-xhtml-dir))
	(file (pg-xhtml-next-file)))
    ;; 
    (or (eq (car-safe (file-attributes dir)) 't)
	(if (not (file-attributes dir))
	    (make-directory (pg-xhtml-dir) t)
	  (error "pg-xhtml-write-tempfile: cannot open temp dir " 
		 (pg-xhtml-dir))))
    `(with-temp-file ,file
      (pg-xml-begin-write t)
      (pg-xml-add-text pg-xhtml-header)
      ,@body
      (insert (pg-xml-doc))
      ,file)))

(defun pg-xhtml-cleanup-tempdir ()
  "Cleanup temporary directory used for XHTML files."
  (delete-directory (pg-xhtml-dir)))
    
(defvar pg-mozilla-prog-name 
  "/usr/bin/mozilla"
  "Command name of browser to use with XHTML display.")

(defun pg-xhtml-display-file-mozilla (file)
  "Display FILENAME in netscape/mozilla."
  (shell-command (concat pg-mozilla-prog-name
			 " -remote \"openURL(" file ")\"")))

(defalias 'pg-xhtml-display-file 'pg-xhtml-display-file-mozilla)

; Test doc
;(pg-xhtml-display-file-mozilla
;(pg-xhtml-write-tempfile
;  (pg-xml-openelt 'root)
;  (pg-xml-openelt 'a '((class . "1B")))
;  (pg-xml-writetext "text a")
;  (pg-xml-closeelt)
;  (pg-xml-closeelt)))


(provide 'pg-xhtml)
;; End of pg-xhtml
