if exists("g:loaded_cdef_plugin")
  finish
endif
let g:loaded_cdef_plugin = 1

if !executable('ctags')
  echohl WarningMsg | echom 'CDEF : missing ctags' | echohl None
endif

command! -nargs=* -range CdefDef       : call cdef#def(<line1>, <line2>, <f-args>)
command! -nargs=0 CdefSwitch           : call cdef#switchProtoFunc()
command! -nargs=0 CdefSwitchNext       : call cdef#selectNextCandidate()
command! -nargs=0 CdefSwitchFile       : call cdef#switchFile()
command! -nargs=0 CdefAddHeadGuard     : call cdef#addHeadGuard()
command! -nargs=0 CdefCreateSourceFile : call cdef#createSourceFile()
command! -nargs=? CdefGetSet           : call cdef#genGetSet({"register" : <q-args>, "entries" : "gs"})
command! -nargs=? CdefGetSetTog        : call cdef#genGetSet({"register"  : <q-args>, "entries" : "gst"})
command! -nargs=? CdefConstGetSet      : call cdef#genGetSet({"const"     : 1, "register"       : <q-args>, "entries" : "gs"})
command! -nargs=? CdefConstGetSetTog   : call cdef#genGetSet({"const"     : 1, "register"       : <q-args>, "entries" : "gst"})
