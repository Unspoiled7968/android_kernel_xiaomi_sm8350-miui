param(
    [Parameter(Mandatory = $true)]
    [string]$ProfilePath,

    [string]$Serial = "68a839d4",

    [string]$RemoteProfilePath = "/data/local/tmp/active_battery_profile.conf",

    [string]$RemoteApplyScript = "/data/local/tmp/apply_battery_profile.sh"
)

$localApplyScript = "C:\Users\ee\AppData\Roaming\reasonix\global-workspace\11u\star_kernel_lab_20260728\battery_profiles\scripts\apply_battery_profile.sh"

if (-not (Test-Path $ProfilePath)) {
    throw "Profile not found: $ProfilePath"
}

if (-not (Test-Path $localApplyScript)) {
    throw "Apply script not found: $localApplyScript"
}

adb -s $Serial push $localApplyScript $RemoteApplyScript
adb -s $Serial push $ProfilePath $RemoteProfilePath
adb -s $Serial shell su -c "chmod 0755 $RemoteApplyScript && sh $RemoteApplyScript $RemoteProfilePath"
