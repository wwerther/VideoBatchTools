# Searches in a given Path for MKV-Files that do not contain MPG4 Video-Streams and relocates them to another directory for further processing

# Call-Example D:\move.ps1 'M:\videos\' 'D:\Video'
Param (
	[string]$Path,      # The input-path/file
	[string]$OPath      # The destinationpath
) 

# A small function, that checks wether or not we work on a 64bit version of Windows
function is64bit() {
    return ([IntPtr]::Size -eq 8)
}

# Returns the x86 ProgramFiles directory independent on wether we have 64bit system or 32bit system
function get-programfilesdir() {
    if (is64bit -eq $true) {
        (Get-Item "Env:ProgramFiles(x86)").Value
    } else {
        (Get-Item "Env:ProgramFiles").Value
    }
}

$myPATH = @{}
$myPATH['Out']  = $OPath
$PDIR86 = get-programfilesdir

# Configure exe paths here.
$ExePath = @{}
$ExePath['mkvinfo']   =  $PDIR86 +  '\MKVtoolnix\mkvmerge.exe'

$Config = @{}
$Config['mkvinfo'] = '-i "$FilenameIn"';

# ReadProcess starts a new process with given arguments and waits until the process terminates. It copies the complete
# content that the process generated as output (STDOUT) to a variable that is returned at the end of the script
function ReadProcess ($Filename, $Arguments) {
	$ProcessInfo1 = New-Object System.Diagnostics.ProcessStartInfo
	$ProcessInfo1.FileName = $Filename
	$ProcessInfo1.Arguments = $Arguments
	$ProcessInfo1.UseShellExecute = $False
	$ProcessInfo1.RedirectStandardOutput = $True
	$ProcessInfo1.RedirectStandardError = $False
	$Process1 = [System.Diagnostics.Process]::Start($ProcessInfo1)
    $Result=$Process1.StandardOutput.ReadToEnd()
    $Process1.WaitForExit();
    $Result
}

function CheckAndMove($FilenameIn,$DestPath) {
    Write-Host "Scanning" $FilenameIn
    
    # Start a process that gets information about the given MKV-file
    $Result=ReadProcess $ExePath['mkvinfo'] $Config['mkvinfo'].Replace('$FilenameIn', $FilenameIn) 
    
    # Parse the output of the MKV-Info
    <#-- Sample Output --
    Datei 'Bad Company.mkv': Container: Matroska
    Track ID 1: video (V_MPEG2)
    Track ID 2: audio (A_AC3)
    Track ID 3: audio (A_AC3)
    Track ID 11: subtitles (S_VOBSUB)
    Kapitel: 16 Einträge
    #>
    foreach ($line in $Result.split("`n")) {        
        $line=$line.trim()
        $line=$line -replace "[\r\n]",''
        switch -regex ($line) {
            '^Track.*video\s\((.+?)\)' {
                $codec=$matches[1]
                # Check for the different codecs
                switch -regex ($codec) {
                    # In case of MPG2 codec
                    'V_MPEG2' {
                        Write-Host "- NOK. Will move to $DestPath"
                        # We want to move the file to our destination path
                        Move-Item $FileNameIn $DestPath
                        return
                    }
                    'V_MPEG4' {
                        Write-Host "-  OK. Skipping Mpg4"
                    }
                    default {
                        Write-Host "- Unknown Codec: " $codec
                    }
                }
            }
            default {
            }
        }
    }
}


# Check for existence of all Exe-Files
foreach ($Exe in $ExePath.Values) {
	if ((Test-Path -PathType 'Leaf' $Exe) -eq $False) {
		Write-Host "Error: Executable `"$Exe`" not found."
		Write-Host 'Exiting. Edit source file to set up exe paths for x264, bepipe, neroaacenc and mp4box!'
		exit
	}
}

# check if a parameter is given specifying the File or Folder to convert
if ($OPath -eq '') {
	Write-Host 'Error: No destination path specified'
    exit
}

# check for the existence of all used path
foreach ($spath in $myPATH.Values) {
	if ((Test-Path -PathType 'Container' $spath) -eq $False) {
        Write-Host "Error: No Path-Found called $spath."
        exit
    }
}


if ($Path -eq '') {
	Write-Host 'Error: No source path/file specified'
} elseif (Test-Path -PathType 'Leaf' $Path) {
    # In case we got a file we encode the file
	CheckAndMove $Path $myPATH['Out']
} elseif (Test-Path -PathType 'Container' $Path) {
    # Else we encode all *.mkv files in the given folder
	Get-ChildItem -Filter '*.mkv' $Path | ForEach-Object { CheckAndMove $_.FullName $myPATH['Out'] }
} else {
	Write-Host "$Path is not a file/folder"
}
