set nocompatible
filetype off

runtime macros/matchit.vim
    filetype indent plugin on
set is
set encoding=utf-8
set rtp+=~/.vim/bundle/Vundle.vim

call vundle#begin()

Plugin 'VundleVim/Vundle.vim'

Plugin 'junegunn/fzf'

Plugin 'junegunn/fzf.vim'

Plugin 'altercation/vim-colors-solarized'

Plugin 'tpope/vim-surround'

Plugin 'tpope/vim-repeat'

Plugin 'airblade/vim-rooter'

Plugin 'neoclide/coc.nvim', {'branch': 'release'}

Plugin 'leafgarland/typescript-vim'

Plugin 'peitalin/vim-jsx-typescript'

Plugin 'ervandew/supertab'

Plugin 'luochen1990/rainbow'

Plugin 'Yggdroot/indentLine'

Plugin 'mhinz/vim-startify'

Plugin 'edkolev/tmuxline.vim'

Plugin 'tpope/vim-fugitive'

Plugin 'airblade/vim-gitgutter'

Plugin 'Xuyuanp/nerdtree-git-plugin'

Plugin 'hail2u/vim-css3-syntax'

Plugin 'ap/vim-css-color'

Plugin 'alvan/vim-closetag'

"======= eslint
set statusline+=%#warningmsg#
set statusline+=%{SyntasticStatuslineFlag()}
set statusline+=%*
autocmd FileType typescript setlocal completeopt+=menu,preview

" ========= prettier
Plugin 'prettier/vim-prettier'
let g:prettier#autoformat = 1
let g:prettier#autoformat_require_pragma = 0
let g:closetag_filenames = '*.html,*.xhtml,*.xml,*.vue,*.php,*.phtml,*.js,*.jsx,*.coffee,*.erb'

" ========= file tree
Plugin  'scrooloose/nerdtree'

  let NERDTreeIgnore = [ '\.swp', '*\.swp', 'node_modules/' ]
  let NERDTreeShowHidden=1
  let NERDTreeQuitOnOpen=1
  let NERDTreeMinimalUI = 1
  let NERDTreeDirArrows = 1
  let NERDTreeAutoDeleteBuffer = 1
" ========= navigation
Plugin 'christoomey/vim-tmux-navigator'
  " autostart nerd-tree
  autocmd StdinReadPre * let s:std_in=1

  " nerdtree toggle
  map <C-t><C-t> :NERDTreeToggle<CR>
Plugin 'zhaocai/GoldenView.Vim'
  let g:goldenview__enable_default_mapping = 0
Plugin 'benmills/vimux'
  " vimux binding
  map <Leader>Lp :VimuxPromptCommand<CR>
  nmap <F8> :TagbarToggle<CR>

