# cdef

## Synopsis

Based on [universal-ctags](https://github.com/universal-ctags/ctags).
Define function in proper position in head or source file.
Switch between head and source file.
Switch between prototype and function.

## Screen Shots

## Install

Use [vim-plug](https://github.com/junegunn/vim-plug) or whatever you like.

Put this in your .vimrc
```vim
nmap <leader>de <Plug>CdefDefineTag
vmap <leader>de <Plug>CdefDefineRange
nmap <leader>df <Plug>CdefDefineFile
```
