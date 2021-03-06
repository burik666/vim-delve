" vim-delve - Delve debugger integration

let s:use_termopen = exists('*termopen')
let s:use_term_start = exists('*term_start')
let s:sign_parameters = ""

if !s:use_termopen && !s:use_term_start && !exists("g:loaded_vimshell")
    echom "vim-delve depends on terminal feature or Shougo/vimshell"
    finish
endif

"-------------------------------------------------------------------------------
"                           Configuration options
"-------------------------------------------------------------------------------

" g:delve_cache_path sets the default vim-delve cache path for breakpoint files.
if !exists("g:delve_cache_path")
    let g:delve_cache_path = $HOME ."/.cache/". v:progname ."/vim-delve"
endif

" g:delve_backend is setting the backend to use for the dlv commands.
if !exists("g:delve_backend")
    let g:delve_backend = "default"
endif

" g:delve_breakpoint_sign sets the sign to use in the gutter to indicate
" breakpoints.
if !exists("g:delve_breakpoint_sign")
    let g:delve_breakpoint_sign = "●"
endif

" g:delve_breakpoint_sign_highlight sets the highlight color for the breakpoint
" sign.
if !exists("g:delve_breakpoint_sign_highlight")
    let g:delve_breakpoint_sign_highlight = "WarningMsg"
endif

" g:delve_enable_syntax_highlighting is setting whether or not we should enable
" Go syntax highlighting in the dlv output.
if !exists("g:delve_enable_syntax_highlighting")
    let g:delve_enable_syntax_highlighting = 1
end

" g:delve_new_command is used to create a new window to run the terminal in.
"
" Supported values are:
" - vnew         Opens a vertical window (default)
" - new          Opens a horizontal window
" - enew         Opens a new full screen window
if !exists("g:delve_new_command")
    let g:delve_new_command = "vnew"
endif

" g:delve_tracepoint_sign sets the sign to use in the gutter to indicate
" tracepoints.
if !exists("g:delve_tracepoint_sign")
    let g:delve_tracepoint_sign = "◆"
endif

" g:delve_tracepoint_sign_highlight sets the highlight color for the tracepoint
" sign.
if !exists("g:delve_tracepoint_sign_highlight")
    let g:delve_tracepoint_sign_highlight = "WarningMsg"
endif

" g:delve_sign_group sets the sign group.
if !exists("g:delve_sign_group")
    let g:delve_sign_group = "delve"
endif

" g:delve_sign_priority sets the sign priority.
if !exists("g:delve_sign_priority")
    let g:delve_sign_priority = 10
endif

" g:delve_instructions_file holdes the path to the instructions file. It should
" be reasonably unique.
if !exists("g:delve_instructions_file")
    let g:delve_instructions_file = g:delve_cache_path ."/". getpid() .".". localtime()
endif

" g:delve_use_vimux is setting whether to use vimux to run the dlv command
" in an adjacent tmux pane instead of inside vim.
if !exists("g:delve_use_vimux")
    let g:delve_use_vimux = 0
endif
if g:delve_use_vimux && !exists("g:loaded_vimux")
    echom "vim-delve with g:delve_use_vimux depends on benmills/vimux"
    finish
endif

" Priority and groups are supported since version 8.1.0658.
if has("patch8.1.0658")
    let s:sign_parameters = s:sign_parameters ." group=". g:delve_sign_group
    let s:sign_parameters = s:sign_parameters ." priority=". g:delve_sign_priority
endif

"-------------------------------------------------------------------------------
"                              Implementation
"-------------------------------------------------------------------------------
" delve_instructions holds all the instructions to delve in a list.
let s:delve_instructions = []
" delve_instructions_signs holds instructions sign id
let s:delve_instructions_signs = {}

" Ensure that the cache path exists.
if has('nvim')
    call mkdir(g:delve_cache_path, "p")
else
    let command = "mkdir -p " . g:delve_cache_path . " > /dev/null 2>&1"
    silent call system(command)
endif

" Remove the instructions file
autocmd VimLeave * call delve#removeInstructionsFile()

" Configure the breakpoint and tracepoint signs in the gutter.
exe "sign define delve_breakpoint text=". g:delve_breakpoint_sign ." texthl=". g:delve_breakpoint_sign_highlight
exe "sign define delve_tracepoint text=". g:delve_tracepoint_sign ." texthl=". g:delve_tracepoint_sign_highlight

" addSign adds sign with unique id
function! delve#addSign(instruction, file, line, name)
    let id = eval(max(s:delve_instructions_signs)+1)
    let s:delve_instructions_signs[a:instruction] = id
    exe "sign place ". id . s:sign_parameters ." line=". a:line ." name=". a:name ." file=". a:file
endfunction

" removeSign removes sign by instruction
function! delve#removeSign(instruction)
    let id = remove(s:delve_instructions_signs, a:instruction)
    exe "sign unplace ". id . s:sign_parameters
