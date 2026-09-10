@echo off
setlocal
title DJMN TV
rem DJMN TV single-file build v3.0.1 - fixed self-extraction marker handling

set "APPDIR=%LOCALAPPDATA%\DJMN_TV"
if not exist "%APPDIR%" mkdir "%APPDIR%" >nul 2>&1

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$bat='%~f0'; $out=Join-Path $env:LOCALAPPDATA 'DJMN_TV\DJMN_TV_Core.ps1'; $raw=Get-Content -LiteralPath $bat -Raw; $marker='###__DJMN_TV_POWERSHELL_BELOW__###'; $idx=$raw.LastIndexOf($marker); if($idx -lt 0){Write-Host 'DJMN TV internal script marker missing.'; exit 20}; $ps=$raw.Substring($idx + $marker.Length); Set-Content -LiteralPath $out -Value $ps -Encoding UTF8; & $out"
set "EC=%ERRORLEVEL%"

if not "%EC%"=="0" (
    echo.
    echo DJMN TV exited with error code %EC%.
    echo.
    pause
)

exit /b %EC%
###__DJMN_TV_POWERSHELL_BELOW__###

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$AppName = "DJMN TV"
$AppDir = Join-Path $env:LOCALAPPDATA "DJMN_TV"
$PlaylistPath = Join-Path $AppDir "DJMN_TV.m3u"
$SelectionPath = Join-Path $AppDir "DJMN_TV_selection.json"
$LogPath = Join-Path $AppDir "DJMN_TV.log"
$VersionPath = Join-Path $AppDir "DJMN_TV_build_version.txt"
$ApiRoot = "https://iptv-org.github.io/api"
$TargetCount = 2200
$UpdateHours = 24
$BuildVersion = "3.0.2-WIDE"

New-Item -ItemType Directory -Path $AppDir -Force | Out-Null

function Write-Log([string]$Message) {
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}

function Say([string]$Message) {
    Write-Host $Message
    Write-Log $Message
}

function Get-VlcPath {
    $paths = New-Object System.Collections.Generic.List[string]

    if ($env:ProgramFiles) {
        $paths.Add((Join-Path $env:ProgramFiles "VideoLAN\VLC\vlc.exe"))
    }
    $pf86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
    if ($pf86) {
        $paths.Add((Join-Path $pf86 "VideoLAN\VLC\vlc.exe"))
    }

    foreach ($p in $paths) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }

    $cmd = Get-Command "vlc.exe" -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source)) { return $cmd.Source }

    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\vlc.exe",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\vlc.exe",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\vlc.exe"
    )
    foreach ($r in $regPaths) {
        try {
            $v = (Get-ItemProperty -Path $r -ErrorAction Stop)."(default)"
            if ($v -and (Test-Path -LiteralPath $v)) { return $v }
        } catch {}
    }

    return $null
}

function Install-VLC {
    Say "VLC was not found."

    $winget = Get-Command "winget.exe" -ErrorAction SilentlyContinue
    if ($winget -and $winget.Source) {
        Say "Installing VLC with winget..."
        Say "A Windows/UAC prompt may appear depending on this PC's security settings."

        try {
            & $winget.Source install --id VideoLAN.VLC -e --source winget --silent --accept-package-agreements --accept-source-agreements
            $exit = $LASTEXITCODE
            Write-Log "winget install exit code: $exit"
        } catch {
            Write-Log "winget install threw an exception: $($_.Exception.Message)"
        }

        Start-Sleep -Seconds 3
        $vlc = Get-VlcPath
        if ($vlc) {
            Say "VLC install detected."
            return $vlc
        }

        Say "VLC was not detected after winget finished."
    }
    else {
        Say "winget is not available on this PC."
    }

    Say "Opening the official VLC download page."
    Start-Process "https://www.videolan.org/vlc/" | Out-Null
    Write-Host ""
    Write-Host "Install VLC, then press ENTER here to continue."
    Read-Host | Out-Null

    $vlc = Get-VlcPath
    if ($vlc) { return $vlc }

    throw "VLC is still not installed or was not detected."
}

function Get-ApiJson([string]$Name) {
    $url = "$ApiRoot/$Name.json"
    Say "  -> $Name"
    return @(Invoke-RestMethod -Uri $url -UseBasicParsing -TimeoutSec 120)
}

function Get-HostName([string]$Url) {
    try { return ([Uri]$Url).Host.ToLowerInvariant() } catch { return "" }
}

function As-Array($Value) {
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value) }
    return @($Value)
}

