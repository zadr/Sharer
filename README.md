Small Mac app to upload files to a server over SFTP after dragging them to the status bar or the dock.

Simplified BSD license.

To do:
- Build preferences for things such as:
	- An option to hide the dock icon
- Support plain FTP (through CFNetworking)
- Keep track of recent uploads to re-copy them
	- This should work through the Dock's recent items and a menu on the status item.

Notes:
- This project uses git submodules, not cocoapods. Try `git clone git@github.com:zadr/Sharer.git --recursive`, or if you've already cloned the repo, run `git submodule update --init --recursive` from it's root.