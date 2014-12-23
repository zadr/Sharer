Small Mac app to upload files to an SFTP server after dragging them to the status bar or the dock.

Simplified BSD license.

To do:
- Build preferences for things such as:
	- An option to hide the dock icon
	- A way to configure the server/port/username/password to upload to, so we don't have to hardcode anything into the app
- Support plain FTP (through CFNetworking) and SCP (through NMSSH) as well.

Since there aren't any preferences yet (see to do directly above this paragraph), you should edit AppDelegate.m to set things up before you build. Prefs will be built soon.