endfunction

" addBreakpoint adds a new breakpoint to the instructions and gutter. If a
" tracepoint exists at the same location, it will be removed.
function! delve#addBreakpoint(file, line)
    let breakpoint = "break ". a:file .":". a:line
    let tracepoint = "trace ". a:file .":". a:line

    " Remove tracepoints if set on the same line.
    if index(s:delve_instructions, tracepoint) != -1
        call delve#removeTracepoint(a:file, a:line)
    endif

    call add(s:delve_instructions, breakpoint)
    call delve#addSign(breakpoint, a:file, a:line, "delve_breakpoint")
endfunction

" addTracepoint adds a new tracepoint to the instructions and gutter. If a
" breakpoint exists at the same location, it will be removed.
function! delve#addTracepoint(file, line)
    let breakpoint = "break ". a:file .":". a:line
    let tracepoint = "trace ". a:file .":". a:line

    " Remove breakpoint if set on the same line.
    if index(s:delve_instructions, breakpoint) != -1
        call delve#removeBreakpoint(a:file, a:line)
    endif

    call add(s:delve_instructions, tracepoint)

    call delve#addSign(tracepoint, a:file, a:line, "delve_tracepoint")
endfunction

" clearAll is removing all active breakpoints and tracepoints.
function! delve#clearAll()
    for i in s:delve_instructions
        call delve#removeSign(i)
    endfor

    let s:delve_instructions = []
    call delve#removeInstructionsFile()
endfunction

" dlvAttach is attaching dlv to a running process.
"
" Optional arguments:
" flags:        flags takes custom flags to pass to dlv.
function! delve#dlvAttach(pid, ...)
    let flags = (a:0 > 0) ? a:1 : ""

    call delve#runCommand("attach ". a:pid, flags, ".", 0, 0)
endfunction

" dlvConnect is calling dlv connect.
"
" Optional arguments:
" address:      host:port to connect to.
" flags:        flags takes custom flags to pass to dlv.
function! delve#dlvConnect(address, ...)
    let flags = (a:0 > 0) ? a:1 : ""

    call delve#runCommand("connect ". a:address, flags)
endfunction

" dlvCore is calling dlv core.
function! delve#dlvCore(bin, dump, ...)
    let flags = (a:0 > 0) ? a:1 : ""
    call delve#runCommand("core ". a:bin ." ". a:dump, flags)
endfunction

" dlvDebug is calling 'dlv debug' for the currently active main package.
"
" Optional arguments:
" flags:        flags takes custom flags to pass to dlv.
function! delve#dlvDebug(dir, ...)
    let flags = (a:0 > 0) ? join(a:000) : ""

    call delve#runCommand("debug", flags, a:dir)
endfunction

" dlvExec is calling dlv exec.
"
" Optional arguments:
" dir:          dir is the directory to execute from. It's the current dir by
"               default.
" flags:        flags takes custom flags to pass to dlv.
function! delve#dlvExec(bin, ...)
    let dir = (a:0 > 0) ? a:1 : "."
    let flags = (a:0 > 1) ? a:2 : ""
    call delve#runCommand("exec ". a:bin, flags, dir)
endfunction

" dlvTest is calling 'dlv test' for the currently active package.
"
" Optional arguments:
" flags:        flags takes custom flags to pass to dlv.
function! delve#dlvTest(dir, ...)
    let flags = (a:0 > 0) ? join(a:000) : ""

    call delve#runCommand("test", flags, a:dir)
endfunction

" dlvVersion is printing the version of dlv.
function! delve#dlvVersion()
    !dlv version
endfunction

" removeTracepoint deletes a new tracepoint to the instructions and gutter.
function! delve#removeTracepoint(file, line)
    let tracepoint = "trace ". a:file .":". a:line

    let i = index(s:delve_instructions, tracepoint)
    if i != -1
        call remove(s:delve_instructions, i)
        call delve#removeSign(tracepoint)
    endif
endfunction

" removeBreakpoint deletes a new breakpoint to the instructions and gutter.
function! delve#removeBreakpoint(file, line)
    let breakpoint = "break ". a:file .":". a:line

    let i = index(s:delve_instructions, breakpoint)
    if i != -1
        call remove(s:delve_instructions, i)
        call delve#removeSign(breakpoint)
    endif
endfunction

" removeInstructionsFile is removing the defined instructions file. Typically
" called when neovim is exited.
function! delve#removeInstructionsFile()
    call delete(g:delve_instructions_file)
endfunction

" getFile returns the file location either from the expanded path or
" configured 'g:delve_project_root'
function! delve#getFile()
    if !exists("g:delve_project_root")
        return expand('%:p')
    endif

    return g:delve_project_root . expand('%')
endfunction

