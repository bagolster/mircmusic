Add-Type -AssemblyName System.Runtime.WindowsRuntime

$outFile  = "C:\IRC\ytmusic.txt"
$stopFile = "C:\IRC\ytmusic.stop"

# Cegah watcher dobel
$created = $false
$mutex = New-Object System.Threading.Mutex(
    $true,
    "Local\mIRC_YTMusic_Watcher",
    [ref]$created
)

if (-not $created) {
    exit
}

if (Test-Path $stopFile) {
    Remove-Item $stopFile -Force -ErrorAction SilentlyContinue
}

$managerType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType=WindowsRuntime]

$propsType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties, Windows.Media.Control, ContentType=WindowsRuntime]

$asTaskGeneric = (
    [System.WindowsRuntimeSystemExtensions].GetMethods() |
    Where-Object {
        $_.Name -eq "AsTask" -and
        $_.IsGenericMethod -and
        $_.GetParameters().Count -eq 1
    }
)[0]

function Await($Operation, $ResultType) {
    $method = $asTaskGeneric.MakeGenericMethod($ResultType)
    $task = $method.Invoke($null, @($Operation))
    $task.Wait()
    return $task.Result
}

try {

    $manager = Await ($managerType::RequestAsync()) $managerType

    $lastSong = ""

    while ($true) {

        if (Test-Path $stopFile) {
            Remove-Item $stopFile -Force -ErrorAction SilentlyContinue
            break
        }

        try {

            # Ambil media yang sedang aktif
            $session = $manager.GetCurrentSession()

            # Kalau current bukan Chrome/Edge, cari media session browser
            if (
                (-not $session) -or
                ($session.SourceAppUserModelId -notmatch "(?i)chrome|msedge")
            ) {

                $session = $manager.GetSessions() |
                    Where-Object {
                        $_.SourceAppUserModelId -match "(?i)chrome|msedge"
                    } |
                    Select-Object -First 1
            }

            if ($session) {

                $playback = $session.GetPlaybackInfo()

                # Hanya proses kalau sedang PLAY
                if ($playback.PlaybackStatus.ToString() -eq "Playing") {

                    $props = Await `
                        ($session.TryGetMediaPropertiesAsync()) `
                        $propsType

                    $title  = $props.Title
                    $artist = $props.Artist

                    if ($title) {

                        if ($artist) {
                            $song = "$artist - $title"
                        }
                        else {
                            $song = "$title"
                        }

                        # Tulis hanya kalau lagu berubah
                        if ($song -ne $lastSong) {

                            $utf8 = New-Object System.Text.UTF8Encoding($false)

                            [System.IO.File]::WriteAllText(
                                $outFile,
                                $song,
                                $utf8
                            )

                            $lastSong = $song
                        }
                    }
                }
            }

        }
        catch {
            # Abaikan error sementara
        }

        Start-Sleep -Milliseconds 750
    }

}
finally {

    try {
        $mutex.ReleaseMutex()
    } catch {}

    $mutex.Dispose()
}