Small Mac app to upload files to a server over SFTP after dragging them to the status bar or the dock.

Simplified BSD license.

To do:
- Build preferences for things such as:
	- An option to hide the dock icon (or the menubar item)
	- Disable Notification Center notifications
	- Optionally 'obsfucate' URLs somehow (shasum the file name, with the file size as a salt?)
- Support plain FTP (through CFNetworking)
- Keep track of recent uploads to re-copy their links
	- This should work through the Dock's recent items and a menu on the status item.
- Make a .zip if multiple files are dragged into the app

Notes:
- This project uses git submodules, not cocoapods. Try `git clone git@github.com:zadr/Sharer.git --recursive`, or if you've already cloned the repo, run `git submodule update --init --recursive` from it's root.