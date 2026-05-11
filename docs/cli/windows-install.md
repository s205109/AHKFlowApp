# Install AHKFlow CLI on Windows

## Install steps

1. Download `ahkflow-win-x64.zip` from the latest GitHub Release.
2. Create the install folder:

   ```powershell
   New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\Tools\ahkflow"
   ```

3. Extract the zip contents into `$env:USERPROFILE\Tools\ahkflow`.
4. Add the install folder to your user PATH:

   ```powershell
   $installPath = "$env:USERPROFILE\Tools\ahkflow"
   $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
   if ([string]::IsNullOrWhiteSpace($userPath)) {
       [Environment]::SetEnvironmentVariable("Path", $installPath, "User")
   } elseif (($userPath -split ";") -notcontains $installPath) {
       [Environment]::SetEnvironmentVariable("Path", "$userPath;$installPath", "User")
   }
   ```

5. Open a new terminal.
6. Confirm the CLI is available:

   ```powershell
   ahkflow --help
   ```

## Sign in and use

Device-code sign-in shows a URL and code in the terminal. Follow the URL, enter the code, and complete sign-in in the browser.

```powershell
ahkflow login
ahkflow hotstring list
ahkflow logout
```

## Uninstall

Remove the install folder from your user PATH:

```powershell
$installPath = "$env:USERPROFILE\Tools\ahkflow"
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$newPath = (($userPath -split ";") | Where-Object { $_ -and $_ -ne $installPath }) -join ";"
[Environment]::SetEnvironmentVariable("Path", $newPath, "User")
```

Delete the install folder:

```powershell
Remove-Item -LiteralPath "$env:USERPROFILE\Tools\ahkflow" -Recurse -Force
```

Remove the MSAL token cache:

```powershell
Remove-Item -LiteralPath "$env:LOCALAPPDATA\AHKFlowApp\msal-cache.bin3" -Force -ErrorAction SilentlyContinue
```

Optionally remove the whole local app data folder:

```powershell
Remove-Item -LiteralPath "$env:LOCALAPPDATA\AHKFlowApp" -Recurse -Force -ErrorAction SilentlyContinue
```

## Advanced overrides

The release zip includes production config. Normal users do not need environment variables.

For testing or advanced scenarios, set overrides before running the CLI:

```powershell
$env:AHKFLOW_ApiBaseUrl = "https://example.invalid"
$env:AHKFLOW_ClientId = "11111111-1111-1111-1111-111111111111"
$env:AHKFLOW_TenantId = "22222222-2222-2222-2222-222222222222"
```
