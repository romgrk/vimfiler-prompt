" File: vimfiler_prompt.vim
" Author: romgrk
" Description: vimfiler navigation plugin
" Date: 29 Sep 2015
" !::exe [so %]

com! VimFilerPrompt call VimFilerPrompt()

hi! FilerCursor   guifg=#000000 guibg=#efefef gui=NONE

hi! FilerSelected guifg=#efefef guibg=#599eff gui=NONE
hi! FilerActive   guifg=#efefef guibg=#505050 gui=NONE

hi! FilerMatch    guifg=NONE    guibg=NONE    gui=NONE
hi! FilerNoMatch  guifg=#9a9a9a guibg=NONE    gui=NONE

hi! def link FilerPrompt     Question
hi! def link FilerInput      MoreMsg
hi! def link FilerCompletion Comment

fu! VimFilerPrompt (...) " {{{
    if !exists('b:vimfiler') | return | end
    if !exists('b:vimfiler_prompt') || exists('g:debug')
        let b:vimfiler_prompt = s:f.new() | end

    call b:vimfiler_prompt.loop()
endfu " }}}

let g:vimfiler_prompt_prototype = {}
let s:f = g:vimfiler_prompt_prototype
fu! s:f.new () dict " {{{
    return deepcopy(self.init())
endfu " }}}
fu! s:f.init () dict "                      DEFINITIONS HERE {{{
    let _              = self
    let _.lead         = ''               " current input
    let _.currentLine  = -1               " selected/active entry
    let _.isCompleting = 0                " cycling through completion TAB/S-TAB
    let _.hasFocus     = 1                " prompt hasFocus (otherwise on panel)

    let _.files     = {}                  " b:vimfiler.current_files
    let _.index     = -1
    let _.matches   = []
    let _.nomatches = []

    " Options
    let _.singleMatchCompletion = 'confirm'
    let _.cleanMatches          = 1

    " Obscure setting
    let _.printWidth = 0

    return self
endfu " }}}
fu! s:f.reset () dict " {{{
    let _              = self
    let _.lead         = ''
    let _.currentLine  = b:vimfiler.prompt_linenr - 1

    let _.files        = b:vimfiler.current_files
    let _.index        = -1
    let _.matches      = []
    let _.nomatches    = []

    let _.exitLoop     = 0

    if _.isCompleting
        call _.stopCompletion()
    end
    call _.getMatches()
endfu " }}}

" Main loop
fu! s:f.loop () dict " {{{
    try | let _ = self
    call _.reset()
    let char = ''

    while (exists('b:vimfiler') && !_.exitLoop)
        if char == "\<Esc>"
            break
        elseif char == "\<CR>"
            call _.confirm()
        elseif char == "\<Tab>"
            call _.complete(1)
        elseif char == "\<S-Tab>"
            call _.complete(0)
        else
            if _.isCompleting
                call _.stopCompletion() | end
            call _.input(char)
            let ms = _.getMatches()
        end

        if _.exitLoop == 1
            break
        end

        call clearmatches()
        call _.hl_currentLine()
        if len(_.matches) > 1 && !empty(_.lead)
            call _.hl_nomatches()
            call _.hl_matches()
        end
        redraw
        call _.prompt()

        let char = _.getchar()
    endwhile
    call _.exit()
    catch /.*/
        echohl ErrorMsg
        echon '_filer: ' . v:exception | echohl None
    endtry
endfu " }}}
fu! s:f.input (char) dict " {{{
    try
    let _ = self
    let c = a:char

        if c == "/"      | cal _.confirm()
    elseif c == "\<BS>"  | let _.lead = _.lead[0: -2]
    else                 | let _.lead .= c            | end

    if  _.lead =~# '\.\.$' | call _.confirm('..')           | end
    catch /.*/ | echo 'input' . v:exception | endtry
endfu " }}}
fu! s:f.confirm (...) dict " {{{
    try
    let _ = self

    let path = _.lead
    if a:0
        let path = a:1
    elseif len(_.matches)
        let path = _.getFileRelpath(_.currentMatch)
    end

    if !empty(path)
        if isdirectory(b:vimfiler.current_dir . path)
            exe 'VimFiler ' . path
            call _.reset()
        elseif filereadable(b:vimfiler.current_dir . path)
            let _.exitLoop = 1
            let com = b:vimfiler.context.edit_action
            exe com . ' ' . b:vimfiler.current_dir . path
            call _.reset()
        else
            exe 'VimFiler ' . path
            call _.reset()
        endif
    end
    catch /.*/ | echo 'confirm' . v:exception | endtry
endfu " }}}
fu! s:f.prompt () dict " {{{
    try
    let _ = self
    let i = _.index

    let dir = b:vimfiler.current_dir[-20:]
    let lead = _.lead
    let rest  = ' '

    if len(_.matches)
        let mi = (i == -1) ? 0 : i
        let m = _.getFileRelpath(_.matches[mi])
        if m =~? '^' . lead
            let rest = m[len(lead):] . ' '
        end
    end

    let _.printWidth = 1

    call _.print('FilerPrompt', dir)
    call _.print('FilerInput', lead)

    call _.print('FilerCursor', rest[0])
    call _.print('FilerCompletion', rest[1:])

    "call _.print('MoreMsg', "\t\t\tline: " . _.currentLine )
    "call _.print('TextInfo', "\tmid " . _.index . ' [' . len(_.matches) .']')

    let remaining = ( &columns - _.printWidth )
    call _.print('Normal', repeat(' ', remaining))
    catch /.*/ | echo 'prompt' . v:exception | endtry
