# DJMN TV

**DJMN TV** is a single-file Windows batch launcher that turns **VLC media player** into a curated, self-updating live TV playlist.

The intended experience is:

```text
Double-click DJMN_TV.bat
        ↓
Install VLC if missing
        ↓
Build or update the channel playlist
        ↓
Open VLC with DJMN TV ready to watch
```

DJMN TV is designed for normal Windows users who do not want to manually manage M3U playlist files.

---

## Features

- One-file Windows `.bat` launcher
- Uses VLC as the video player
- Automatically detects VLC if it is already installed
- Attempts to install VLC with `winget` if VLC is missing
- Downloads current public IPTV metadata from IPTV-org
- Builds a curated English-language M3U playlist
- Stores all working files in the user's local AppData folder
- Updates the playlist automatically when it is missing, stale, or from an older build
- Falls back to the last working playlist if an update fails
- Opens VLC directly into the generated playlist
- Does not create extra files on the Desktop

---

## Main Goal

DJMN TV is not meant to be the biggest IPTV playlist possible.

The goal is to create a curated English-language TV lineup that feels closer to a cable-style channel package.

The playlist is designed around categories people actually browse:

- local
- News
- Weather
- Movies
- TV shows
- Sports
- Science
- History
- Nature
- Kids
- Anime
- Music
- Cooking
- Travel
- Cars
- Outdoors
- Relaxation channels

The playlist is designed to be simple enough for an older viewer to use, while still being useful for general English-language viewing.

---

## Requirements

### Required

- Windows 10 or Windows 11
- Internet connection for first setup and playlist updates
- PowerShell
- VLC media player

### Optional

- `winget`

If `winget` is available and VLC is missing, DJMN TV attempts to install VLC automatically.

If `winget` is not available, the script opens the official VLC download page and waits for the user to install VLC manually.

---

## Installation

1. Download `DJMN_TV.bat`.
2. Place it on the Desktop or in any folder.
3. Double-click it.

That is the full install process.

No separate `.ps1` file is required. The PowerShell updater is embedded inside the `.bat` file and extracts itself automatically.

---

## Where Files Are Saved

DJMN TV does **not** save extra files to the Desktop.

It creates and uses this folder:

```text
%LOCALAPPDATA%\DJMN_TV
```

Usually that resolves to something like:

```text
C:\Users\<YourUserName>\AppData\Local\DJMN_TV
```

The folder may contain:

```text
DJMN_TV.m3u
DJMN_TV_selection.json
DJMN_TV_Core.ps1
DJMN_TV.log
DJMN_TV_build_version.txt
```

### File Purposes

| File | Purpose |
|---|---|
| `DJMN_TV.m3u` | The generated VLC playlist |
| `DJMN_TV_selection.json` | Debug/metadata file showing selected channels |
| `DJMN_TV_Core.ps1` | The extracted PowerShell engine embedded in the BAT |
| `DJMN_TV.log` | Runtime and update log |
| `DJMN_TV_build_version.txt` | Tracks which script version generated the current playlist |

---

## How Updating Works

DJMN TV checks the playlist every time it launches.

It rebuilds the playlist when:

- The playlist does not exist.
- The playlist is older than 24 hours.
- The current playlist was built by an older DJMN TV build version.

Otherwise, it opens VLC immediately using the existing playlist.

```text
Launch
  ↓
Check VLC
  ↓
Check playlist
  ↓
Missing, old, or wrong build?
  ├─ Yes → rebuild playlist, then launch VLC
  └─ No  → launch VLC immediately
```

---

## Failure Protection

DJMN TV uses a safe update flow.

When rebuilding the playlist, it first writes temporary files:

```text
DJMN_TV.m3u.tmp
DJMN_TV_selection.json.tmp
```

Only after the build succeeds does it replace the active playlist.

If an update fails, the script keeps the existing working playlist and launches VLC anyway.

This prevents the playlist from being wiped out by a bad network request, temporary API issue, or interrupted update.

---

## Channel Source

DJMN TV currently uses the public IPTV-org API:

```text
https://iptv-org.github.io/api/channels.json
https://iptv-org.github.io/api/streams.json
https://iptv-org.github.io/api/feeds.json
https://iptv-org.github.io/api/logos.json
https://iptv-org.github.io/api/cities.json
```

The script uses these files to discover:

- Channel metadata
- Stream URLs
- Feed language metadata
- Logos
- Minnesota city and broadcast metadata

---

## Language Rule

DJMN TV is built as an **English-only** playlist.

A channel or feed is allowed only when English is detected in IPTV-org metadata.

The script checks for:

```text
eng
english
```

It checks both feed-level and channel-level metadata.

The intended rule is:

```text
English feed from the United States      Allowed
English feed from Canada                 Allowed
English feed from the United Kingdom     Allowed
English feed from Australia              Allowed
English feed from anywhere else          Allowed

Non-English feed from any country        Blocked
Unknown-language feed                    Blocked
```

Country does not matter. The feed language does.

---

## Channel Count

The current wide build targets up to:

```text
2200 channels
```

Actual channel count can vary depending on what IPTV-org exposes at the time of launch.

The script may select fewer than 2200 channels if there are not enough matching English streams after filtering.

---

## Category Layout

The generated playlist is grouped into VLC categories.

```text
01 Minnesota Local
02 News
03 Weather

04 Movies - Action
05 Movies - Comedy
06 Movies - Horror
07 Movies - Sci-Fi
08 Movies - Christmas
09 Movies - Classics
10 Movies - General

11 TV Shows - Crime
12 TV Shows - Sitcoms
13 TV Shows - Reality
14 TV Shows - Game Shows
15 TV Shows - Classic TV

16 Sports
17 Science
18 History
19 Nature

20 Kids
21 Anime
22 Music
23 Cooking
24 Travel
25 Cars
26 Outdoors

27 Relaxation - Aquarium
28 Relaxation - Fireplace
29 Relaxation - Space
30 Relaxation - Nature
```

In VLC, press:

```text
Ctrl + L
```

to view the playlist/channel list.

---

## Content Priorities

DJMN TV favors watchable, familiar, cable-like free streaming channels.

Examples of favored sources and channel families include:

```text
Pluto TV
Plex
Tubi
Samsung TV Plus
Xumo
Roku
Amazon Freevee
FilmRise
Cinevault
MovieSphere
The Film Detective
Maverick
Gravitas
Comet
Charge!
Grit
Bounce
Laff
MeTV
Movies!
ION
Court TV
PBS
NASA
WeatherNation
AccuWeather
NBC News
CBS News
ABC News
BBC News
Sky News
Bloomberg
Reuters
Tastemade
Vevo
Stingray
beIN SPORTS XTRA
Fubo Sports
Rally TV
Racer
RetroCrush
Anime All Day
Shout TV
Midnight Pulp
Popcornflix
Crackle
MST3K
RiffTrax
```

The intent is to keep channels people might actually stop and watch, rather than simply importing every possible stream.

---

## Movie and TV Tuning

The wide build gives extra priority to specific channel families.

### Movie Sources

```text
Pluto
Plex
Tubi
Samsung TV Plus
Xumo
Roku
FilmRise
Cinevault
MovieSphere
The Film Detective
Maverick
Gravitas
Comet
Grit
Charge!
Movies!
```

### Sci-Fi / Geek TV

```text
Star Trek
Stargate
Doctor Who
The X-Files
Battlestar
Babylon 5
Farscape
The Outer Limits
Comet
DUST
```

### Anime

```text
RetroCrush
Crunchyroll
Anime All Day
Naruto
Dragon Ball
Gundam
Sailor Moon
Pokémon
Yu-Gi-Oh
One Piece
Bleach
Beyblade
Digimon
```

### Classic TV

```text
MeTV
Bonanza
Gunsmoke
Andy Griffith
Perry Mason
Little House
M*A*S*H
Carol Burnett
Johnny Carson
The Rifleman
Rawhide
The Lone Ranger
The Beverly Hillbillies
```

---

## What Gets Filtered Out

DJMN TV attempts to remove or avoid:

```text
Shopping channels
Religious channels
Government/civic access
City council streams
School board streams
Radio-only streams
Security cameras
Webcams
Test streams
Backup streams
Geo-blocked streams
Closed channels
NSFW channels
Obvious numeric-IP restreams
Known unstable/restream-heavy hosts
Non-English feeds
```

This filtering is rule-based, so it is not perfect.

Some unwanted channels may still appear, and some useful channels may occasionally be excluded if their metadata is incomplete.

---

## Premium Cable Channels

DJMN TV does **not** intentionally import unauthorized premium cable restreams.

Examples:

```text
HBO
Cinemax
Showtime
Starz
Encore
Epix / MGM+
ESPN
NFL Network
NBA TV
MLB Network
NHL Network
```

These are generally paid subscription channels. Public free IPTV versions are usually unauthorized restreams, unstable, and not appropriate for a public GitHub project.

The script instead prioritizes legitimate free movie and TV-style channels from FAST providers such as:

```text
Pluto
Plex
Tubi
Roku
Samsung TV Plus
Xumo
FilmRise
Cinevault
Crackle
Popcornflix
Shout TV
Midnight Pulp
```

---

## VLC Auto-Install Behavior

When VLC is missing, DJMN TV checks for `winget`.

If `winget` exists, it runs:

