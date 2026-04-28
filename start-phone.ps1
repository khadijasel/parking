param(
    [string]$DeviceId = "",
    [string]$IpAddress = "",
    [int]$Port = 8000,
    [string]$ApiPath = "/api",
    [string]$GoogleServerClientId = "",
    [switch]$SkipPubGet,
    [switch]$SkipFirewallRule,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "[start-phone] $Message" -ForegroundColor Cyan
}

function Assert-Tool {
    param([string]$CommandName)

    if (-not (Get-Command $CommandName -ErrorAction SilentlyContinue)) {
        throw "Required command not found in PATH: $CommandName"
    }
}

function Normalize-ApiPath {
    param([string]$RawApiPath)

    $clean = $RawApiPath
    if ($null -eq $clean) {
        $clean = ""
    }

    $clean = $clean.Trim()
    if (-not $clean) {
        return "/api"
    }

    if (-not $clean.StartsWith("/")) {
        $clean = "/$clean"
    }

    return $clean.TrimEnd("/")
}

function Resolve-LocalIp {
    param([string]$OverrideIp)

    if ($OverrideIp -and $OverrideIp.Trim()) {
        return $OverrideIp.Trim()
    }

    $candidates = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {
        $_.IPAddress -notmatch '^127\.' -and
        $_.IPAddress -notmatch '^169\.254\.' -and
        $_.PrefixOrigin -ne 'WellKnown'
    }

    if (-not $candidates) {
        throw "No suitable local IPv4 address found. Pass -IpAddress manually."
    }

    $preferred = $candidates | Where-Object {
        $_.InterfaceAlias -match 'Wi-Fi|WLAN|Ethernet'
    } | Select-Object -First 1

    if (-not $preferred) {
        $preferred = $candidates | Select-Object -First 1
    }

    return $preferred.IPAddress
}

function Resolve-AndroidDeviceId {
    param([string]$RequestedDeviceId)

    $rawJson = & flutter devices --machine | Out-String
    $devices = $rawJson | ConvertFrom-Json

    if ($RequestedDeviceId -and $RequestedDeviceId.Trim()) {
        $exists = $devices | Where-Object { $_.id -eq $RequestedDeviceId } | Select-Object -First 1
        if (-not $exists) {
            throw "Device ID '$RequestedDeviceId' was not found. Run 'flutter devices' to list valid IDs."
        }
        return $RequestedDeviceId
    }

    $physicalAndroid = $devices | Where-Object {
        $_.targetPlatform -like 'android*' -and -not $_.emulator
    } | Select-Object -First 1

    if ($physicalAndroid) {
        return $physicalAndroid.id
    }

    $anyAndroid = $devices | Where-Object {
        $_.targetPlatform -like 'android*'
    } | Select-Object -First 1

    if ($anyAndroid) {
        return $anyAndroid.id
    }

    throw "No Android device found. Connect a phone and run 'flutter devices'."
}

function Get-DotEnvValue {
    param(
        [string]$FilePath,
        [string]$Key
    )

    if (-not (Test-Path $FilePath)) {
        return ""
    }

    $escapedKey = [regex]::Escape($Key)

    foreach ($line in Get-Content $FilePath) {
        if ($line -match "^\s*$escapedKey\s*=\s*(.*)$") {
            $value = $matches[1].Trim()

            if (
                ($value.StartsWith('"') -and $value.EndsWith('"')) -or
                ($value.StartsWith("'") -and $value.EndsWith("'"))
            ) {
                if ($value.Length -ge 2) {
                    $value = $value.Substring(1, $value.Length - 2)
                }
            }

            return $value.Trim()
        }
    }

    return ""
}