function Has-Eng($Obj) {
    if ($null -eq $Obj) { return $false }
    $langs = @()
    foreach ($field in @("languages","language")) {
        try {
            if ($Obj.PSObject.Properties.Name -contains $field) {
                $langs += @(As-Array $Obj.$field)
            }
        } catch {}
    }
    foreach ($l in $langs) {
        if ([string]$l -eq "eng") { return $true }
        if ([string]$l -match '(^|[,;\s])eng($|[,;\s])') { return $true }
        if ([string]$l -match 'english') { return $true }
    }
    return $false
}

function Get-QualityScore([string]$Quality) {
    if (-not $Quality) { return 0 }
    if ($Quality -match "4320") { return 18 }
    if ($Quality -match "2160") { return 16 }
    if ($Quality -match "1440") { return 13 }
    if ($Quality -match "1080") { return 11 }
    if ($Quality -match "720")  { return 9 }
    if ($Quality -match "576")  { return 6 }
    if ($Quality -match "540")  { return 5 }
    if ($Quality -match "480")  { return 4 }
    if ($Quality -match "360")  { return 2 }
    return 1
}

function Escape-M3U([string]$Text) {
    if ($null -eq $Text) { return "" }
    return ($Text -replace '"', "'")
}

function Test-Regex([string]$Text, [string]$Pattern) {
    if (-not $Pattern) { return $false }
    if (-not $Text) { return $false }
    return ($Text -match $Pattern)
}

function First-NonEmpty([object[]]$Values) {
    foreach ($v in $Values) {
        if ($null -ne $v -and -not [string]::IsNullOrWhiteSpace([string]$v)) {
            return [string]$v
        }
    }
    return ""
}

Clear-Host
Say "==============================================="
Say " DJMN TV - One-click VLC TV launcher"
Say " Build $BuildVersion"
Say "==============================================="
Say ""

$vlcPath = Get-VlcPath
if (-not $vlcPath) {
    $vlcPath = Install-VLC
}
Say "VLC: $vlcPath"
Say ""

$needsUpdate = $false

if (-not (Test-Path -LiteralPath $PlaylistPath)) {
    $needsUpdate = $true
    Say "Playlist missing. Building DJMN TV."
}
else {
    $age = (Get-Date) - (Get-Item -LiteralPath $PlaylistPath).LastWriteTime
    $existingVersion = ""
    if (Test-Path -LiteralPath $VersionPath) {
        try { $existingVersion = (Get-Content -LiteralPath $VersionPath -Raw).Trim() } catch { $existingVersion = "" }
    }

    if ($existingVersion -ne $BuildVersion) {
        $needsUpdate = $true
        Say ("Playlist was built by '{0}'. Current launcher is '{1}'. Rebuilding now." -f $existingVersion, $BuildVersion)
    }
    elseif ($age.TotalHours -ge $UpdateHours) {
        $needsUpdate = $true
        Say ("Playlist is {0:N1} hours old. Updating first." -f $age.TotalHours)
    }
    else {
        Say ("Playlist is fresh ({0:N1} hours old). Launching now." -f $age.TotalHours)
    }
}