```bat
winget install --id VideoLAN.VLC -e --source winget --silent --accept-package-agreements --accept-source-agreements
```

Depending on Windows security settings, this may trigger a UAC prompt.

If `winget` is unavailable or VLC is not detected after installation, DJMN TV opens the official VLC download page and waits for the user to install VLC manually.

---

## VLC Detection

DJMN TV checks multiple locations for VLC:

```text
C:\Program Files\VideoLAN\VLC\vlc.exe
C:\Program Files (x86)\VideoLAN\VLC\vlc.exe
PATH entry for vlc.exe
Windows App Paths registry entries
```

If VLC is found, the script launches it with:

```text
DJMN_TV.m3u
```

---

## Generated M3U Format

Each channel entry is written in extended M3U format.

Example:

```m3u
#EXTINF:-1 tvg-id="Example.us" tvg-name="Example Channel" tvg-logo="https://example.com/logo.png" group-title="10 Movies - General",Example Channel
https://example.com/live/playlist.m3u8
```

Some streams may also include VLC-specific options:

```m3u
#EXTVLCOPT:http-referrer=https://example.com/
#EXTVLCOPT:http-user-agent=Mozilla/5.0
```

---

## Troubleshooting

### VLC does not open

Check whether VLC is installed.

You can also open:

```text
%LOCALAPPDATA%\DJMN_TV
```

and double-click:

```text
DJMN_TV.m3u
```

If Windows asks what app to use, choose VLC.

---

### Playlist seems too small

Delete or rename this file:

```text
%LOCALAPPDATA%\DJMN_TV\DJMN_TV.m3u
```

Then run `DJMN_TV.bat` again.

This forces a rebuild.

---

### Playlist does not update

Delete this file:

```text
%LOCALAPPDATA%\DJMN_TV\DJMN_TV_build_version.txt
```

Then run `DJMN_TV.bat` again.

---

### A channel does not play

Some public IPTV streams go offline, move, or break.

Run the BAT again after 24 hours, or delete the playlist file to force an immediate rebuild.

---

### Script opens and closes quickly

Open Command Prompt and run:

```bat
cd %USERPROFILE%\Desktop
DJMN_TV.bat
```

Then check the log:

```text
%LOCALAPPDATA%\DJMN_TV\DJMN_TV.log
```

---

## Uninstall

Delete the desktop BAT file.

Then delete this folder:

```text
%LOCALAPPDATA%\DJMN_TV
```

No registry changes or system services are created by DJMN TV.

If DJMN TV installed VLC and you no longer want VLC, uninstall it from Windows:

```text
Settings → Apps → Installed apps → VLC media player → Uninstall
```

---

## Privacy

DJMN TV does not require an account.

The script:

- Downloads public IPTV-org JSON data
- Writes playlist files locally
- Launches VLC
- Does not upload user files
- Does not collect analytics
- Does not track viewing history
- Does not create a background service

VLC and stream providers may make ordinary network requests when a user plays a channel.

---

## Security Notes

This is a Windows batch script that extracts and runs embedded PowerShell.

That is intentional because the project is designed to be distributed as a single `.bat` file.

Users should review the script before running it.

Recommended safety practices:

- Download only from a trusted GitHub repository
- Review the `.bat` before launching
- Avoid running it as Administrator unless absolutely necessary
- Do not add unauthorized premium-channel sources
- Keep Windows and VLC updated

---

## Known Limitations

- VLC is a player, not a full cable-box interface.
- VLC can browse M3U channel groups, but it does not provide a polished XMLTV grid guide.
- Public IPTV streams can change or disappear.
- Metadata quality depends on IPTV-org data.
- Filtering is rule-based and may need tuning over time.
- Some legitimate channels may be missed if their metadata is incomplete.
- Some unwanted channels may slip through if their names do not match the filter rules.

---

## Recommended Repository Layout

```text
DJMN-TV/
├── DJMN_TV.bat
├── README.md
├── LICENSE
└── screenshots/
    └── optional-vlc-playlist-view.png
```

Optional future files:

```text
docs/
├── FILTERING.md
├── CHANGELOG.md
└── TROUBLESHOOTING.md
```

---

## Suggested GitHub Description

```text
One-click Windows BAT that turns VLC into a self-updating, English-only curated live TV playlist.
```

---

## Suggested Topics

```text
vlc
iptv
m3u
windows
batch
powershell
playlist
live-tv
fast-channels
iptv-org
```

---

## Disclaimer

DJMN TV is a playlist generator and launcher for publicly available streams.

It does not host video content.

It does not bypass subscriptions, logins, DRM, geographic restrictions, or paywalls.

Channel availability depends on third-party public stream metadata and upstream stream providers.

Premium subscription channels are intentionally not included unless a legitimate public source is available.
