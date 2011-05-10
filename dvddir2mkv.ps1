Param (
	[string]$Path
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
$myPATH['Out']  = 'D:\Video\'
$PDIR86 = get-programfilesdir

# Configure exe paths here.
$ExePath = @{}
if (is64bit -eq $true ) {
    $ExePath['makemkv']   =  $PDIR86 +  '\MakeMKV\makemkvcon64.exe'
} else {
    $ExePath['makemkv']   =  $PDIR86 +  '\MakeMKV\makemkvcon.exe'
}

$Config = @{}
$Config['makemkv'] = 'mkv --decrypt --progress=-same --noscan -r file:"$DirectoryIn" all $DirectoryOut';

# Check for existence of all Exe-Files
foreach ($Exe in $ExePath.Values) {
	if ((Test-Path -PathType 'Leaf' $Exe) -eq $False) {
		Write-Host "Error: Executable `"$Exe`" not found."
		Write-Host 'Exiting. Edit source file to set up exe paths for x264, bepipe, neroaacenc and mp4box!'
		exit
	}
}

function Encode($FilenameIn) {
    $splittedName=$FilenameIn.split([system.io.path]::DirectorySeparatorChar )
    $Moviename=$splittedName[-3]
    $DirIn=[system.io.path]::GetDirectoryName($FilenameIn)
    Write-Host "Encoding moviename: $Moviename"
    $OPath=$myPATH['Out'] + [system.io.path]::DirectorySeparatorChar + $Moviename+[system.io.path]::DirectorySeparatorChar;
    $OPath=$OPath.replace([system.io.path]::DirectorySeparatorChar + [system.io.path]::DirectorySeparatorChar,[system.io.path]::DirectorySeparatorChar)
    
    if (Test-Path -PathType 'Leaf' $OPath) {
        'Destination is a file and not a directory'
        return $false;
    } elseif (-not (Test-Path -PathType 'Container' $OPath)) {
        mkdir $OPath
    }
    if (-not (Test-Path -PathType 'Container' $OPath)) {
        'Destination directory could not be created'
        return $false
    }

    Write-Host ' - Generating MKV...'
    
    $Process=start-process -PassThru $ExePath['makemkv'] $Config['makemkv'].Replace('$DirectoryIn',$DirIn).Replace('$DirectoryOut',$OPath);
    
    # Loop while the process is running
    while (-not $Process.HasExited) {
    
        # Check if the process used to much calculation time yet (we compare to the real CPU-time to be a bit more independent when more processes are running in parallel)
        If ($Process.TotalProcessorTime -gt [system.TimeSpan]::Parse('03:00:00') ) {
            Write-Host "stopping process, it took to long"
            Stop-Process -InputObject $Process
            $Process.WaitForExit()
        }
        sleep 2
    }
    # Write information about used processing-time to console
    Write-Host " - used processor time: " + $Process.TotalProcessorTime
}

# check if a parameter is given specifying the File or Folder to convert
if ($Path -eq '') {
	Write-Host 'Error: No path specified'
} elseif (Test-Path -PathType 'Leaf' $Path) {
    # In case we got a file we encode the file
	Encode $Path
} elseif (Test-Path -PathType 'Container' $Path) {
    # Else we encode all *.mkv files in the given folder
	Get-ChildItem -Recurse -Filter "VIDEO_TS.ifo" $Path | ForEach-Object { Encode $_.FullName }
} else {
	Write-Host "$Path is not a file/folder"
}
