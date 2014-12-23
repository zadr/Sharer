Small Mac app to upload files to a server over SFTP after dragging them to the status bar or the dock.

Simplified BSD license.

To do:
- Make a .zip if multiple files are dragged into the app
- Option to select pubkey instead of defaulting to it being in ~/.ssh

Notes:
- This project uses git submodules, not cocoapods. Try `git clone git@github.com:zadr/Sharer.git --recursive`, or if you've already cloned the repo, run `git submodule update --init --recursive` from it's root.