set backspace=indent,eol,start

" Backup and undo files in dedicated directories
set backup
set undofile
set backupdir=~/.vim/backup//
set backupskip=/tmp/*
set undodir=~/.vim/undo//

set history=1000
set ruler
set showcmd
set incsearch
set number
set autoindent
set expandtab
set tabstop=4
set shiftwidth=4
set softtabstop=4
set wildmenu
set scrolloff=5
set laststatus=2
set ttimeoutlen=50

" Don't use Ex mode, use Q for formatting
nnoremap Q gq

" CTRL-U in insert mode deletes a lot.  Use CTRL-G u to first break undo,
" so that you can undo CTRL-U after inserting a line break.
inoremap <C-U> <C-G>u<C-U>

if has('mouse')
  set mouse=a
endif

syntax on
set hlsearch

filetype plugin indent on

augroup vimrcEx
  au!
  autocmd FileType text setlocal textwidth=78

  " When editing a file, always jump to the last known cursor position.
  autocmd BufReadPost *
    \ if line("'\"") >= 1 && line("'\"") <= line("$") |
    \   exe "normal! g`\"" |
    \ endif
augroup END

" Convenient command to see the difference between the current buffer and the
" file it was loaded from, thus the changes you made.
if !exists(":DiffOrig")
  command DiffOrig vert new | set bt=nofile | r ++edit # | 0d_ | diffthis
		  \ | wincmd p | diffthis
endif
