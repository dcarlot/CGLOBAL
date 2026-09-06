# Charger System.Windows.Forms
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue

# ============================================================
# DPI Awareness : evite le flou des popups a 125% (et autres)
# Doit etre appele AVANT la creation de tout controle Windows Forms
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
# Forcage au premier plan : Windows empeche par defaut un processus
# sans focus de voler l'avant-plan (anti-vol-de-focus). TopMost seul
# ne suffit pas toujours ; SetForegroundWindow force reellement l'activation.
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

    Add-Content -Path $script:CGLOBAL_LogFile -Value $Line -Encoding UTF8

    $Color = @{
        INFO  = 'Cyan'
        OK    = 'Green'
        WARN  = 'Yellow'
        ERROR = 'Red'
    }

    Write-Host $Line -ForegroundColor $Color[$Level]
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

    # $null distingue explicitement l'annulation d'une saisie vide validee par OK
    return $null
}

Export-ModuleMember -Function Get-CGlobalLogFile, Initialize-CGlobalLog, Write-Log, Show-CGlobalPopup, Show-CGlobalInputBox
