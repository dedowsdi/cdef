# cdef

c/c++ plugin.

- Switch between head and source file, function declaration and definition.
- Create function definition from declaration.
- Convert function definition to declaration.
- Generate some common snippets.

Require [universal-ctags](https://github.com/universal-ctags/ctags).

## Configuration

Add this to your `ftplugin/c.vim` or `ftplug/cpp.vim`
```vim
nnoremap <buffer> <f8>       :CdefSwitch<cr>
nnoremap <buffer> _d :CdefDef<cr>
vnoremap <buffer> _d :CdefDef<cr>
nnoremap <buffer> _D :CdefDefAndSwitch<cr>
vnoremap <buffer> _D :CdefDefAndSwitch<cr>
nnoremap <buffer> _p :CdefFuncToProto<cr>
nnoremap <buffer> _P :CdefFuncToProtoAndSwitch<cr>
nnoremap <buffer> _s :CdefCreateSourceFile<cr>
nnoremap <buffer> _h :CdefAddHeadGuard<cr>
nnoremap <buffer> _g :CdefGetSet<cr>
vnoremap <buffer> _g :CdefGetSet<cr>
nnoremap <buffer> _G :CdefConstGetSet<cr>
vnoremap <buffer> _G :CdefConstGetSet<cr>
```
