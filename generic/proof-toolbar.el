;; proof-toolbar.el    Toolbar for Proof General
;;
;; Copyright (C) 1998 David Aspinall.
;; Author:     David Aspinall <da@dcs.ed.ac.uk>
;; Maintainer: Proof General maintainer <proofgen@dcs.ed.ac.uk>
;;
;; $Id$
;;
;; NB: FSF GNU Emacs has no toolbar facility. This file defines
;; proof-toolbar-menu which holds the same commands and is put on the
;; menubar by proof-toolbar-setup (surprisingly).
;;
;; Toolbar is just for the scripting buffer currently.
;;
;;
;; TODO:
;;
;; FIXME: edit-toolbar cannot edit proof toolbar (even in a proof mode)
;; Need a variable containing  a specifier or similar.
;; (defvar proof-toolbar-specifier nil
;;   "Specifier for proof toolbar.")
;; This doesn't seem worth fixing until XEmacs toolbar implementation
;; settles a bit.  Enablers don't work too well at the moment.

;; FIXME: it's a little bit tricky to add prover-specific items.
;; We can improve on that by generating everything on-thy-fly
;; in proof-toolbar-setup.

;; FIXME: consider automatically disabling buttons which are
;; not configured for the prover, e.g. if proof-info-command is
;; not set, then the Info button should not be show. 

;; FIXME: In the future, add back the enabler functions.
;; As of 20.4, they *almost* work, but it seems difficult
;; to get the toolbar to update at the right times.
;; For older versions of XEmacs (19.15, P.C.Callaghan@durham.ac.uk
;; reports) the toolbar specifier format doesn't like
;; arbitrary sexps as the enabler, either.