" runCommand is running the dlv commands.
"
" command:           Is the dlv command to run.
" flags:             String passing additional flags to the command.
" dir:               Path to the cwd.
" init:              Boolean determining if we should append the --init
"                    parameter.
" flushInstructions: Boolean determining if we should flush the in memory
"                    instructions before calling dlv.
function! delve#runCommand(command, ...)
    let flags = (a:0 > 0) ? a:1 : ""
    let dir = (a:0 > 1) ? a:2 : "."
    let init = (a:0 > 2) ? a:3 : 1
    let flushInstructions = (a:0 > 3) ? a:4 : 1

    if (flushInstructions)
        call delve#writeInstructionsFile()
    endif

    let cmd = "cd ". dir . "; "
    let cmd = cmd ."dlv"
    if g:delve_backend != "default"
        let cmd = cmd ." --backend=". g:delve_backend
    endif
    if (init)
        let cmd = cmd ." --init=". g:delve_instructions_file
    endif
    let cmd = cmd ." ". a:command
    if (flags != "")
        let cmd = cmd ." ". flags
    endif

    if g:delve_use_vimux
        let cmd = cmd ."; cd -"
        call VimuxRunCommand(cmd)
    elseif s:use_termopen || s:use_term_start
        if g:delve_new_command == "vnew"
            vnew
        elseif g:delve_new_command == "enew"
            enew
        elseif g:delve_new_command == "new"
            new
        else
            echoerr "Unsupported g:delve_new_command, ". g:delve_new_command
            return
        endif

        if g:delve_enable_syntax_highlighting
            set syntax=go
        end

        if s:use_termopen
            call termopen(cmd)
        else
            call term_start([&shell, &shellcmdflag, cmd], { 'curwin': 1 })
        endif
        startinsert
    else
        if g:delve_new_command == "vnew"
            VimShellBufferDir -split
        elseif g:delve_new_command == "enew"
            enew
            VimShellBufferDir
        elseif g:delve_new_command == "new"
            VimShellBufferDir -popup
        else
            echoerr "Unsupported g:delve_new_command, ". g:delve_new_command
            return
        endif

        exe "VimShellSendString ". cmd
        exe "VimShell"
    endif
endfunction

" toggleBreakpoint is toggling breakpoints at the line under the cursor.
function! delve#toggleBreakpoint(file, line)
    let breakpoint = "break ". a:file .":". a:line

    " Find the breakpoint in the instructions, if available. If it's already
    " there, remove it. If not, add it.
    if index(s:delve_instructions, breakpoint) == -1
        call delve#addBreakpoint(a:file, a:line)
    else
        call delve#removeBreakpoint(a:file, a:line)
    endif
endfunction

" toggleTracepoint is toggling tracepoints at the line under the cursor.
function! delve#toggleTracepoint(file, line)
    let tracepoint = "trace ". a:file .":". a:line

    " Find the tracepoint in the instructions, if available. If it's already
    " there, remove it. If not, add it.
    if index(s:delve_instructions, tracepoint) == -1
        call delve#addTracepoint(a:file, a:line)
    else
        call delve#removeTracepoint(a:file, a:line)
    endif
endfunction

" writeInstructionsFile is persisting the instructions to the set file.
function! delve#writeInstructionsFile()
    call delve#removeInstructionsFile()
    call writefile(s:delve_instructions + ["continue"], g:delve_instructions_file)
endfunction

function! delve#getInitInstructions()
    return s:delve_instructions
endfunction

"-------------------------------------------------------------------------------
"                                 Commands
"-------------------------------------------------------------------------------
command! -nargs=0 DlvAddBreakpoint call delve#addBreakpoint(delve#getFile(), line('.'))
command! -nargs=0 DlvAddTracepoint call delve#addTracepoint(delve#getFile(), line('.'))
command! -nargs=+ DlvAttach call delve#dlvAttach(<f-args>)
command! -nargs=0 DlvClearAll call delve#clearAll()
command! -nargs=+ DlvCore call delve#dlvCore(<f-args>)
command! -nargs=+ DlvConnect call delve#dlvConnect(<f-args>)
command! -nargs=* DlvDebug call delve#dlvDebug(expand('%:p:h'), <f-args>)
command! -nargs=+ DlvExec call delve#dlvExec(<f-args>)
command! -nargs=0 DlvRemoveBreakpoint call delve#removeBreakpoint(delve#getFile(), line('.'))
command! -nargs=0 DlvRemoveTracepoint call delve#removeTracepoint(delve#getFile(), line('.'))
command! -nargs=* DlvTest call delve#dlvTest(expand('%:p:h'), <f-args>)
command! -nargs=0 DlvToggleBreakpoint call delve#toggleBreakpoint(delve#getFile(), line('.'))
command! -nargs=0 DlvToggleTracepoint call delve#toggleTracepoint(delve#getFile(), line('.'))
command! -nargs=0 DlvVersion call delve#dlvVersion()