function Ensure-FirewallRule {
    param(
        [int]$ListenPort,
        [switch]$SkipRule,
        [switch]$Dry
    )

    if ($SkipRule) {
        Write-Step "Skipping firewall rule setup."
        return
    }

    $ruleName = "Laravel-$ListenPort"
    $commandPreview = "netsh advfirewall firewall add rule name=`"$ruleName`" dir=in action=allow protocol=TCP localport=$ListenPort"

    if ($Dry) {
        Write-Step "DryRun: $commandPreview"
        return
    }

    try {
        & netsh advfirewall firewall add rule name="$ruleName" dir=in action=allow protocol=TCP localport=$ListenPort | Out-Null
        Write-Step "Firewall rule ensured: $ruleName"
    } catch {
        Write-Warning "Could not add firewall rule automatically (likely requires admin rights)."
        Write-Warning "Run manually as admin if needed: $commandPreview"
    }
}

function Start-BackendServer {
    param(
        [string]$BackendPath,
        [int]$ListenPort,
        [switch]$Dry
    )

    $backendCommand = "php artisan serve --host=0.0.0.0 --port=$ListenPort"

    if ($Dry) {
        Write-Step "DryRun: start backend in separate window -> $backendCommand"
        return
    }

    Start-Process -FilePath "powershell" -WorkingDirectory $BackendPath -ArgumentList "-NoExit", "-Command", $backendCommand | Out-Null
    Write-Step "Backend launched in separate PowerShell window on 0.0.0.0:$ListenPort"
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$backendPath = Join-Path $scriptRoot "parking_back"
$frontPath = Join-Path $scriptRoot "parking_front"

if (-not (Test-Path (Join-Path $backendPath "artisan"))) {
    throw "Laravel backend not found at: $backendPath"
}

if (-not (Test-Path (Join-Path $frontPath "pubspec.yaml"))) {
    throw "Flutter frontend not found at: $frontPath"
}

Assert-Tool -CommandName "php"
Assert-Tool -CommandName "flutter"

$normalizedApiPath = Normalize-ApiPath -RawApiPath $ApiPath
$localIp = Resolve-LocalIp -OverrideIp $IpAddress
$apiBaseUrl = "http://$localIp`:$Port$normalizedApiPath"
$resolvedDeviceId = Resolve-AndroidDeviceId -RequestedDeviceId $DeviceId

Write-Step "Using local IP: $localIp"
Write-Step "Using Android device: $resolvedDeviceId"
Write-Step "Using API base URL: $apiBaseUrl"

Ensure-FirewallRule -ListenPort $Port -SkipRule:$SkipFirewallRule -Dry:$DryRun
Start-BackendServer -BackendPath $backendPath -ListenPort $Port -Dry:$DryRun

if ($DryRun) {
    Write-Step "DryRun complete."
    exit 0
}

Push-Location $frontPath
try {
    if (-not $SkipPubGet) {
        Write-Step "Running flutter pub get..."
        & flutter pub get
        if ($LASTEXITCODE -ne 0) {
            throw "flutter pub get failed with code $LASTEXITCODE"
        }
    } else {
        Write-Step "Skipping flutter pub get."
    }

    Write-Step "Starting Flutter app on phone..."
    $resolvedGoogleServerClientId = $GoogleServerClientId.Trim()

    if (-not $resolvedGoogleServerClientId -and $env:GOOGLE_SERVER_CLIENT_ID) {
        $resolvedGoogleServerClientId = $env:GOOGLE_SERVER_CLIENT_ID.Trim()
    }

    if (-not $resolvedGoogleServerClientId) {
        $resolvedGoogleServerClientId = Get-DotEnvValue -FilePath (Join-Path $backendPath ".env") -Key "GOOGLE_CLIENT_ID"
        if ($resolvedGoogleServerClientId) {
            Write-Step "Using GOOGLE_CLIENT_ID from backend .env as GOOGLE_SERVER_CLIENT_ID."
        }
    }

    $flutterArgs = @(
        "run",
        "-d", $resolvedDeviceId,
        "--dart-define", "API_BASE_URL=$apiBaseUrl"
    )

    if ($resolvedGoogleServerClientId) {
        $flutterArgs += @("--dart-define", "GOOGLE_SERVER_CLIENT_ID=$resolvedGoogleServerClientId")
        Write-Step "Using GOOGLE_SERVER_CLIENT_ID for Google Sign-In."
    } else {
        Write-Step "GOOGLE_SERVER_CLIENT_ID not provided; using Google access token fallback."
    }

    & flutter @flutterArgs
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}