;;; IMPORT declaration 
(require 'proof-script)
(autoload 'proof-shell-live-buffer "proof-shell")
(autoload 'proof-shell-restart "proof-shell")


;;
;; The default generic toolbar and toolbar variable
;;

(defconst proof-toolbar-entries-default
  `((state	"Display proof state" "Display the current proof state" t)
    (context	"Display context"     "Display the current context" t)
    (goal	"Start a new proof"   "Start a new proof" t)
    (retract	"Retract buffer"      "Retract (undo) whole buffer" t)
    (undo	"Undo step"           "Undo the previous proof command" t)
    (next	"Next step"           "Process the next proof command" t)
    (use	"Use buffer"  	      "Process whole buffer" t)
    (restart	"Restart scripting"   "Restart scripting (clear all locked regions)" t)
    (qed	"Finish proof"        "Close/save proved theorem" t)
    (find	"Find theorems"	      "Find theorems" t)
    (command    "Issue command"	      "Issue a non-scripting command" t)
    (interrupt  "Interrupt prover"    "Interrupt the proof assistant (warning: may break synchronization)" t)
    (info	nil		      "Show proof assistant information" t)
    (help	nil		      "Proof General manual" t))
"Example value for proof-toolbar-entries.  Also used to define Scripting menu.
This gives a bare toolbar that works for any prover.  To add
prover specific buttons, see documentation for proof-toolbar-entries
and the file proof-toolbar.el.")

;; FIXME: defcustom next one, to set on a per-prover basis
(defvar proof-toolbar-entries
  proof-toolbar-entries-default
  "List of entries for Proof General toolbar and Scripting menu.
Format of each entry is (TOKEN MENUNAME TOOLTIP ENABLER-P).
For each TOKEN, we expect an icon with base filename TOKEN,
		          a function proof-toolbar-<TOKEN>,
         and (optionally) an enabler proof-toolbar-<TOKEN>-enable-p.
If MENUNAME is nil, item will not appear on the \"Scripting\" menu.")



;;
;; Function, icon, button names
;; 

(defun proof-toolbar-function (token)
  (intern (concat "proof-toolbar-" (symbol-name token))))

(defun proof-toolbar-icon (token)
  (intern (concat "proof-toolbar-" (symbol-name token) "-icon")))

(defun proof-toolbar-enabler (token)
  (intern (concat "proof-toolbar-" (symbol-name token) "-enable-p")))


;;
;; Now the toolbar icons and buttons
;; 

(defun proof-toolbar-make-icon (tle)
  "Make icon variable and icon list entry from a proof-toolbar-entries entry."
  (let* ((icon (car tle))
	 (iconname (symbol-name icon))
	 (iconvar  (proof-toolbar-icon icon)))
    ;; first declare variable
    ;;  (eval
    ;;  `(defvar ,iconvar nil
    ;;  ,(concat 
    ;;   "Glyph list for " iconname " button in Proof General toolbar.")))
    ;; FIXME: above doesn't quite work right.  However, we only lose
    ;; the docstring which is no big deal.
    ;; now the list entry
    (list iconvar iconname)))
  
(defconst proof-toolbar-iconlist
  (mapcar 'proof-toolbar-make-icon proof-toolbar-entries)
  "List of icon variable names and their associated image files.
A list of lists of the form (VAR IMAGE).  IMAGE is the root name
for an image file in proof-images-directory.  The toolbar
code expects to find files IMAGE.xbm, IMAGE.xpm, IMAGE.8bit.xpm
and chooses the best one for the display properites.")

(defun proof-toolbar-make-toolbar-item (tle)
  "Make a toolbar button descriptor from a proof-toolbar-entries entry."
  (let*
      ((token	      (car tle))
       (menuname      (cadr tle))
       (tooltip       (nth 2 tle))
       (existsenabler (nth 3 tle))
       (enablep	      (and proof-toolbar-use-enablers
			   (>= emacs-major-version 21)
			   existsenabler))
       (enabler	      (proof-toolbar-enabler token))
       (enableritem   (if enablep (list enabler) t))
       (buttonfn      (proof-toolbar-function token))
       (icon	      (proof-toolbar-icon token))
       (actualfn      (if (or enablep (not existsenabler))
			  buttonfn
			;; Add the enabler onto the function if necessary.
			`(lambda ()
				   (if (,enabler) 
				       (call-interactively (quote ,buttonfn)))))))
    (vector icon actualfn enableritem tooltip)))

(defvar proof-toolbar-button-list 
  (append
   (mapcar 'proof-toolbar-make-toolbar-item proof-toolbar-entries)
   (list [:style 3d]))
  "A toolbar descriptor evaluated in proof-toolbar-setup.
Specifically, a list of sexps which evaluate to entries in a toolbar
descriptor.   The default value proof-toolbar-default-button-list
will work for any proof assistant.")

;;
;; Code for displaying and refreshing toolbar
;;

(defvar proof-toolbar nil
  "Proof mode toolbar button list.  Set in proof-toolbar-setup.")

(deflocal proof-toolbar-itimer nil
  "itimer for updating the toolbar in the current buffer")

;;; ###autoload
(defun proof-toolbar-setup ()
  "Initialize Proof General toolbar and enable it for the current buffer.
If proof-mode-use-toolbar is nil, change the current buffer toolbar
to the default toolbar."
  (interactive)
  (if (featurep 'toolbar)		; won't work in FSF Emacs
      (if (and	
	   (not proof-toolbar-inhibit)
	   ;; NB for FSFmacs use window-system, not console-type
	   (eq (console-type) 'x))
	  (let
	      ((icontype   (if (featurep 'xpm)
			       (if (< (device-pixel-depth) 16)
				   ".8bit.xpm" ".xpm")
			     ".xbm")))
	    ;; First set the button variables to glyphs.  
	    (mapcar
	     (lambda (buttons)
	       (let ((var	(car buttons))
		     (iconfiles (mapcar (lambda (name)
					  (concat proof-images-directory
						  name
						  icontype)) (cdr buttons))))
		 (set var (toolbar-make-button-list iconfiles))))
	     proof-toolbar-iconlist)
	    ;; Now evaluate the toolbar descriptor
	    (setq proof-toolbar (mapcar 'eval proof-toolbar-button-list))
	    ;; Ensure current buffer will display this toolbar
	    (set-specifier default-toolbar proof-toolbar (current-buffer))
	    ;; Set the callback for updating the enablers
	    (add-hook 'proof-state-change-hook 'proof-toolbar-refresh)
	    ;; Also call it whenever text changes in this buffer,
	    ;; provided it's a script buffer.
	    (if (eq proof-buffer-type 'script)
		(add-hook 'after-change-functions 
			  'proof-toolbar-refresh nil t))
	    ;; And the interval timer for really refreshing the toolbar
	    (setq proof-toolbar-itimer
		  (start-itimer "proof toolbar refresh"
				'proof-toolbar-really-refresh
				0.5		 ; seconds of delay
				0.5		 ; repeated
				t		 ; count idle time
				t		 ; pass argument
				(current-buffer)))) ;  - current buffer
	;; Disabling toolbar: remove specifier, hooks, timer.
	(remove-specifier default-toolbar (current-buffer))
	(remove-hook 'proof-state-change-hook 'proof-toolbar-refresh)
	(remove-hook 'after-change-functions 'proof-toolbar-refresh)
	(if proof-toolbar-itimer (delete-itimer proof-toolbar-itimer))
	(setq proof-toolbar-itimer nil))))

(defun proof-toolbar-toggle (&optional force-on)
  "Toggle display of Proof General toolbar."
  (interactive "P")
  (setq proof-toolbar-inhibit
       (or force-on (not proof-toolbar-inhibit)))
  (proof-toolbar-setup))

(deflocal proof-toolbar-refresh-flag nil
  "Flag indicating that the toolbar should be refreshed.")

;; &rest args needed for after change function args
;; FIXME: don't want to do this in every buffer, really;
;; we'll have proof-toolbar-refresh-flag defined everywhere.
(defun proof-toolbar-refresh (&rest args)
  "Set flag to indicate that the toolbar should be refreshed."
  (setq proof-toolbar-refresh-flag t))

(defun proof-toolbar-really-refresh (buf)
  "Force refresh of toolbar display to re-evaluate enablers.
This function needs to be called anytime that enablers may have 
changed state."
  ;; FIXME: could improve performance here and reduce flickeryness
  ;; by caching result of last evaluation of enablers.  If nothing
  ;; has changed, don't remove and re-add.
  (if ;; Be careful to only add to correct buffer, and if it's live
      (buffer-live-p buf)
      ;; I'm not sure if this is "the" official way to do this,
      ;; but it's what VM does and it works.
      (progn
	(remove-specifier default-toolbar buf)
	(set-specifier default-toolbar proof-toolbar buf)
	(setq proof-toolbar-refresh-flag nil))
    ;; Kill off this itimer if it's owning buffer has died
    (delete-itimer current-itimer)))

;;
;; =================================================================
;;
;;
;; GENERIC PROOF TOOLBAR BUTTON FUNCTIONS
;;
;; Defaults functions are provided below for: up, down, restart
;; Code for specific provers may define the symbols below to use
;; the other buttons: next, prev, goal, qed (images are provided).
;;
;;  proof-toolbar-next		   next function
;;  proof-toolbar-next-enable      enable predicate for next (or t)
;;
;; etc.
;;
;; To add support for more buttons or alter the default
;; images, proof-toolbar-entries should be adjusted.
;;
;;

;; TODO:
;;
;; Combine these with standard movement functions, rationalizing.
;;


;;
;; Helper functions 
;;

(defmacro proof-toolbar-move (&rest body)
  "Save point according to proof-toolbar-follow-mode, execute BODY."
  `(if (eq proof-toolbar-follow-mode 'locked)
       (progn
	 ,@body)				; nb no error catching
     (save-excursion
	,@body)))

(defun proof-toolbar-follow ()
  "Maybe point to the make sure the locked region is displayed."
  (if (eq proof-toolbar-follow-mode 'follow)
    (proof-goto-end-of-queue-or-locked-if-not-visible)))


;;
;; Undo button
;;

(defun proof-toolbar-undo-enable-p () 
  (and (proof-shell-available-p)
       (> (proof-unprocessed-begin) (point-min))))

;; No error if enabler fails: if it is because proof shell is busy,
;; it gets messy when clicked quickly in succession.

(defun proof-toolbar-undo ()
  "Undo last successful in locked region, without deleting it."
  (interactive)
  (proof-toolbar-move
   (proof-undo-last-successful-command t))
  (proof-toolbar-follow))

;;
;; Next button
;;

(defun proof-toolbar-next-enable-p ()
  (and
   (not (proof-locked-region-full-p))
   (not (and (proof-shell-live-buffer) proof-shell-busy))))

(defun proof-toolbar-next ()
  "Assert next command in proof to proof process.
Move point if the end of the locked position is invisible."
  (interactive)
  (proof-toolbar-move
   (goto-char (proof-queue-or-locked-end)) ; was unprocessed-begin
   (proof-assert-next-command-interactive))
  (proof-toolbar-follow))


;;
;; Retract button
;;

(defun proof-toolbar-retract-enable-p ()
  (not (proof-locked-region-empty-p)))

;; FIXME: to become proof-retract-buffer
(defun proof-toolbar-retract ()
  "Retract entire buffer."
  ;; proof-retract-file might be better here!
  (interactive)
  (proof-toolbar-move
   (proof-retract-buffer))	; gives error if process busy
  (proof-toolbar-follow))

;;
;; Use button
;;

(defun proof-toolbar-use-enable-p ()
  (not (proof-locked-region-full-p)))

(defun proof-toolbar-use ()
  "Process the whole buffer."
  (interactive)
  (proof-toolbar-move
   (proof-process-buffer))	; gives error if process busy
  (proof-toolbar-follow))

;;
;; Restart button
;;

(defun proof-toolbar-restart-enable-p ()
  ;; Could disable this unless there's something running.
  ;; But it's handy to clearup extents, etc, I suppose.
  (eq proof-buffer-type 'script)	; should always be t 
					; (toolbar only in scripts)
  )

(defalias 'proof-toolbar-restart 'proof-shell-restart)

;;
;; Goal button
;;

(defun proof-toolbar-goal-enable-p ()
  ;; Goals are always allowed: will crank up process if need be.
  ;; Actually this should only be available when "no subgoals"
  t)

(defalias 'proof-toolbar-goal 'proof-issue-goal)


;;
;; QED button
;;

(defun proof-toolbar-qed-enable-p ()
  (and proof-shell-proof-completed
       (proof-shell-available-p)))

(defalias 'proof-toolbar-qed 'proof-issue-save)

;;
;; State button
;;

(defun proof-toolbar-state-enable-p ()
  (proof-shell-available-p))
  
(defalias 'proof-toolbar-state 'proof-prf)

;;
;; Context button
;;

(defun proof-toolbar-context-enable-p ()
  (proof-shell-available-p))
  
(defalias 'proof-toolbar-context 'proof-ctxt)

;;
;; Info button
;;
;; Might as well enable it all the time; convenient trick to
;; start the proof assistant.

(defun proof-toolbar-info-enable-p ()
  t)

(defalias 'proof-toolbar-info 'proof-help)

;;
;; Command button
;;

(defun proof-toolbar-command-enable-p ()
  (proof-shell-available-p))

(defalias 'proof-toolbar-command 'proof-execute-minibuffer-cmd)

;;
;; Help button
;;
 
(defun proof-toolbar-help-enable-p () 
  t)

(defun proof-toolbar-help ()
  (interactive)
  (info "ProofGeneral"))

;;
;; Find button
;;
 
(defun proof-toolbar-find-enable-p () 
  (proof-shell-available-p))

(defalias 'proof-toolbar-find 'proof-find-theorems)

;;
;; Interrupt button
;; 

(defun proof-toolbar-interrupt-enable-p ()
  proof-shell-busy)

(defalias 'proof-toolbar-interrupt 'proof-interrupt-process)


;;
;; =================================================================
;;
;; Scripting menu built from toolbar functions
;;

(defun proof-toolbar-make-menu-item (tle)
  "Make a menu item from a proof-toolbar-entries entry."
  (let*
      ((token	  (car tle))
       (menuname  (cadr tle))
       (tooltip   (nth 2 tle))
       (enablep	  (nth 3 tle))
       (fnname	  (proof-toolbar-function token))
       ;; fnval: remove defalias to get keybinding onto menu; 
       ;; NB: function and alias must both be defined for this 
       ;; to work!!
       (fnval	  (if (symbolp (symbol-function fnname))
		      (symbol-function fnname)
		    fnname)))
    (if menuname
	(list 
	 (apply 'vector
	   (append
	    (list menuname fnval)
	    (if enablep 
		(list ':active (list (proof-toolbar-enabler token))))))))))
   
(defconst proof-toolbar-scripting-menu
  ;; Toolbar contains commands to manipulate script and
  ;; other handy stuff.  Called "Scripting"
  (apply 'append
	  (mapcar 'proof-toolbar-make-menu-item 
		  proof-toolbar-entries))
  "Menu made from the Proof General toolbar commands.")

;;
;; Add this menu to proof-menu
;;
; (setq proof-menu
;      (append proof-menu (list proof-toolbar-menu)))

 
;; 
(provide 'proof-toolbar)

