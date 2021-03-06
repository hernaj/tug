#!/usr/bin/env pwsh

function Install-TugServer {
<#
.SYNOPSIS
Installs the Tug DSC Pull Server.

.PARAMETER InstallPath
Overrides the default target installation path (%PROGRAMDATA%\TugDSC\Server).

.PARAMETER InstallAsService
Specifies the behavior for installing the TugDSC Server as  Windows Server.  "Auto", the default
installs on On Windows platforms and skips elsewhere.  "Yes" forces an attempt, which will fail
on non-Windows paltforms.  "No" skips installing on all platforms.

.PARAMETER Overwrite
If the InstallPath exists and is not empty and then the installation will fail unless
this switch is specified.  When specified, it will overwrite any files in the target
location except for configuration files.
#>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$InstallPath="$($env:ProgramData)\TugDSC\Server",
        [Parameter()]
        [ValidateSet(
            'Auto',
            'Yes',
            'No'
        )]
        [string]$InstallAsService="Auto",
        [Parameter()]
        [switch]$Overwrite
    )

    $onWindows = ($PSVersionTable.PSEdition -ine "Core") -or $IsWindows
    Write-Verbose "Detected running [$(if ($onWindows) { "ON WINDOWS" } else { "NOT on WINDOWS" })]"

    $winServiceSupported = (Microsoft.PowerShell.Core\Get-Command `
            Microsoft.PowerShell.Management\New-Service -ErrorAction SilentlyContinue)
    $winServiceInstall = ($InstallAsService -ieq 'YES') `
            -or ($InstallAsService -ieq 'AUTO' -and $winServiceSupported)
    
    $fullPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PWD, $InstallPath))
    Write-Verbose "Resolved installation path as [$fullPath]"

    if (Test-Path -PathType Container $fullPath) {
        if (-not $Overwrite -and (Get-ChildItem $fullPath).Length) {
            Write-Error "Target installation path is not empty; specify Overwrite switch to force install"
            return
        }
        Write-Verbose "Target installation path already exists"
    }
    else {
        Write-Verbose "Creating target installation path"
        mkdir $fullPath -Force | Out-Null
    }

    $tugModule = $MyInvocation.MyCommand.Module
    Write-Verbose "My Module is [$tugModule] is located at [$($tugModule.Path)]"

    $webappSource = [System.IO.Path]::Combine($tugModule.ModuleBase, "webapp")
    $assetsSource = [System.IO.Path]::Combine($tugModule.ModuleBase, "assets")

    if ($onWindows) {
        $webappSource = Join-Path $webappSource "win-x64-net461"
    }
    else {
        $webappSource = Join-Path $webappSource "linux-x64-netcoreapp2.0"        
    }

    if (-not (Test-Path -PathType Container $webappSource)) {
        Write-Error "Cannot resolve installation WebApp files"
        return
    }

    if (-not (Test-Path -PathType Container $assetsSource)) {
        Write-Error "Cannot resolve installation Assets files"
        return
    }

    Write-Verbose "Copying binary files over"
    Copy-Item $binSource -Destination "$fullPath" -Recurse -Force

<#
    $initialFiles = @{}
    Write-Verbose "Copying over initial config/samples..."
    foreach ($f in (Get-ChildItem -Path $smpSource)) {
        Write-Verbose "Installing [$f]:"

        $hashSource = Get-FileHash $f.FullName -Algorithm MD5
        $fileFullPath = [System.IO.Path]::Combine($fullPath, $f.Name)

        if (Test-Path $fileFullPath) {
            Write-Verbose "  * already found at [$fileFullPath]"
            $hashTarget = Get-FileHash $fileFullPath -Algorithm MD5
            
            if ($hashTarget.Hash -ne $hashSource.Hash) {
                $samplePath = [System.IO.Path]::Combine($fullPath, "sample")
                $fileFullPath = [System.IO.Path]::Combine($samplePath, $f.Name)

                ## Make sure there is a place to stash our samples
                if (-not (Test-Path -PathType Container $samplePath)) {
                    mkdir $samplePath -Force | Out-Null
                }

                $copyIndex = 0
                while (Test-Path $fileFullPath) {
                    $hashTarget = Get-FileHash $fileFullPath -Algorithm MD5

                    ## We only want to save samples if they're newer
                    if ($hashTarget.Hash -eq $hashSource.Hash) {
                        Write-Verbose "  * latest sample already found at [$fileFullPath]"
                        $fileFullPath = $null
                        break
                    }

                    ## Advance to the next candidate sample name
                    $fileFullPath = $fileFullPath -replace '_\d+$',''
                    $fileFullPath += "_$((++$copyIndex))"
                }

                if ($fileFullPath) {
                    Write-Verbose "  * saving as sample file to [$fileFullPath]"
                    Copy-Item $f.FullName -Destination $fileFullPath
                }
            }
        }
        else {
            Write-Verbose "  * creating initial at [$fileFullPath]"
            Copy-Item $f.FullName $fileFullPath
            $initialFiles[$f.Name] = $true
        }
    }

    $authzPath = [System.IO.Path]::Combine($fullPath, "var\DscService\Authz")
    $regKeyPath = [System.IO.Path]::Combine($fullPath, "var\DscService\Authz\RegistrationKeys.txt")
    if (-not (Test-Path -PathType Container $authzPath)) {
        Write-Warning "*******************************************************************"
        Write-Warning "** Initial installation, creating INITIAL REGISTRATION KEY FILE"
        Write-Warning "**   * Saving to [$regKeyPath]"
        Write-Warning "**   * You should inspect/update this file with your own Reg Keys"
        Write-Warning "**     or distribute the newly minted Reg Key to your Nodes"
        Write-Warning "*******************************************************************"

        mkdir $authzPath -Force | Out-Null
        Set-Content -Path $regKeyPath -Value @"
## This file is only relevant if "Registration Key Authorization"
## (RegKey Authz) is enabled.
##
## In this file Tug will use any non-blank lines after stripping out
## comments starting with the '#' character and trimming whitespace
## from both ends.

## You should either update the Registration Keys listed here
## with your own or distribute the keys here to your nodes.
##
## This file is auto-generated with a newly-minted Reg Key:
##     at [$([datetime]::Now)]
##     by [$($env:USERNAME)]
##     on [$($env:COMPUTERNAME)]
##     to [$($regKeyPath)]

$([guid]::NewGuid())

"@
    }
#>
}

Export-ModuleMember -Function Install-*