# Main builder. Kept inside a function so failures can fall back cleanly.
function Build-DJMN-TV {
    Say ""
    Say "Refreshing English-only curated channel list..."
    Say "Pulling current IPTV-org API data..."

    $channels = Get-ApiJson "channels"
    $streams  = Get-ApiJson "streams"
    $feeds    = Get-ApiJson "feeds"
    $logos    = Get-ApiJson "logos"
    $cities   = Get-ApiJson "cities"

    $channelById = @{}
    foreach ($c in $channels) {
        if ($c.id) { $channelById[[string]$c.id] = $c }
    }

    $feedByKey = @{}
    $mainFeedsByChannel = @{}
    foreach ($f in $feeds) {
        if (-not $f.channel) { continue }
        $key = "$($f.channel)|$($f.id)"
        $feedByKey[$key] = $f
        if ($f.is_main -eq $true -and -not $mainFeedsByChannel.ContainsKey([string]$f.channel)) {
            $mainFeedsByChannel[[string]$f.channel] = $f
        }
    }

    $logosByChannel = @{}
    foreach ($l in $logos) {
        if (-not $l.channel -or -not $l.url) { continue }
        $cid = [string]$l.channel
        if (-not $logosByChannel.ContainsKey($cid)) {
            $logosByChannel[$cid] = New-Object System.Collections.ArrayList
        }
        [void]$logosByChannel[$cid].Add($l)
    }

    $mnCityAreas = New-Object System.Collections.Generic.HashSet[string]
    foreach ($city in $cities) {
        if ($city.subdivision -eq "US-MN" -and $city.code) {
            [void]$mnCityAreas.Add("ct/$($city.code)")
        }
    }

    function Get-FeedInfo($s) {
        if ($s.feed) {
            $k = "$($s.channel)|$($s.feed)"
            if ($feedByKey.ContainsKey($k)) { return $feedByKey[$k] }
        }
        if ($mainFeedsByChannel.ContainsKey([string]$s.channel)) { return $mainFeedsByChannel[[string]$s.channel] }
        return $null
    }

    function Test-EnglishChannel($channel, $feedInfo) {
        # Hard preference: feed says English.
        if (Has-Eng $feedInfo) { return $true }

        # Fallback: channel-level language says English.
        if (Has-Eng $channel) { return $true }

        # Do not blindly accept unknown language. This keeps the playlist English-only.
        return $false
    }

    function Test-Minnesota($stream, $channel, $feedInfo) {
        $combined = "$($stream.title) $($channel.name) $($channel.id) $($channel.subdivision) $($channel.city)"
        if ($combined -match "Minnesota|Minneapolis|Saint Paul|St\. Paul|Twin Cities|Duluth|Rochester|Mankato|Maple Grove|KMSP|WCCO|KARE|KSTP|KTCA|KTCI|CCX") {
            return $true
        }
        if ($null -ne $feedInfo) {
            foreach ($area in @(As-Array $feedInfo.broadcast_area)) {
                if ([string]$area -eq "s/US-MN" -or $mnCityAreas.Contains([string]$area)) { return $true }
            }
        }
        return $false
    }

    function Get-LogoUrl([string]$ChannelId, [string]$FeedId) {
        if (-not $logosByChannel.ContainsKey($ChannelId)) { return "" }
        $all = @($logosByChannel[$ChannelId])
        if ($FeedId) {
            $exact = @($all | Where-Object { $_.feed -eq $FeedId -and $_.in_use -eq $true } | Sort-Object width -Descending)
            if ($exact.Count -gt 0) { return [string]$exact[0].url }
        }
        $main = @($all | Where-Object { (-not $_.feed) -and $_.in_use -eq $true } | Sort-Object width -Descending)
        if ($main.Count -gt 0) { return [string]$main[0].url }
        $any = @($all | Where-Object { $_.in_use -eq $true } | Sort-Object width -Descending)
        if ($any.Count -gt 0) { return [string]$any[0].url }
        if ($all.Count -gt 0) { return [string]$all[0].url }
        return ""
    }

    $trustedProviderRegex = @(
        "pluto",
        "plex",
        "tubi",
        "samsung",
        "samsungtvplus",
        "xumo",
        "roku",
        "freevee",
        "amazon",
        "fubo",
        "sling",
        "stirr",
        "distro",
        "redbox",
        "filmrise",
        "cinevault",
        "movieland",
        "moviesphere",
        "maverick",
        "gravitas",
        "film detective",
        "comet",
        "charge!",
        "charge tv",
        "metv",
        "me tv",
        "movies!",
        "grit",
        "bounce",
        "ion",
        "court tv",
        "pbs",
        "nasa",
        "weather nation",
        "weathernation",
        "accuweather",
        "nbc news",
        "cbs news",
        "abc news",
        "sky news",
        "bbc news",
        "bloomberg",
        "reuters",
        "cheddar",
        "scripps",
        "live now",
        "livenow",
        "bein",
        "rally tv",
        "racer",
        "vevo",
        "stingray",
        "tastemade",
        "america's test kitchen",
        "test kitchen",
        "history hit",
        "curiosity",
        "magellan",
        "documentary\+",
        "docurama",
        "star trek",
        "stargate",
        "retrocrush",
        "anime all day",
        "crackle",
        "popcornflix",
        "midnight pulp",
        "shout! factory",
        "shout tv",
        "shout! tv",
        "mst3k",
        "rifftrax"
    ) -join "|"

    $preferredHostRegex = @(
        "pluto\.tv",
        "plutotv\.net",
        "plex\.tv",
        "tubi\.video",
        "tubitv\.com",
        "samsungtvplus",
        "samsung\.wurl",
        "xumo",
        "roku",
        "freevee",
        "sling",
        "stirr",
        "distro",
        "filmrise",
        "cinevault",
        "amagi\.tv",
        "cloudfront\.net",
        "akamaized\.net",
        "akamaihd\.net",
        "fast\.nbcuni\.com",
        "pbs\.org",
        "lls\.pbs\.org",
        "sinclairstoryline\.com",
        "vustreams\.com",
        "getpublica\.com",
        "ottera\.tv",
        "otteravision\.com",
        "brightcove",
        "jwp\.services",
        "livecdn\.io",
        "wurl\.tv",
        "frequency\.stream",
        "herringnetwork\.com",
        "streamguys",
        "jwplayer",
        "cdnstream",
        "mediatailor",
        "crackle",
        "popcornflix",
        "shoutfactory",
        "shout",
        "midnightpulp",
        "thegateway\.app",
        "lgchannels"
    ) -join "|"

    $blockedHostRegex = @(
        "cammonitorplus",
        "aynascope",
        "aynaott",
        "rezofoot",
        "ioapk",
        "random\.host",
        "localhost"
    ) -join "|"

    $blockedNameRegex = @(
        "\bchurch\b",
        "\bchristian\b",
        "\bcatholic\b",
        "\bbible\b",
        "\bgospel\b",
        "\bministry\b",
        "\bworship\b",
        "\bsermon\b",
        "\bshopping\b",
        "\bshop\b",
        "\bqvc\b",
        "\bhsn\b",
        "\bgem shopping\b",
        "\bjewelry\b",
        "\bgovernment\b",
        "\bcivic\b",
        "\bpublic access\b",
        "\bcommunity access\b",
        "\bmunicipal\b",
        "\bschool board\b",
        "\bcity council\b",
        "\bparliament\b",
        "\blegislative\b",
        "\bradio\b",
        "\bfm\b",
        "\bam\b",
        "\bcamera\b",
        "\bsecurity cam\b",
        "\bwebcam\b",
        "\btest\b",
        "\bbackup\b",
        "\bsurveillance\b",
        "Real America's Voice",
        "Salem News",
        "\bCBN\b"
    ) -join "|"

    # Avoid importing clearly unauthorized premium-cable restreams.
    $blockedPremiumRegex = @(
        "\bHBO\b",
        "\bCinemax\b",
        "\bShowtime\b",
        "\bStarz\b",
        "\bEncore\b",
        "\bEpix\b",
        "\bMGM\+\b",
        "\bESPN\b",
        "\bNFL Network\b",
        "\bNBA TV\b",
        "\bMLB Network\b",
        "\bNHL Network\b"
    ) -join "|"

    $mustKeepRegex = @(
        "Pluto TV",
        "Plex",
        "Tubi",
        "Samsung TV Plus",
        "Xumo",
        "Roku",
        "FilmRise",
        "Cinevault",
        "MovieSphere",
        "The Film Detective",
        "Maverick",
        "Gravitas",
        "Comet",
        "Charge!",
        "Grit",
        "Bounce",
        "Laff",
        "MeTV",
        "Movies!",
        "ION",
        "Court TV",
        "WeatherNation",
        "AccuWeather",
        "NASA",
        "PBS",
        "NBC News NOW",
        "CBS News",
        "ABC News",
        "BBC News",
        "Sky News",
        "Bloomberg",
        "Reuters",
        "Scripps News",
        "Cheddar",
        "Tastemade",
        "Vevo",
        "Stingray",
        "beIN SPORTS XTRA",
        "Fubo Sports",
        "Rally TV",
        "Racer",
        "Star Trek",
        "Stargate",
        "Doctor Who",
        "The X-Files",
        "RetroCrush",
        "Anime All Day",
        "Crunchyroll",
        "Shout! Factory",
        "Shout TV",
        "Midnight Pulp",
        "Popcornflix",
        "Crackle",
        "MST3K",
        "RiffTrax"
    ) -join "|"

    $groupRules = @(
        [pscustomobject]@{ Name="01 Minnesota Local"; Quota=60; Cats=@(); Regex="Minnesota|Minneapolis|Saint Paul|St\. Paul|Twin Cities|Duluth|Rochester|Mankato|Maple Grove|KMSP|WCCO|KARE|KSTP|KTCA|KTCI|CCX" },

        [pscustomobject]@{ Name="02 News"; Quota=160; Cats=@("news","business"); Regex="News|NBC News|CBS News|ABC News|BBC News|Sky News|Bloomberg|Reuters|Scripps|Cheddar|LiveNOW|Live Now|Al Jazeera English|France 24 English|Yahoo Finance|Newsmax|Euronews English|CBC News|DW English|TRT World|CNA" },

        [pscustomobject]@{ Name="03 Weather"; Quota=50; Cats=@("weather"); Regex="Weather|WeatherNation|AccuWeather|Storm|Radar|Forecast" },

        [pscustomobject]@{ Name="04 Movies - Action"; Quota=120; Cats=@("movies"); Regex="Action|Adventure|Thriller|Western|Grit|Charge|Combat|War|Maverick|Mission|Movie Action|Action Movies" },
        [pscustomobject]@{ Name="05 Movies - Comedy"; Quota=90; Cats=@("movies","comedy"); Regex="Comedy Movies|Funny|Laugh|Laff|Comedy|Stand Up|Rom Com|Romantic Comedy" },
        [pscustomobject]@{ Name="06 Movies - Horror"; Quota=120; Cats=@("movies"); Regex="Horror|Scream|Fear|Terror|Halloween|Monsters|Thriller|Dark Matter|Screambox|Watch It Scream|American Horrors" },
        [pscustomobject]@{ Name="07 Movies - Sci-Fi"; Quota=120; Cats=@("movies","science"); Regex="Sci[- ]?Fi|Science Fiction|Comet|DUST|Space|Alien|Fantasy|Geek|Star Trek|Stargate|Doctor Who|The X-Files|X-Files|Battlestar|Babylon 5|Farscape|Outer Limits" },
        [pscustomobject]@{ Name="08 Movies - Christmas"; Quota=60; Cats=@("movies"); Regex="Christmas|Holiday|Xmas|Hallmark" },
        [pscustomobject]@{ Name="09 Movies - Classics"; Quota=150; Cats=@("movies","classic"); Regex="Classic|Classics|Retro|Film Detective|Cinevault|Cine|Cinema|FilmRise Classic|Movies!|MeTV|MovieSphere|Gravitas|Oldies|Golden" },
        [pscustomobject]@{ Name="10 Movies - General"; Quota=420; Cats=@("movies"); Regex="Movie|Movies|Film|Cinema|Cine|Flix|Flicks|Pluto.*Movie|Plex.*Movie|Tubi.*Movie|Roku.*Movie|Xumo.*Movie|Samsung.*Movie|FilmRise|Cinevault|Maverick|Gravitas|Hallmark|Bounce|Grit" },

        [pscustomobject]@{ Name="11 TV Shows - Crime"; Quota=130; Cats=@("series","crime"); Regex="Crime|Cops|Forensic|Mystery|Unsolved|Detective|Law & Order|CSI|NCIS|Blue Bloods|Cold Case|Investigation|Court TV|True Crime|Midsomer" },
        [pscustomobject]@{ Name="12 TV Shows - Sitcoms"; Quota=110; Cats=@("series","comedy"); Regex="Sitcom|Comedy|Cheers|Frasier|Raymond|Roseanne|MASH|M\*A\*S\*H|SNL|Baywatch|Just for Laughs|Johnny Carson|Carol Burnett" },
        [pscustomobject]@{ Name="13 TV Shows - Reality"; Quota=120; Cats=@("series","entertainment","lifestyle"); Regex="Reality|Pawn|Storage|Kitchen Nightmares|Hell's Kitchen|Deal Zone|Project Runway|Duck Dynasty|Ice Road|Dog the Bounty|Survivor|Baywatch|Rescue" },
        [pscustomobject]@{ Name="14 TV Shows - Game Shows"; Quota=80; Cats=@("entertainment"); Regex="Game Show|Game Shows|Deal or No Deal|Family Feud|Price Is Right|Wipeout|Buzzr|Fear Factor" },
        [pscustomobject]@{ Name="15 TV Shows - Classic TV"; Quota=140; Cats=@("series","classic"); Regex="Classic TV|Retro TV|MeTV|Antenna|Bonanza|Gunsmoke|Andy Griffith|Perry Mason|Little House|Twilight Zone|Doctor Who|Star Trek|Stargate|MASH|M\*A\*S\*H|Dragnet|Carol Burnett|Johnny Carson|The Rifleman|Rawhide|Wanted Dead or Alive|The Lone Ranger|The Beverly Hillbillies" },

        [pscustomobject]@{ Name="16 Sports"; Quota=180; Cats=@("sports"); Regex="Sports|Fubo Sports|NBC Sports|beIN SPORTS|Rally TV|Racer|Poker|PGA|Golf|Tennis|FIFA|Soccer|Football|Baseball|Hockey|Basketball|Fight|MMA|Boxing|Wrestling|Motorsport|Racing|Unbeaten|SportsGrid" },

        [pscustomobject]@{ Name="17 Science"; Quota=110; Cats=@("science","education","documentary"); Regex="Science|NASA|Space|Curiosity|Engineering|Tech|Technology|Physics|Astronomy|Documentary\+|Magellan|DUST|Xplore|Explore" },
        [pscustomobject]@{ Name="18 History"; Quota=110; Cats=@("history","documentary","education"); Regex="History|Military|War|WWII|World War|Ancient|Archaeology|Timeline|Smithsonian|Documentary|Docurama|History Hit" },
        [pscustomobject]@{ Name="19 Nature"; Quota=120; Cats=@("documentary","outdoor","science"); Regex="Nature|Animals|Wild|Wildlife|Earth|Ocean|Sea|Shark|Zoo|Animal|Love Nature|WildEarth|National Park|Adventure" },

        [pscustomobject]@{ Name="20 Kids"; Quota=110; Cats=@("kids","animation","family"); Regex="Kids|Cartoon|Toon|Kartoon|PBS Kids|BabyFirst|Ryan|Lego|Family|Animation|Nick|DuckTV" },
        [pscustomobject]@{ Name="21 Anime"; Quota=90; Cats=@("animation","series"); Regex="Anime|RetroCrush|Crunchyroll|Yu-Gi-Oh|Yu Gi Oh|Naruto|Pokemon|Pokémon|Toonami|Dragon Ball|Gundam|Sailor Moon|Anime All Day|Animax|One Piece|Bleach|Beyblade|Digimon|Inazuma|Kamen Rider|Ultraman" },

        [pscustomobject]@{ Name="22 Music"; Quota=130; Cats=@("music"); Regex="Music|Vevo|Stingray|Qello|LiveOne|LiveXLive|Country|Rock|Classic Rock|80s|90s|Jazz|Blues|Classical|Concert|K-POP|Clubbing" },
        [pscustomobject]@{ Name="23 Cooking"; Quota=100; Cats=@("cooking","lifestyle"); Regex="Cooking|Cook|Chef|Food|Tastemade|America's Test Kitchen|Test Kitchen|Bon Appetit|BBQ|Barbecue|Baking|Kitchen" },
        [pscustomobject]@{ Name="24 Travel"; Quota=90; Cats=@("travel","lifestyle","documentary"); Regex="Travel|Adventure|Journy|Journey|Vacation|Destination|Tiny House|Places|World" },
        [pscustomobject]@{ Name="25 Cars"; Quota=90; Cats=@("auto","sports","documentary"); Regex="Car|Cars|Auto|Motor|Motors|Racer|Racing|Drive|Torque|PowerNation|Mecum|Barrett|Hot Rod|Muscle|Truck|Garage" },
        [pscustomobject]@{ Name="26 Outdoors"; Quota=90; Cats=@("outdoor","sports","documentary"); Regex="Outdoor|Outdoors|Hunt|Hunting|Fish|Fishing|Camping|Bushcraft|Waypoint|Pursuit|Adventure|Boat|Boating" },

        [pscustomobject]@{ Name="27 Relaxation - Aquarium"; Quota=40; Cats=@("relax"); Regex="Aquarium|Fish Tank|Coral|Reef" },
        [pscustomobject]@{ Name="28 Relaxation - Fireplace"; Quota=40; Cats=@("relax"); Regex="Fireplace|Fire Place|Yule Log|Campfire" },
        [pscustomobject]@{ Name="29 Relaxation - Space"; Quota=50; Cats=@("relax","science"); Regex="NASA|ISS|Earth From Space|Space|Astronaut|Orbit" },
        [pscustomobject]@{ Name="30 Relaxation - Nature"; Quota=70; Cats=@("relax","nature"); Regex="Relax|Nature|Scenic|Ocean|Rain|Forest|Beach|Waterfall|Northern Lights|Aurora|Birds|Panda|Zoo" }
    )

    function Get-ProviderScore($x) {
        $t = "$($x.Name) $($x.StreamTitle) $($x.Url)".ToLowerInvariant()
        if ($t -match "pluto|plutotv") { return 80 }
        if ($t -match "plex") { return 78 }
        if ($t -match "tubi") { return 76 }
        if ($t -match "samsung|samsungtvplus") { return 74 }
        if ($t -match "xumo") { return 72 }
        if ($t -match "roku") { return 70 }
        if ($t -match "freevee|amazon") { return 68 }
        if ($t -match "filmrise") { return 66 }
        if ($t -match "cinevault") { return 64 }
        if ($t -match "pbs|nasa") { return 62 }
        if ($t -match "amagi|wurl|ottera|cloudfront|akamai|mediatailor") { return 35 }
        return 0
    }

    function Get-StreamScore($s, $c, $feedInfo) {
        $streamHost = Get-HostName $s.url
        $text = "$($s.title) $($c.name) $($c.id) $($s.url)"

        $score = 0
        $score += Get-QualityScore $s.quality

        if ($s.url -like "https://*") { $score += 18 } else { $score += 2 }
        if ($streamHost -match $preferredHostRegex) { $score += 26 }
        if ($text -match $trustedProviderRegex) { $score += 50 }
        if ($text -match $mustKeepRegex) { $score += 70 }

        if ($s.label -match "Not 24/7") { $score -= 18 }
        if ($s.referrer) { $score -= 2 }
        if ($s.user_agent) { $score -= 1 }

        if (Test-Minnesota $s $c $feedInfo) { $score += 35 }

        return $score
    }

    $candidates = New-Object System.Collections.ArrayList

    foreach ($s in $streams) {
        if (-not $s.channel -or -not $s.url) { continue }
        $cid = [string]$s.channel
        if (-not $channelById.ContainsKey($cid)) { continue }

        $c = $channelById[$cid]
        if ($c.is_nsfw -eq $true) { continue }
        if ($c.closed) { continue }

        $feedInfo = Get-FeedInfo $s
        if (-not (Test-EnglishChannel $c $feedInfo)) { continue }

        $name = First-NonEmpty @($s.title, $c.name, $cid)
        $combinedName = "$name $($c.name) $cid"

        if ($combinedName -match $blockedNameRegex) { continue }

        # Do not auto-import likely unauthorized premium-cable restreams.
        if ($combinedName -match $blockedPremiumRegex) { continue }

        $streamHost = Get-HostName $s.url
        if (-not $streamHost) { continue }
        if ($streamHost -match '^\d{1,3}(\.\d{1,3}){3}$') { continue }
        if ($streamHost -match $blockedHostRegex) { continue }

        # Avoid obvious geoblocked entries.
        if ([string]$s.label -match "Geo-blocked|Geo blocked|blocked") { continue }

        $tvgId = if ($s.feed) { "$cid@$($s.feed)" } else { $cid }
        $display = [string]$c.name
        if ((Test-Minnesota $s $c $feedInfo) -and $name) {
            $display = $name -replace '\s*\(\d+p\).*$', ''
        }

        $feedId = if ($s.feed) { [string]$s.feed } else { "" }

        $obj = [pscustomobject]@{
            ChannelId = $cid
            FeedId = $feedId
            TvgId = $tvgId
            Name = $display
            StreamTitle = $name
            Url = [string]$s.url
            Referrer = if ($s.referrer) { [string]$s.referrer } else { "" }
            UserAgent = if ($s.user_agent) { [string]$s.user_agent } else { "" }
            Quality = if ($s.quality) { [string]$s.quality } else { "" }
            Categories = @(As-Array $c.categories)
            Country = if ($c.country) { [string]$c.country } else { "" }
            IsMinnesota = (Test-Minnesota $s $c $feedInfo)
            Score = (Get-StreamScore $s $c $feedInfo)
            ProviderScore = 0
            Logo = (Get-LogoUrl $cid $feedId)
            Group = ""
        }
        $obj.ProviderScore = Get-ProviderScore $obj
        [void]$candidates.Add($obj)
    }

    Say ("Filtered usable English stream candidates: {0}" -f $candidates.Count)

    # Collapse duplicates by tvg-id, then later by display name/url.
    $bestByTvg = @{}
    foreach ($x in $candidates) {
        if (-not $bestByTvg.ContainsKey($x.TvgId) -or (($x.Score + $x.ProviderScore) -gt ($bestByTvg[$x.TvgId].Score + $bestByTvg[$x.TvgId].ProviderScore))) {
            $bestByTvg[$x.TvgId] = $x
        }
    }
    $candidates = @($bestByTvg.Values)

    function Test-Group($x, $g) {
        if ($g.Name -eq "01 Minnesota Local") { return $x.IsMinnesota }
        $cats = @($x.Categories)
        foreach ($cat in @($g.Cats)) {
            if ($cats -contains $cat) { return $true }
        }
        $combined = "$($x.Name) $($x.StreamTitle) $($x.ChannelId)"
        if ($g.Regex -and $combined -match $g.Regex) { return $true }
        return $false
    }

    function Group-SpecificScore($x, $g) {
        $combined = "$($x.Name) $($x.StreamTitle) $($x.ChannelId) $($x.Url)"
        $score = $x.Score + $x.ProviderScore
        if (Test-Regex $combined $g.Regex) { $score += 50 }
        if ($combined -match $mustKeepRegex) { $score += 50 }

        # Movie-heavy tuning.
        if ($g.Name -match "Movies" -and $combined -match "Pluto|Plex|Tubi|Samsung|Xumo|Roku|FilmRise|Cinevault|MovieSphere|Film Detective|Maverick|Gravitas|Comet|Grit|Charge|Movies!") {
            $score += 80
        }

        # Dad-friendly classics.
        if ($combined -match "MeTV|MASH|Bonanza|Gunsmoke|Perry Mason|Andy Griffith|Little House|Twilight Zone|Carol Burnett|Johnny Carson|Classic") {
            $score += 60
        }

        return $score
    }

    $selected = New-Object System.Collections.ArrayList
    $selectedIds = New-Object System.Collections.Generic.HashSet[string]
    $selectedNames = New-Object System.Collections.Generic.HashSet[string]

    foreach ($g in $groupRules) {
        $pool = @($candidates | Where-Object { -not $selectedIds.Contains($_.TvgId) -and (Test-Group $_ $g) })

        $ranked = $pool | Sort-Object `
            @{Expression={ Group-SpecificScore $_ $g }; Descending=$true}, `
            @{Expression={$_.Name}; Descending=$false}

        $take = @($ranked | Select-Object -First $g.Quota)
        foreach ($x in $take) {
            if ($selectedIds.Contains($x.TvgId)) { continue }
            $x.Group = $g.Name
            [void]$selected.Add($x)
            [void]$selectedIds.Add($x.TvgId)
            [void]$selectedNames.Add(($x.Name.ToLowerInvariant()))
        }
    }

    # Top-up pass: if fewer than target, add strong remaining English channels that match any desired category.
    if ($selected.Count -lt $TargetCount) {
        $left = @($candidates | Where-Object { -not $selectedIds.Contains($_.TvgId) } | Sort-Object @{Expression={ $_.Score + $_.ProviderScore }; Descending=$true}, Name)
        foreach ($x in $left) {
            if ($selected.Count -ge $TargetCount) { break }

            foreach ($g in $groupRules | Where-Object { $_.Name -ne "01 Minnesota Local" }) {
                if (Test-Group $x $g) {
                    $x.Group = $g.Name
                    [void]$selected.Add($x)
                    [void]$selectedIds.Add($x.TvgId)
                    break
                }
            }
        }
    }

    $selected = @($selected | Select-Object -First $TargetCount)

    if ($selected.Count -lt 25) {
        throw "Only $($selected.Count) channels were selected. Refusing to replace the existing playlist."
    }

    $tmpPlaylist = "$PlaylistPath.tmp"
    $tmpSelection = "$SelectionPath.tmp"

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('#EXTM3U x-tvg-url="DJMN_TV_EPG.xml" url-tvg="DJMN_TV_EPG.xml"')
    $lines.Add("# $AppName - English-only curated VLC playlist")
    $lines.Add("# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $lines.Add("# Build: $BuildVersion")
    $lines.Add("# Source: IPTV-org public API")
    $lines.Add("# Note: premium subscription channels like HBO/Cinemax/Showtime/Starz are not imported unless a legitimate public feed exists.")
    $lines.Add("")

    foreach ($g in $groupRules) {
        $items = @($selected | Where-Object { $_.Group -eq $g.Name } | Sort-Object @{Expression={ $_.Score + $_.ProviderScore }; Descending=$true}, Name)
        if ($items.Count -eq 0) { continue }

        $lines.Add("# ==================== $($g.Name.ToUpperInvariant()) ====================")
        foreach ($x in $items) {
            $id = Escape-M3U $x.TvgId
            $nm = Escape-M3U $x.Name
            $logo = Escape-M3U $x.Logo
            $grp = Escape-M3U $x.Group

            $lines.Add("#EXTINF:-1 tvg-id=`"$id`" tvg-name=`"$nm`" tvg-logo=`"$logo`" group-title=`"$grp`",$nm")
            if ($x.Referrer) { $lines.Add("#EXTVLCOPT:http-referrer=$($x.Referrer)") }
            if ($x.UserAgent) { $lines.Add("#EXTVLCOPT:http-user-agent=$($x.UserAgent)") }
            $lines.Add($x.Url)
        }
        $lines.Add("")
    }

    $lines | Set-Content -LiteralPath $tmpPlaylist -Encoding UTF8

    $selected | Select-Object TvgId,ChannelId,FeedId,Name,StreamTitle,Group,Country,Quality,Logo,Url |
        ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath $tmpSelection -Encoding UTF8

    Move-Item -LiteralPath $tmpPlaylist -Destination $PlaylistPath -Force
    Move-Item -LiteralPath $tmpSelection -Destination $SelectionPath -Force
    Set-Content -LiteralPath $VersionPath -Value $BuildVersion -Encoding UTF8

    Say ""
    Say "DJMN TV WIDE playlist updated successfully."
    Say ("Channels selected: {0}" -f $selected.Count)
    Say ""
    foreach ($grp in ($selected | Group-Object Group | Sort-Object Name)) {
        Say ("  {0,-34} {1,3}" -f $grp.Name, $grp.Count)
    }
}

if ($needsUpdate) {
    try {
        Build-DJMN-TV
    }
    catch {
        Say ""
        Say "Update failed: $($_.Exception.Message)"

        if (Test-Path -LiteralPath $PlaylistPath) {
            Say "Keeping the last working playlist and launching anyway."
        }
        else {
            Say "No working playlist exists yet. DJMN TV cannot launch until the first playlist build succeeds."
            Say "Log file: $LogPath"
            Write-Host ""
            Write-Host "Press ENTER to close."
            Read-Host | Out-Null
            exit 30
        }
    }
}

if (-not (Test-Path -LiteralPath $PlaylistPath)) {
    Say "Playlist is missing. Cannot launch."
    exit 31
}

Say ""
Say "Opening DJMN TV in VLC..."
Start-Process -FilePath $vlcPath -ArgumentList "`"$PlaylistPath`""
exit 0
