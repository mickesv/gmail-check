;;; gmail-check.el --- Check Unread Gmails

;; Author: Mikael Svahnberg <mikael.svahnberg@gmail.com>
;; Version: 0.1.0

;; The MIT License (MIT)
;;
;; Copyright (c) 2016 Mikael Svahnberg
;;
;; Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
;;
;; The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
;;
;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

;;; Commentary:

;; Background
;; --------------------
;; Poll GMail's Atom feed to find out how many new mails there are.
;; Put names <emails> :: Titles where you want it
;; Adds unread mailcount to modeline.
;; (optionally) alert when mails from certain people arrive.
;;
;; Instructions
;; --------------------
;;
;; Put this in your init.el - file:
;;
;; (require 'gmail-check)
;;
;;
;; Initialise the package
;; This will add a gmail counter to the modeline:
;; 
;; (gmail-check)
;;
;;
;; Add a regexp of a name to watch especially
;; This will change the colour of the gmail counter
;; and add the name to the help text when hovering over
;; it with the mouse pointer.:
;; 
;; (add-to-list 'gmail-check-watch '("RegexpName" . nil))
;;
;;
;; You may also wish to call a function:
;;
;; (add-to-list 'gmail-check-watch '("BossName" . flashCurrentBufferEgregiously))
;;
;;
;; gmail-check is normally silent, but if you wish to
;; output the headers somehow.
;; Output to a temp buffer:
;; 
;; (add-to-list 'gmail-check-output-functions 'gmail-check-do-output-default)
;;
;;
;; Output to two files, e.g. for use by geektools:
;;
;; (add-to-list 'gmail-check-output-functions 'gmail-check-do-output-file)
;;
;; The directory and the root of the filenames are set in the variable
;; `gmail-check-ootput-file-root'. Default is "/tmp/gmail-check"
;;


;;; Code:

(require 'url)
(require 'cl)

;; User configurable variables
;; --------------------
(defconst gmail-check-checkmail-timeout 30
  "The time in seconds that has to pass before checking the mail again.")

(defvar gmail-check-watch nil
  "Add (NAME . FUNCTION) pairs here.
When there is an email from NAME, execute FUNCTION.

When FUNCTION is nil, just do the basic notification (change
colour in mode line, add name to help text)

NOTE: FUNCTION will be called every time gmail-check checks for
mail so make sure it does something nice and stateless, otherwise
you will suffer the effects of the function until you finally
read the mail in question")

(defvar gmail-check-output-functions nil
  "List of functions to call with the output.
Each function takes two arguments: Number of mails, and a string with names and
titles")

(defvar gmail-check-output-file-root "/tmp/gmail-check"
  "Location for file when using the `gmail-check-output-file' function.

Two files will be created:
- <filename>-nbmails.txt contains the number of unread mails.
- <filename>-headers.txt contains the headers of the unread mails")

(defvar gmail-check-suspend nil
  "Temporarily suspend checking (useful if e.g. network is shaky)

Default is nil (not suspended)
Suspend checking if any other value.")

;; Internal variables and constants
;; --------------------
(defvar gmail-check-last-output ""
  "Keep the last output for the modeline menu.")
(defvar gmail-check-last-mailcount 0
  "Keep the last mailcount for the modeline menu.")
(defconst gmail-check-atom-url "https://mail.google.com/mail/feed/atom"
  "The URL that gmail publishes its RSS feed on.")
(defvar gmail-check-help-text ""
  "Text to display when hovering over mode-line.")

;; Some faces
(put 'gmail-check-face-normal 'face-alias 'mode-line)
(put 'gmail-check-face-highlight 'face-alias 'mode-line-buffer-id)
(put 'gmail-check-face 'face-alias 'gmail-check-face-normal)


;; Toggle Suspend
;; --------------------
(defun gmail-check-suspend ()
  "Toggle temporary suspension of gmail-check."
  (interactive)
  (setq gmail-check-suspend (not gmail-check-suspend))
  (unless gmail-check-suspend
    (gmail-check-do-output-file 0 "-- Gmail-check is temporarily suspended --"))
  gmail-check-suspend)

;; Add to Modeline
;; --------------------
(defun gmail-check-modeline ()
  "Modeline function. Make sure I don't retreive the e-mails more often than gmail-check-checkmail-timeout."
  (if (boundp 'gmail-check-time-last)
      (if (>= (nth 1 (current-time)) (+ gmail-check-time-last gmail-check-checkmail-timeout))
	  (progn
	    (setq gmail-check-time-last (nth 1 (current-time)))
;;	    (message "gmail-check: Retrieving mail...")
	    (gmail-check-retrieve))
	(if (< (nth 1 (current-time)) gmail-check-time-last)
	    (progn
	      (message "gmail-check: Resetting clock...")
	      (setq gmail-check-time-last (nth 1 (current-time))))))
    (progn				;; else (if (boundp...)
      (message "gmail-check: First run, retrieving mail...")
      (setq gmail-check-time-last (nth 1 (current-time)))
      (gmail-check-retrieve)))
  (if gmail-check-suspend
      (concat "[✉✖]")			;; There ought to be a better "suspend" symbol, but I CBA to find it now.
    (if (> gmail-check-last-mailcount 0)
	(format "✉%d"	gmail-check-last-mailcount)
      (concat ""))
    ))


(defun gmail-check-modeline-init ()
  "Add the number of unread mails to the modeline."
  (interactive)
  (add-to-list 'global-mode-string '(:eval (propertize (gmail-check-modeline)
						       'face 'gmail-check-face
						       'help-echo (concat gmail-check-help-text)))))


;; Act on watched senders
;; --------------------
(defun gmail-check-execute-watches (names)
  "Check NAMES using the variable `gmail-check-watch'.
If a name match is found, it calls the corresponding function"
;;  (message "gmail-check: Executing watches...")
  (put 'gmail-check-face 'face-alias 'gmail-check-face-normal)
  (setq gmail-check-help-text "")
  (mapc (lambda (name)
	  (mapc (lambda (pair)
		  (when (string-match (car pair) name)
;;			(message "gmail-check: Found match for %s in %s. Calling function..." (car pair) name)
		    (put 'gmail-check-face 'face-alias 'gmail-check-face-highlight)
		    (setq gmail-check-help-text (concat gmail-check-help-text name "\n"))
		    (if (cdr pair)
			(funcall (cdr pair))
;;			  (message "gmail-check: ERR: No function found.")
		      ))
		  ) gmail-check-watch)
	  ) names))



;; Output
;; --------------------

(defun gmail-check-do-output-default (nbmails output)
  "Displays the mail headers in a temp buffer."
  (message (format "New mails: %d" nbmails))
  (unless (= nbmails 0)
    (with-output-to-temp-buffer "*MailHeaders*"
      (princ output)
      )))

(defun gmail-check-do-output-file (nbmails output)
  "Store NBMAILS and OUTPUT (mail headers) in files.

The filenames and locations are specified with `gmail-check-output-file-root'"
  (write-region (if (< 0 nbmails)
		    (format "%d\n" nbmails)
		  (concat "\n"))
		  nil (expand-file-name (concat gmail-check-output-file-root "-nbmails.txt")) nil 42) ;; 42 is "neither t nor nil nor string" to write quietly without output to the message buffer
  (write-region (concat output "\n") nil (expand-file-name (concat gmail-check-output-file-root "-headers.txt")) nil 42))
 
(defun gmail-check-do-output (nbmails output)
  "Channel output to the specified places."
  (mapc (lambda (out-fun)
	  (funcall out-fun nbmails output))
	gmail-check-output-functions))

;; Core Functions 
;; --------------------          
(defun gmail-check-do-basic-string-cleanup (string)
  "Remove the most obvious swedish utf-8 characters from STRING.
This is an ugly hack and does not remove all utf-8 junk, but it'll do for now"
  (let* ((charmap [["\\\303\\\245" "å"]
		   ["\\\303\\\244" "ä"]
		   ["\\\303\\\266" "ö"]
		   ["\\\303\\\205" "Å"]
		   ["\\\303\\\204" "Ä"]
		   ["\\\303\\\226" "Ö"]
		   ])
	 (len (length charmap))
	 (iter 0))
    (while (> len iter)
      (setq string (replace-regexp-in-string (elt (elt charmap iter) 0) (elt (elt charmap iter) 1) string))
      (setq iter (1+ iter)))
    string))

(defun gmail-check-format-output (titles names emails)
  "Format the list of mails as name <email> :: title."
  (let ((output ""))
    (while names
      (setq output (concat output
			   (format "%45s :: %-40s\n"
				   (format "%.20s <%.20s>"
					   (gmail-check-do-basic-string-cleanup (car names))
					   (gmail-check-do-basic-string-cleanup (car emails)))
 				   (gmail-check-do-basic-string-cleanup (car titles)))))
      (setq names (cdr names)
	    emails (cdr emails)
	    titles (cdr titles)))
    (setq gmail-check-last-output output)))

(defun gmail-check-extract (block)
  "Extract the next BLOCK from current buffer."
  (let* ((start (search-forward (concat "<" block ">")))
	 (end (- (search-forward "</") 2)))
    (if (= start end)
	(concat "--- no " block " ---")
      (buffer-substring start end))))       

(defun gmail-check-retrieve ()
  "Retrieve the atom feed for gmail and extracts the number of mails plus author/title."
  (unless gmail-check-suspend
    (url-retrieve gmail-check-atom-url
                  (lambda (status)
                    (let ((titles '())
                          (names '())
                          (emails '())
                          (nbread 0)
                          (nbmails 0)
                          (output ""))
                      (goto-char 1)
                      (search-forward "</title>" nil t)
                      (setq nbmails (how-many "<title>"))
                      (setq gmail-check-last-mailcount nbmails)
                      (while (> nbmails nbread)
                        (push (gmail-check-extract "title") titles)
                        (push (gmail-check-extract "name") names)
                        (push (gmail-check-extract "email") emails)
                        (setq nbread (1+ nbread)))
                      (gmail-check-execute-watches names)
                      (setq output (gmail-check-format-output titles names emails))
                      (gmail-check-do-output nbmails output)
                      (kill-buffer)
                      )) nil t)))

(defun gmail-check ()
  "Initialise gmail-check."
  (interactive))
  ;;(gmail-check-modeline-init))

(provide 'gmail-check)
;;; gmail-check.el ends here