endfu " }}}

" File matching
fu! s:f.getMatches () dict " {{{
    try
    let _ = self
    let _.index = -1
    let _.matches   = []
    let _.nomatch   = []

    let _.files   = b:vimfiler.current_files
    let _.pattern = '\M^' . escape(_.lead, '^$\')
    for k in range(len(_.files))
        if _.filter(_.files[k])
            call add(_.matches, k)
        else
            call add(_.nomatches, k)
        end
    endfor

    if len(_.matches)
        let _.currentMatch = _.matches[0]
        call _.setCurrentLine(_.getLineNumber(_.matches[0]))
    end

    catch /.*/ | echo 'getMatches '. v:exception | endtry
    return _.matches
endfu " }}}
fu! s:f.filter (vfile) dict " {{{
    return (a:vfile.vimfiler__filename =~? self.pattern)
endfu " }}}

" Completion
fu! s:f.startCompletion () dict " {{{
    let self.initialLead  = self.lead
    let self.index        = -1
    "let self.matches      = a:matches
    let self.isCompleting = 1
endfu " }}}
fu! s:f.stopCompletion () dict " {{{
    if self.initialLead == ''
        let self.lead = ''
    end
    let self.isCompleting = 0
    let self.hasFocus = 1
endfu " }}}
" fu! s:f.complete (direction= { 1 | 0 } )  {{{
"  _.index:  -1: initialLead
"            0: matches[0]
"            1: matches[1]
"            2: ...
fu! s:f.complete (direction) dict
    let _ = self
    let i   = _.index
    let len = len(_.matches)

    if !_.isCompleting
        call _.startCompletion ()
    end

    if len == 0
        call _.stopCompletion()                   | end

    if (a:direction == 1)
        let i += 1
        let i = (i == len) ? -1 : i
    else
        let i -= 1
        let i = (i == -2) ? len-1 : i                 | end

    if i == -1
        let k = _.matches[0]
        let _.lead = _.initialLead
        let _.hasFocus = 1
    else
        let k = _.matches[i]
        let _.lead = _.getFileRelpath(k)
        let _.hasFocus = 0
        if len == 1
            call _.confirm()
        end
    end
    let _.currentMatch = k
    call _.setCurrentLine(_.getLineNumber(k))

    let _.index = i
endfu " }}}

" Completion matches manipulation
"   ,where k:=
"       an index of _.files === b:vimfiler.current_files
fu! s:f.setCurrentLine (lnum) dict " {{{
    let _ = self
    let _.currentLine = a:lnum
    call setpos('.', [0, a:lnum, 0, 0])
endfu " }}}
fu! s:f.getLineNumber (k) dict " {{{
    return vimfiler#get_line_number(a:k)
endfu " }}}
fu! s:f.getFileRelpath (k) dict " {{{
    return self.relative(self.files[a:k].action__path)
endfu " }}}

" Highlight
fu! s:f.highLine (group, lnum, ...) dict " {{{
    let pattern = '\%' . a:lnum . 'l'
    return matchadd(a:group, pattern, (a:0 ? a:1 : 20))
endfu " }}}
fu! s:f.hl_currentLine () dict " {{{
    "if exists('self._lastMatch')
        "call matchdelete(self._lastMatch)
    "end
    let group = 'FilerSelected'
    if self.hasFocus && len(self.matches) > 1
        let group = 'FilerActive'
    end
    if self.currentLine != -1
        let self._lastMatch = self.highLine(group, self.currentLine)
    end
endfu " }}}
fu! s:f.hl_matches () dict " {{{
    let _ = self  | let i = _.index

    for k in _.matches
        if k == _.currentMatch | continue | end
        call _.highLine('FilerMatch', _.getLineNumber(k))
    endfor
endfu " }}}
fu! s:f.hl_nomatches () dict " {{{
    let _ = self  | let i = _.index
    for k in _.nomatches
        let lnum = _.getLineNumber(k)
        if lnum == _.currentLine
            continue
        endif
        call _.highLine('FilerNoMatch', lnum)
    endfor
endfu " }}}

" Utils
fu! s:f.print (hl, text) dict " {{{
    if !empty(a:hl)
        exe 'echohl ' . a:hl
    end
    echon a:text
    let self.printWidth += strdisplaywidth(a:text)
endfu " }}}
fu! s:f.relative (path) dict " {{{
    return substitute(a:path, b:vimfiler.current_dir, '', '')
endfu " }}}
fu! s:f.getchar () dict " {{{
    let char = getchar()
    if char =~ '^\d\+$' | return nr2char(char) | end
    return char
endfu " }}}
fu! s:f.len () dict " {{{
    return len(self.lead)
endfu " }}}
fu! s:f.exit () dict " {{{
    if self.cleanMatches
        call clearmatches() | end
    redraw | echo '' | echo
    call self.print('FilerPrompt', '_filer exited ')
    call self.print('FilerInput', ':)')
endfu " }}}

