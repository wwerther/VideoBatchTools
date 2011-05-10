# Description: Batch encoding from AVI file to x264/AAC in MP4 file.
# Example Usage: .\VidBatch.ps1 "D:\Folder_of_AVIs"
# Required tools: x264, bepipe, neroaacenc, mp4box, AviSynth - be sure to adapt exe paths below

Param (
	[string]$Path,      # The input-path/file
	[string]$OPath      # The destinationpath
) 

function is64bit() {
  return ([IntPtr]::Size -eq 8)
}

function get-programfilesdir() {
  if (is64bit -eq $true) {
    (Get-Item "Env:ProgramFiles(x86)").Value
  }
  else {
    (Get-Item "Env:ProgramFiles").Value
  }
}

# Configure paths here. Temporary files (AVS, video, audio) are saved in $TempPath which is cleared out after every file. Muxed video is saved to $OutPath

$myPATH = @{}
$myPATH['Out']  = $OPath
$PDIR86 = get-programfilesdir

# Configure exe paths here.
$ExePath = @{}
$ExePath['handbrake']   =  $PDIR86 +  '\Handbrake\HandBrakeCLI.exe'

$Config = @{}
$Config['handbrakescan'] = '--scan -i "$FilenameIn"';
$Config['handbrake'] = '$AUDIO $CHAPTER $SUBTITLE --format=mkv --loose-anamorphic -x b-adapt=2:rc-lookahead=50 --encoder x264 -q 20 -i "$FilenameIn" -o "$FilenameOut"';

function ReadHandbrake ($Filename, $Arguments) {
	$ProcessInfo1 = New-Object System.Diagnostics.ProcessStartInfo
	$ProcessInfo1.FileName = $Filename
	$ProcessInfo1.Arguments = $Arguments
	$ProcessInfo1.UseShellExecute = $False
	$ProcessInfo1.RedirectStandardOutput = $True
	$ProcessInfo1.RedirectStandardError = $True
	$Process1 = [System.Diagnostics.Process]::Start($ProcessInfo1)
    $Process1.BeginOutputReadLine()
    $Error = $Process1.StandardError.ReadToEnd()
    $Process1.WaitForExit();
    $Error
}

function scanTitle($FilenameIn,$FilenameOut) {
    
    Write-Host '- Scanning video...'
    $Result=ReadHandbrake $ExePath['handbrake'] $Config['handbrakescan'].Replace('$FilenameIn', $FilenameIn) 
    if ($Result -cmatch "No title found.") {
       Write-Host "No title found"
       return $False
       exit;
    }
    
    $DATA=@{}
    $DATA.audio=@{}
    $DATA.subtitle=@{}
    $mode='none'
    foreach ($line in $Result.split("`n")) {        
        $line=$line.trim()
        $line=$line -replace "[\r\n]",''
        switch -regex ($line) {
            '\+ title (\d)'  {
                Write-Host "Start parsing Title-Information " $matches[1]
                $mode='Title';
                break
            }
            '\+ stream: (.*)'  {
                Write-Host " Stream " $matches[1]
                break
            }
            '\+ autocrop: (.*)'  {
                Write-Host " Crop " $matches[1]
                break
            }
            '\+ audio tracks:'  {
                Write-Host "Mode: Audio"
                $mode='audio'
                break
            }
            '\+ subtitle tracks:'  {
                Write-Host "Mode: Subtitle"
                $mode='subtitle'
                break
            }
            '\+ chapters:'  {
                Write-Host "Mode: Chapters"
                $mode='chapter'
                break
            }
            '^\+' {
                switch ($mode) {
                    'audio' {
                        $m=$line -match "(\d+),\s+(.+?)\s+\((.+?)\)\s+\((.+?)\)"
                        $spur=$matches[1]
                        $language=$matches[2]
                        $codec=$matches[3]
                        $channels=$matches[4]
                        Write-Host " AUDIO Spur: $spur Sprache: $language Codec: $codec Kanäle: $channels"
                        #Write-Host " --> $line"
                        switch ($codec) {
                            'AC3' { 
                                $DATA.audio[$spur]='copy' 
                                break
                             }
                            default { 
                                $DATA.audio[$spur]='unknown' 
                                break
                             }
                        }
                        break
                    }
                    'chapter' {
                        #write-Host "CHAPTER: "$line
                        $DATA.chapters=$true;
                        break
                    }
                    'subtitle' {
                        $m=$line -match "(\d+),\s+(.+?)\s"
                        $spur=$matches[1]
                        $language=$matches[2]
                        Write-Host " SUB: Spur: $spur Sprache: $language"
                        $DATA.subtitle[$spur]=$language 
                        break
                    }
                    default {
                       #write-Host $mode": "$line
                    }
                }
                break
            }
            default {
                $mode='none'
               # Write-Host $mode": "$line
            }
        }
    }
    
    $audio=''
    $subtitle=''
    $chapter=''
    
    $keys=$DATA.audio.Keys
    $values=$DATA.audio.Values
    if (@($keys).Length -gt 0) {
        $audio='--audio ' + ($keys -join ',')
        $audio +=' --aencoder ' + ($values -join ',')
    }
    $keys=$DATA.subtitle.Keys
    if (@($keys).Length -gt 0) {
        $subtitle='--subtitle ' + ($keys -join ',')
    }
    if ($DATA.chapters -eq $true) {
        $chapter='--markers'
    }
   
    Write-Host '- Encoding video...'
    Start-Process -PassThru -Wait $ExePath['handbrake'] $Config['handbrake'].Replace('$AUDIO', $audio).Replace('$SUBTITLE', $subtitle).Replace('$CHAPTER', $chapter).Replace('$FilenameIn', $FilenameIn).Replace('$FilenameOut', $FilenameOut) 
}


function Encode($FilenameIn,$DestPath) {

    $Basename = [system.io.path]::GetFilenameWithoutExtension($FilenameIn)
	$FilenameOut = $DestPath + $Basename + '.mkv'
	Write-Host "Encoding $FilenameIn to $FilenameOut"
    if (Test-Path -PathType 'Leaf' $FilenameOut) {
        Write-Host "- Output Videofile already exists. Skipping"
        return
    }

    Write-Host 'Processing video...'
    if (scanTitle $FilenameIn $FilenameOut) {
        Write-Host '- Done'
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

# check if a parameter is given specifying the File or Folder to convert
if ($Path -eq '') {
	Write-Host 'Error: No path/file specified'
} elseif (Test-Path -PathType 'Leaf' $Path) {
    # In case we got a file we encode the file
	Encode $Path $myPath['out']
} elseif (Test-Path -PathType 'Container' $Path) {
    # Else we encode all *.mkv files in the given folder
	Get-ChildItem -Filter '*.mkv' $Path | ForEach-Object { Encode $_.FullName $myPath['out'] }
} else {
	Write-Host "$Path is not a file/folder"
}