" ======= fuzzy find
Plugin 'ctrlpvim/ctrlp.vim'
set wildignore+=*/tmp/*,*.so,*.swp,*.zip     " MacOSX/Linux
set wildignore+=*\\tmp\\*,*.swp,*.zip,*.exe  " Windows

let g:ctrlp_custom_ignore = '\v[\/]\.(git|hg|svn)$'
let g:ctrlp_custom_ignore = {
  \ 'dir':  '\v[\/]\.(git|hg|svn)$',
  \ 'file': '\v\.(exe|so|dll)$',
  \ 'link': 'some_bad_symbolic_links',
  \ }
let g:ctrlp_user_command = ['.git', 'cd %s && git ls-files -co --exclude-standard']

" ======= extrars
Plugin 'majutsushi/tagbar'
Plugin 'vim-airline/vim-airline'
Plugin 'vim-airline/vim-airline-themes'
Plugin 'mileszs/ack.vim'

let g:indentLine_char = '.'
let g:rainbow_active = 1


map <Leader>vp :VimuxPromptCommand<CR>
map <Leader>vl :VimuxRunLastCommand<CR>
map <Leader>vz :VimuxZoomRunner<CR>

nnoremap <C-J> <C-W><C-J>
nnoremap <C-K> <C-W><C-K>
nnoremap <C-L> <C-W><C-L>
nnoremap <C-H> <C-W><C-H>
set splitbelow
set splitright


" set up ascii fo my startify
let g:startify_custom_header = [
    \ '________              _____                  __  .__    .__',
    \ '\______ \   ____     /  _  \   ____ ___.__._/  |_|  |__ |__| ____    ____',
    \ ' |    |  \ /  _ \   /  /_\  \ /    <   |  |\   __\  |  \|  |/    \  / ___\',
    \ ' |    `   (  <_> ) /    |    \   |  \___  | |  | |   Y  \  |   |  \/ /_/  >',
    \ '/_______  /\____/  \____|__  /___|  / ____| |__| |___|  /__|___|  /\___  / ',
    \  '       \/                 \/     \/\/                \/        \//_____/ ',
    \ ]

autocmd QuickFixCmdPost [^l]* nested cwindow
autocmd QuickFixCmdPost    l* nested lwindow




call vundle#end()            " required
filetype plugin indent on    " required

" Brief help
" " :PluginList       - lists configured plugins
" " :PluginInstall    - installs plugins; append `!` to update or just
" :PluginUpdate
" " :PluginSearch foo - searches for foo; append `!` to refresh local cache
" " :PluginClean      - confirms removal of unused plugins; append `!` to
" auto-approve removal
" "

let mapleader = ","
let g:coc_global_extensions = [
      \ 'coc-tsserver',
      \ 'coc-rls',
      \ 'coc-prettier',
      \ 'coc-eslint',
      \ ]
let g:coc_user_config = {
      \ "coc.preferences.formatOnSaveFiletypes": [
        \ "css",
        \ "markdown",
        \ "javascript",
        \ "javascriptreact",
        \ "typescript",
        \ "typescriptreact",
      \ ],
      \ "suggest.floatEnable": v:false,
      \ "diagnostic.messageTarget": "echo",
      \ }
if !exists('g:airline_symbols')
   let g:airline_symbols = {}
endif
" let g:airline_left_sep = '»'
" let g:airline_left_sep = '▶'
" let g:airline_right_sep = '«'
" let g:airline_right_sep = '◀'
" let g:airline_symbols.crypt = '🔒'
" let g:airline_symbols.linenr = '☰'
" let g:airline_symbols.linenr = '␊'
" let g:airline_symbols.linenr = '␤'
" let g:airline_symbols.linenr = '¶'
" let g:airline_symbols.maxlinenr = ''
" let g:airline_symbols.maxlinenr = '㏑'
" let g:airline_symbols.branch = '⎇'
" let g:airline_symbols.paste = 'ρ'
" let g:airline_symbols.paste = 'Þ'
" let g:airline_symbols.paste = '∥'
" let g:airline_symbols.spell = 'Ꞩ'
" let g:airline_symbols.notexists = 'Ɇ'
" let g:airline_symbols.whitespace = 'Ξ'

let g:airline_powerline_fonts = 1
let g:airline#extensions#tabline#enabled = 1
let g:airline#extensions#tabline#left_sep = ' '
let g:airline#extensions#tabline#left_alt_sep = '|'

" ============= extra settings
syntax on

" tabs to 2 spaces
set smartindent
set tabstop=2
set shiftwidth=2
set expandtab
set ruler
set hidden
:set guioptions-=m " remove menu bar
:set guioptions-=T " remove toolbar
:set guioptions-=r " remove right-hand scroll bar
:set guioptions-=L " remove left-hand scroll bar
":set lines=999 columns=999
set shortmess+=A " disable swap file warning

" hybrid line numbers
set number relativenumber
augroup numbertoggle
  autocmd!
  autocmd BufEnter,FocusGained,InsertLeave * set relativenumber
  autocmd BufLeave,FocusLost,InsertEnter * set norelativenumber
augroup END

let g:solarized_termtrans=1
syntax enable
colorscheme solarized
set background=dark

set splitbelow
" no wrapping
set nowrap

" allow backspace immediately after insert
set bs=2

" useful aliases
cnoreabbrev W w
cnoreabbrev Q q

" save undo in a file
set undofile
set undodir=~/.vim/undo
set undolevels=1000
set undoreload=10000

" tmux will only forward escape sequences to the terminal if surrounded by a
" DCS sequence
" "
" http://sourceforge.net/mailarchive/forum.php?thread_name=AANLkTinkbdoZ8eNR1X2UobLTeww1jFrvfJxTMfKSq-L%2B%40mail.gmail.com&forum_name=tmux-users
if exists('$TMUX')
  let &t_SI = "\<Esc>Ptmux;\<Esc>\<Esc>]50;CursorShape=1\x7\<Esc>\\"
  let &t_EI = "\<Esc>Ptmux;\<Esc>\<Esc>]50;CursorShape=0\x7\<Esc>\\"
else
  let &t_SI = "\<Esc>]50;CursorShape=1\x7"
  let &t_EI = "\<Esc>]50;CursorShape=0\x7"
endif

" Folding
augroup XML
    autocmd!
    autocmd FileType xml setlocal foldmethod=indent foldlevelstart=999 foldminlines=0
augroup END

map ; :Files<CR>
