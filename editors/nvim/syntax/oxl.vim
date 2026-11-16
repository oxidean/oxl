" oxl syntax fallback — used when the language server is not attached.
" Mirrors editors/grammars/oxl.tmLanguage.json scope choices.

if exists('b:current_syntax')
  finish
endif

syn case match

syn keyword oxlKeyword control fn struct enum interface extern return if else for let scope spawn go goin spawnBlocking chan select defer match as import package break continue
syn keyword oxlType storage.type int float bool str byte void err cstr own ref mut unsafe nil true false any ordered eq add
syn match   oxlFunctionName "\<fn\s\+\zs\k\+"
syn match   oxlConstant "\<\u\k*\>"
syn match   oxlNumber "\<\d\+\.\d\+\%([eE][+-]\=\d\+\)\?\>"
syn match   oxlNumber "\<\d[\d_]*\>"
syn region  oxlStringD start=+"+ end=+"+ skip=+\\\\\(.\|\n\)+ contains=oxlStringEscape
syn region  oxlStringS start=+'+ end=+'+ skip=+\\\\\(.\|\n\)+ contains=oxlStringEscape
syn match   oxlStringEscape "\\\\\(u[0-9a-fA-F]\{4\}\|x[0-9a-fA-F]\{2\}\|.\)" contained
syn region  oxlCommentBlock start=+/\* end=+\*/ contains=oxlCommentTodo
syn match   oxlCommentLine "+//.*$" contains=oxlCommentTodo
syn keyword oxlCommentTodo TODO FIXME XXX contained

hi def link oxlKeyword        Keyword
hi def link oxlType           Type
hi def link oxlFunctionName   Function
hi def link oxlConstant       Constant
hi def link oxlNumber         Number
hi def link oxlStringD        String
hi def link oxlStringS        String
hi def link oxlStringEscape   SpecialChar
hi def link oxlCommentBlock   Comment
hi def link oxlCommentLine    Comment
hi def link oxlCommentTodo    Todo

let b:current_syntax = 'oxl'
