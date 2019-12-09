if exists("g:loaded_cdef_plugin")
  finish
endif
let g:loaded_cdef_plugin = 1

if !executable('ctags')
  echohl WarningMsg | echom 'CDEF : missing ctags' | echohl None
  finish
endif

com -nargs=* -range CdefDef       : call cdef#def(<line1>, <line2>, <f-args>)
com -nargs=0 CdefSwitch           : call cdef#switch_proto_func()
com -nargs=0 CdefSwitchNext       : call cdef#select_next_candidate()
com -nargs=0 CdefSwitchFile       : call cdef#switch_file()
com -nargs=0 CdefAddHeadGuard     : call cdef#add_head_guard()
com -nargs=0 CdefCreateSourceFile : call cdef#create_source_file()
com -nargs=? -range CdefGetSet           : call cdef#gen_get_set({"register" : <q-args>, "entries" : "gs"}, <line1>, <line2>)
com -nargs=? -range CdefGetSetTog        : call cdef#gen_get_set({"register" : <q-args>, "entries" : "gst"}, <line1>, <line2>)
com -nargs=? -range CdefConstGetSet      : call cdef#gen_get_set({"const"    : 1, "register"       : <q-args>, "entries" : "gs"}, <line1>, <line2>)
com -nargs=? -range CdefConstGetSetTog   : call cdef#gen_get_set({"const"    : 1, "register"       : <q-args>, "entries" : "gst"}, <line1>, <line2>)
