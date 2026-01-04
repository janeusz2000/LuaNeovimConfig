# EXECUTION PLAN FOR THE CODEX PLUGIN INSINDE NEOVIM

You are writing a lua neovim plugin that is going to execute codex in place of 
the buffer. This is a starting point that is going to be expanded in the future.
You are going to write this plugin in `lua/animator/codex.lua`

## How to track progress of the prompt
codex executes prompt into two phases:
- progress phase
- output phase

explaination form documentation:
**While codex exec runs, Codex streams progress to stderr and prints only the 
final agent message to stdout. This makes it straightforward to redirect or 
pipe the final result:**
```
codex exec "generate release notes for the last 10 commits" | tee release-notes.md
```
You will take advantage of this and you will print the progress of the prompt next
to the selection of the prompt and after the prompt is going to finish the execution
you will replace the selection with the output.

## How invoked
The prompt is going to be executed by selection of the buffer and then we will
`<leader>i` (more info in `remap.lua` file) which should put the message 
`"Codex: I got It!"`. Then on every line of "progress"
stage you will erase previous message put by codex and print the next one like 
`Codex: <progress message>` from stderr buffer.

## Prompt creation 
You will create a prompt based on the selection and whole current neovim buffer. 
In a prompt you will include:
- location of the buffer ( via `:lua print(vim.api.nvim_buf_get_name(0))` )
- location of the repo (via `git rev-parse --show-toplevel`)
- location of the cursor (via `vim.api.nvim_win_get_cursor(0)[<line>, <character_number>]`)
- include file type of the modified buffr
we will also allow codex to gatgher the context of the repo to ensure that codex
"understands" the context around the selection

We also want codex to:
- Do not include markdown or backticks,
- Do not include commentary or status lines in the replacement code.  
  (except when we want to explain the which is always very appreciative),

## History
- Every invocation of the codex, should create a tmp file that will contain 
  all the things that are going to enable us to debug what happened inside the 
  codex invocation. We should include everyting verbose there.
- `<leader><leader>i` should open the last log file in neovim so I can see what 
   went wrong. See more info in `remap.lua`

## How to execute codex exec
You will execute the codex via command:
```fish
codexexec --cd 'buffer_file_path' --json "<prompt>"
```
but feel free to check `codex --help` and `codex exec --help` to gather more info
