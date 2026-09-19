# Charger System.Windows.Forms
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue

# ============================================================
# DPI Awareness : évite le flou des popups à 125% (et autres)
# Doit être appelé AVANT la création de tout contrôle Windows Forms
# ============================================================
Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;
public class CGlobalDpiHelper {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
"@ -ErrorAction SilentlyContinue

if ("CGlobalDpiHelper" -as [type]) {
    [CGlobalDpiHelper]::SetProcessDPIAware() | Out-Null
}

# ============================================================
# Forçage au premier plan : Windows empêche par défaut un processus
# sans focus de voler l'avant-plan (anti-vol-de-focus). TopMost seul
# ne suffit pas toujours ; SetForegroundWindow force réellement l'activation.
# ============================================================
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class CGlobalForegroundHelper {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@ -ErrorAction SilentlyContinue

function New-CGlobalTopMostOwner {
    $OwnerForm = New-Object System.Windows.Forms.Form
    $OwnerForm.StartPosition = 'CenterScreen'
    $OwnerForm.Size = New-Object System.Drawing.Size(1, 1)
    $OwnerForm.FormBorderStyle = 'None'
    $OwnerForm.ShowInTaskbar = $false
    $OwnerForm.Opacity = 0
    $OwnerForm.TopMost = $true

    [void]$OwnerForm.Show()
    $OwnerForm.Activate()

    if ("CGlobalForegroundHelper" -as [type]) {
        [CGlobalForegroundHelper]::SetForegroundWindow($OwnerForm.Handle) | Out-Null
    }

    return $OwnerForm
}

$script:CGLOBAL_LogFolder = "C:\_CGLOBAL\Logs"
$script:CGLOBAL_LogFile   = $null

function Get-CGlobalLogFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath
    )

    $ScriptName = Split-Path -Leaf $ScriptPath
    $BaseName   = [System.IO.Path]::GetFileNameWithoutExtension($ScriptName)

    return Join-Path $script:CGLOBAL_LogFolder "Log$BaseName.txt"
}

