set drive=%1
set dir=%2

set basedir=d:\video
mkdir %basedir%\%dir%\
mkdir %basedir%\%dir%\VIDEO_TS

robocopy /R:2 /W:5 %drive%\video_ts\ %basedir%\%dir%\VIDEO_TS

:: "c:\Program Files (x86)\MakeMKV\makemkvcon64.exe" mkv --decrypt --progress=-same --noscan -r file:%basedir%\%dir%\VIDEO_TS\ all %basedir%\%dir%\
::del "%basedir%\%dir%\*.vob"
::del "%basedir%\%dir%\*.bup"
::del "%basedir%\%dir%\*.ifo"

@echo Done %dir%
