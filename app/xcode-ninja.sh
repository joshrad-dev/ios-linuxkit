#!/bin/sh

# Try to figure out the user's PATH to pick up their installed utilities.
login_path=$(env -i HOME="$HOME" USER="$USER" SHELL="${SHELL:-/bin/zsh}" /bin/zsh -lc 'print -r -- $PATH' 2>/dev/null || true)
if [ -n "$login_path" ]; then
    export PATH="$PATH:$login_path"
fi

terax_tools=/Users/rcarmo/Build/terax
terax_lld=$terax_tools/.tmp-lld-bottle/lld/22.1.5
terax_llvm=$terax_tools/.tmp-llvm-bottle/llvm/22.1.5
terax_z3=$terax_tools/.tmp-homebrew/Cellar/z3/4.15.4
terax_zstd=$terax_tools/.tmp-homebrew/Cellar/zstd/1.5.7_1
terax_lz4=$terax_tools/.tmp-homebrew/Cellar/lz4/1.10.0
if [ -x "$terax_lld/bin/ld.lld" ] && [ -d "$terax_llvm/lib" ]; then
    export PATH="$terax_lld/bin:$PATH"
    export DYLD_LIBRARY_PATH="$terax_lld/lib:$terax_llvm/lib:$terax_z3/lib:$terax_zstd/lib:$terax_lz4/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
fi

ninja "$@"
