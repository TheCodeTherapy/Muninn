# Odin + Raylib boilerplate

This is an Odin + Raylib game boilerplate, that aims to offer support for hot reloading and webassembly builds.

## Features I aimed for this boilerplate:

- ### Single-file Webassembly build

For the Webassembly builds, I've chosen to allow for some overhead in terms of bundle size to obtain the advantage of generating a single self-contained HTML file with everything that is necessary to run the game (including the compiled WASM file and all the assets as base64 strings in the script tag inlined to the HTML file). I'm also including auxiliary scripts and other minor things (like the favicon used by the HTML file, also as a base64 string URI).

That, IMHO, offers the convenience of running the game just by opening the HTML file locally in a web browser (just by double-clicking the file on your file manager), without the need to serve the files to comply with browser policies that would prevent loading the need files directly from the disk.

- ### Hot-reload on save

Instead of having to manually run the hot-reload build script (or trigger its execution through a bind-key) after saving changes to your code, I've chosen to implement a minimal build logic that monitors the source files and triggers the hot-reload build automatically once any changes are detected to any of the source files.

## About the original project

The project is an adaptation of the original [Karl Zylinski](https://github.com/karl-zylinski)'s project, that you may find [here](https://github.com/karl-zylinski/odin-raylib-hot-reload-game-template). My version aims to adjust its functionality to fit my personal development workflow and choices better, but you should definitely check out his work.

Karl is a prolific author and game developer who specializes in Odin and Raylib. Reading his book (which you can find [here](https://odinbook.com/)) was invaluable for my incredibly easy transition from C++ to Odin to develop my Raylib projects. If you're interested in Odin, please consider supporting Karl by [buying his book](https://odinbook.com/) or checking out [his game](https://store.steampowered.com/app/2781210/CAT__ONION/) built with Odin + Raylib on Steam.