function Initialize-CGlobalLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )

    $script:CGLOBAL_LogFile = $LogFile

    $LogDirectory = Split-Path -Path $LogFile -Parent

    if (-not (Test-Path -Path $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }

    if (-not (Test-Path -Path $LogFile)) {
        New-Item -Path $LogFile -ItemType File -Force | Out-Null
    }

    return $script:CGLOBAL_LogFile
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO', 'OK', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    if (-not $script:CGLOBAL_LogFile) {
        $script:CGLOBAL_LogFile = Join-Path $script:CGLOBAL_LogFolder "CGLOBAL_Common.log"
        if (-not (Test-Path (Split-Path $script:CGLOBAL_LogFile -Parent))) {
            New-Item -Path (Split-Path $script:CGLOBAL_LogFile -Parent) -ItemType Directory -Force | Out-Null
        }
    }

    $Line = "[{0}] [{1,-5}] {2}" -f `
        (Get-Date -Format "HH:mm:ss"), `
        $Level, `
        $Message

    # Réessai en cas de verrou transitoire sur le fichier (ex. lecture concurrente,
    # antivirus). Une erreur d'écriture de log ne doit jamais interrompre le script appelant.
    $MaxAttempts = 10
    for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {
        try {
            Add-Content -Path $script:CGLOBAL_LogFile -Value $Line -Encoding UTF8 -ErrorAction Stop
            break
        }
        catch {
            if ($Attempt -ge $MaxAttempts) {
                Write-Host "[ÉCHEC ECRITURE LOG] $Line" -ForegroundColor Red
            }
            else {
                Start-Sleep -Milliseconds 150
            }
        }
    }

    $Color = @{
        INFO  = 'Cyan'
        OK    = 'Green'
        WARN  = 'Yellow'
        ERROR = 'Red'
    }

    Write-Host $Line -ForegroundColor $Color[$Level]
}


# ============================================================
# Modes d'execution centralises
# ============================================================
$script:CGLOBAL_SessionConfig = $null

function Get-CGlobalExecutionMode {
    $Mode = [string]$env:CGLOBAL_EXECUTION_MODE
    if ($Mode -notin @('Interactif', 'Prévalidé', 'Silencieux')) {
        return 'Interactif'
    }
    return $Mode
}

function Get-CGlobalSessionConfig {
    if ($null -ne $script:CGLOBAL_SessionConfig) {
        return $script:CGLOBAL_SessionConfig
    }
    $Path = [string]$env:CGLOBAL_SESSION_FILE
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        $script:CGLOBAL_SessionConfig = [PSCustomObject]@{}
        return $script:CGLOBAL_SessionConfig
    }
    try {
        $script:CGLOBAL_SessionConfig = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        $script:CGLOBAL_SessionConfig = [PSCustomObject]@{}
        Write-Log "Configuration de session illisible : $($_.Exception.Message)" 'WARN'
    }
    return $script:CGLOBAL_SessionConfig
}

function Get-CGlobalDecision {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [AllowNull()][object]$Default = $null
    )
    $Config = Get-CGlobalSessionConfig
    $Property = $Config.PSObject.Properties[$Key]
    if ($null -eq $Property) { return $Default }
    return $Property.Value
}

function Show-CGlobalPasswordBox {
    param([string]$Title = 'Définition du mot de passe')
    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = $Title
    $Form.StartPosition = 'CenterScreen'
    $Form.FormBorderStyle = 'FixedDialog'
    $Form.Width = 460
    $Form.Height = 255
    $Form.TopMost = $true
    $Form.MaximizeBox = $false
    $Form.MinimizeBox = $false
    $Form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $Label1 = New-Object System.Windows.Forms.Label
    $Label1.Text = 'Entrez le mot de passe :'
    $Label1.SetBounds(20, 20, 400, 20)
    $Text1 = New-Object System.Windows.Forms.TextBox
    $Text1.SetBounds(20, 45, 400, 24)
    $Text1.UseSystemPasswordChar = $true
    $Label2 = New-Object System.Windows.Forms.Label
    $Label2.Text = 'Confirmez le mot de passe :'
    $Label2.SetBounds(20, 85, 400, 20)
    $Text2 = New-Object System.Windows.Forms.TextBox
    $Text2.SetBounds(20, 110, 400, 24)
    $Text2.UseSystemPasswordChar = $true
    $Ok = New-Object System.Windows.Forms.Button
    $Ok.Text = 'Valider'; $Ok.SetBounds(125, 155, 90, 30)
    $Ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $Cancel = New-Object System.Windows.Forms.Button
    $Cancel.Text = 'Annuler'; $Cancel.SetBounds(235, 155, 90, 30)
    $Cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $Form.Controls.AddRange(@($Label1,$Text1,$Label2,$Text2,$Ok,$Cancel))
    $Form.AcceptButton = $Ok; $Form.CancelButton = $Cancel
    do {
        $Result = $Form.ShowDialog()
        if ($Result -ne [System.Windows.Forms.DialogResult]::OK) { $Form.Dispose(); return $null }
        if (-not [string]::IsNullOrWhiteSpace($Text1.Text) -and $Text1.Text -eq $Text2.Text) { break }
        [void][System.Windows.Forms.MessageBox]::Show('Les mots de passe sont vides ou différents.','Mot de passe invalide','OK','Exclamation')
        $Text1.Clear(); $Text2.Clear(); $Text1.Focus()
    } while ($true)
    $Secure = ConvertTo-SecureString -String $Text1.Text -AsPlainText -Force
    $Blob = ConvertFrom-SecureString -SecureString $Secure
    $Text1.Clear(); $Text2.Clear(); $Form.Dispose()
    return $Blob
}


function Show-CGlobalPopup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [string]$Title = "Post-Installation PC",

        [ValidateSet('OK', 'OKCancel', 'YesNo', 'YesNoCancel', 'AbortRetryIgnore', 'RetryCancel')]
        [string]$Buttons = 'OK',

        [ValidateSet('None', 'Question', 'Exclamation', 'Stop', 'Information')]
        [string]$Icon = 'Information'
    )

    $OwnerForm = New-CGlobalTopMostOwner

    $dialogResult = [System.Windows.Forms.MessageBox]::Show(
        $OwnerForm,
        $Message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::$Buttons,
        [System.Windows.Forms.MessageBoxIcon]::$Icon
    )

    $OwnerForm.Close()
    $OwnerForm.Dispose()

    return $dialogResult
}

function Show-CGlobalInputBox {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [string]$Title = "Post-Installation PC",

        [string]$DefaultText = ""
    )

    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = $Title
    $Form.StartPosition = 'CenterScreen'
    $Form.FormBorderStyle = 'FixedDialog'
    $Form.MinimizeBox = $false
    $Form.MaximizeBox = $false
    $Form.Width = 420
    $Form.Height = 180
    $Form.Topmost = $true

    $Label = New-Object System.Windows.Forms.Label
    $Label.Text = $Message
    $Label.SetBounds(10, 10, 390, 60)
    $Form.Controls.Add($Label)

    $TextBox = New-Object System.Windows.Forms.TextBox
    $TextBox.Text = $DefaultText
    $TextBox.SetBounds(10, 75, 385, 24)
    $Form.Controls.Add($TextBox)

    $OkButton = New-Object System.Windows.Forms.Button
    $OkButton.Text = 'OK'
    $OkButton.SetBounds(220, 105, 80, 28)
    $OkButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $Form.Controls.Add($OkButton)
    $Form.AcceptButton = $OkButton

    $CancelButton = New-Object System.Windows.Forms.Button
    $CancelButton.Text = 'Annuler'
    $CancelButton.SetBounds(310, 105, 85, 28)
    $CancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $Form.Controls.Add($CancelButton)
    $Form.CancelButton = $CancelButton

    $Form.Add_Shown({
        $Form.Activate()
        if ("CGlobalForegroundHelper" -as [type]) {
            [CGlobalForegroundHelper]::SetForegroundWindow($Form.Handle) | Out-Null
        }
        $TextBox.Focus()
        $TextBox.SelectAll()
    })

    $Result = $Form.ShowDialog()
    $Form.Dispose()

    if ($Result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $TextBox.Text
    }

    # $null distingue explicitement l'annulation d'une saisie vide validée par OK
    return $null
}

Export-ModuleMember -Function Get-CGlobalLogFile, Initialize-CGlobalLog, Write-Log, Show-CGlobalPopup, Show-CGlobalInputBox, Get-CGlobalExecutionMode, Get-CGlobalSessionConfig, Get-CGlobalDecision, Show-CGlobalPasswordBox
