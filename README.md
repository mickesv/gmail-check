# gmail-check
Check number of unread gmail and retrieve headers

Poll GMail's Atom feed to find out how many new mails there are.
Put names <emails> :: Titles where you want it
Adds unread mailcount to modeline.
(optionally) alert when mails from certain people arrive.

# Instructions

Put this in your init.el - file:

```
(require 'gmail-check)
```


Initialise the package
This will add a gmail counter to the modeline:

```
(gmail-check)
```


Add a regexp of a name to watch especially
This will change the colour of the gmail counter
and add the name to the help text when hovering over
it with the mouse pointer.:

```
(add-to-list 'gmail-check-watch '("RegexpName" . nil))
```

You may also wish to call a function:

```
(add-to-list 'gmail-check-watch '("BossName" . flashCurrentBufferEgregiously))
```

gmail-check is normally silent, but if you wish to
output the headers somehow.
Output to a temp buffer:

```
(add-to-list 'gmail-check-output-functions 'gmail-check-do-output-default)
```

Output to two files, e.g. for use by geektools:

```
(add-to-list 'gmail-check-output-functions 'gmail-check-do-output-file)
```

The directory and the root of the filenames are set in the variable
`gmail-check-ootput-file-root`. Default is "/tmp/gmail-check"

