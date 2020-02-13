#Persistent
#SingleInstance, force 
SetWorkingDir %A_ScriptDir%

HDHomeRunDirectory := "C:\Program Files\Silicondust\HDHomeRun"
VLCPath := "C:\Program Files\VideoLAN\VLC\vlc.exe"
aVLC := []
vlcIndex := 1

RegRead, RunOnStartUp, HKEY_CURRENT_USER, Software\Microsoft\Windows\CurrentVersion\Run, HDHomeRunAHK
if (RunOnStartUp := !ErrorLevel) && RunOnStartUp != A_ScriptFullPath " --background" ; user Moved the script
	RegWrite, REG_SZ, HKEY_CURRENT_USER, Software\Microsoft\Windows\CurrentVersion\Run, HDHomeRunAHK, "%A_ScriptFullPath%" --background

Menu, Tray, Icon, tv.png,, 1
Menu, tray, NoStandard

Menu, tray, Add, GUI, showGUI
Menu, tray, Default, GUI ; menu separator line
Menu, tray, Add
Menu, tray, add , Exit, exit 

for n, param in A_Args 
{
    if (param = "--background")
    	return
}

showGUI:
Gui +LastFoundExist
IfWinExist 
{
	WinActivate
	Return 									; prevent error due to reloading gui 
}

Gui, Add, ListView, x+15 y+15 w270 -Multi -Hdr R25 ReadOnly vLVDummy gListView, Number|Name|link
Gui, Add, Button, xp y+25 w60 h40 gRefreshChannels, Refresh 
Gui, Add, Radio, x+30 yp+15 vChannelA gChannelA checked, A
Gui, Add, Radio, x+10 yp vChannelB gChannelB, B

Gui, Add, Checkbox, x+25 yp vRunOnStartUp Checked%RunOnStartUp% gToggleStartUp, Run on startup

Gui, Add, Button, Hidden Default gEnterKeyInput, OK ; Default!
gosub % isobject(aChannels) ? "listChannels" :  "refreshChannels"
Gui, Show,, TV
return 

GuiClose:
Gui Destroy
return 

exit:
exitapp
return 

ChannelA:
vlcIndex := 1
return 

ChannelB:
vlcIndex := 2
return 

ToggleStartUp:
GuiControlGet, RunOnStartUp
if RunOnStartUp
	RegWrite, REG_SZ, HKEY_CURRENT_USER, Software\Microsoft\Windows\CurrentVersion\Run, HDHomeRunAHK, "%A_ScriptFullPath%" --background
else RegDelete, HKEY_CURRENT_USER, Software\Microsoft\Windows\CurrentVersion\Run, HDHomeRunAHK
return  


CheckURL(Url, timeoutMS = ""){ 
	whr := ComObjCreate("Msxml2.ServerXMLHTTP.6.0") ; "WinHttp.WinHttpRequest.5.1" doesnt have readyState
	whr.Open("GET", Url, true) ; Using 'true' above and the call below allows the script to remain responsive.
	whr.Send()
	
	startTick := A_TickCount
	while (whr.readyState != 4)
	{
		if (A_TickCount - startTick >= timeoutMS)
			return false

		sleep 20	
	}
	
	return 	whr.status = 200 
			|| whr.status = 401 ;  Unauthorized error, but something there
}

refreshChannels:
LV_Delete()
if !RegExMatch(RunWaitOne("""" HDHomeRunDirectory "\hdhomerun_config.exe"  """ discover"), "hdhomerun device ([[:xdigit:]]+) found at (\d+.\d+.\d+.\d+)", host)
	return
aChannels := getChannels(host2)
listChannels:
for i, channel in aChannels
	LV_Add(, channel.number, channel.name, channel.link)

LV_ModifyCol(3, 0) ; set column width to 0
LV_ModifyCol(1, "Auto"), LV_ModifyCol(2, "Auto") 
return 

EnterKeyInput:
GuiControlGet, FocusedControl, FocusV ; Retrieves the name of the focused control's associated variable.
if (FocusedControl != "LVDummy")
    return
LV_GetText(link, LV_GetNext(, "Focused"), 3)
ListView:
if (A_ThisLabel = "ListView")
{
	if (A_GuiEvent = "DoubleClick")
		LV_GetText(link, A_EventInfo, 3)
	else return 
}
index := vlcIndex  ; copy to tmp var incase changes during function call
if !IsObject(aVLC[index]) || !WinExist("ahk_pid " aVLC[index].pid)
	aVLC[index] := vlc_launch(VLCPath)
vlc_input(link, aVLC[index])	

return


if (A_GuiEvent = "DoubleClick" )
{
	LV_GetText(link, A_EventInfo, 3)
	index := vlcIndex 
	if !IsObject(aVLC[index]) || !WinExist("ahk_pid " aVLC[index].pid)
		aVLC[index] := vlc_launch(VLCPath)
	vlc_input(link, aVLC[index])	
}
return 


; Good example
; https://www.autohotkey.com/boards/viewtopic.php?f=5&t=5830&start=20
; When logging in, leave the username field blank
/*
--extraintf=<string>       Extra interface modules
          You can select "additional interfaces" for VLC. They will be launched
          in the background in addition to the default interface. Use a colon
          separated list of interface modules. (common values are "rc" (remote
          control), "http", "gestures" ...)
*/

vlc_launch(VLCPath := "C:\Program Files\VideoLAN\VLC\vlc.exe", address := "")
{
	; check port isnt in use for something else (or for another instance of VLC)
	port := 8088
	while CheckURL("http://localhost:" port, 200)
	{
		Random, offset, 2, 15
		port += offset
	}

	;  extraintf http = so http interface doesnt need to be enabled in options
	; need to use a password for http interface to be accessible 
	options := "--extraintf http --network-caching=1000 --http-port=" port " --http-password=abc"

	Run, % VLCPath  " " options " "  address,,, pid ; address cab be used to open file etc when launching
	return {pid: pid, password: Base64Encode(":abc"), host: "localhost:" port } ; note the additional ':' in encoded password
}



vlc_PlayPause(vlcObj)
{
	req := ComObjCreate("Msxml2.XMLHTTP")
	req.open("GET", "http://" vlcObj.host "/requests/status.xml?command=pl_pause", true)
	req.SetRequestHeader("Authorization", "Basic " vlcObj.password)
	req.send()
}
/*
https://wiki.videolan.org/VLC_command-line_help

URL syntax:
  file:///path/file              Plain media file
  http://host[:port]/file        HTTP URL
  ftp://host[:port]/file         FTP URL
  mms://host[:port]/file         MMS URL
  screen://                      Screen capture
  dvd://[device]                 DVD device
  vcd://[device]                 VCD device
  cdda://[device]                Audio CD device
  udp://[[<source address>]@[<bind address>][:<bind port>]]
                                 UDP stream sent by a streaming server
  vlc://pause:<seconds>          Pause the playlist for a certain time
  vlc://quit                     Special item to quit VLC

 */

vlc_input(link, vlcObj)
{
	req := ComObjCreate("Msxml2.XMLHTTP")
	req.open("GET", "http://" vlcObj.host "/requests/status.xml?command=in_play&input=" link, true)
	req.SetRequestHeader("Authorization", "Basic " vlcObj.password)
	req.send()
}

playTest()
{
	req := ComObjCreate("Msxml2.XMLHTTP")
	;req.open("GET", "http://127.0.0.1:8088/requests/status.xml?command=in_play&input=file:///D:/My Computer/My Documents/BIKE FALL.wmv", true)
	req.SetRequestHeader("Authorization", "Basic " Base64Encode(":abc"))
	req.send()
}
; For more examples:
; https://autohotkey.com/board/topic/83886-vlc-http-2-interface-library-for-lastest-vlc-media-player/
; or debug/capture requests with browser

getChannels(host)
{

	ie	:= ComObjCreate("InternetExplorer.Application")
	ie.visible := false
	ie.navigate("http://" host "/lineup.html")
	while ie.ReadyState != 4
		Sleep, 100
	
	sleep 100
	aChannels := {}
	loop % (rows := ie.document.getElementById("channelTable").all.tags( "tr" )).length
	{
		rowDataItems := rows[ A_Index-1 ].all.tags( "td" )
		aChannels.insert(	{ 	number:  rowDataItems[1].innerText
							,	name:  rowDataItems[2].innerText
							,	link: rowDataItems[1].getElementsByTagName("a")[0].getAttribute("href") } )
	}
	ie.quit
	return aChannels
}

return 


HTMLTableToText(HTML_Doc, tableIndex := 0)
{
	data := HTML_Doc.forms[0].childNodes[0].innerText "`n"
	table := HTML_Doc.all.tags( "table" )	
	Loop, % ( rows := table[tableIndex].all.tags( "tr" ) ).length {
		If A_Index = 1 ; build headers
			Loop, % ( item := rows[ A_Index-1 ].all.tags( "font" ) ).length
				data .=	item[ A_Index-1 ].innerText
						.	( A_Index<4 ? " " : "`t" ) ; combine first 4 headers in first column
		Else
			Loop, % ( item := rows[ A_Index-1 ].all.tags( "td" ) ).length
				data .=	( (text := item[ A_Index-1 ].innerText) = "" && A_Index=1 ) ? ""
						:	( data~="`n$" && text+0<>"" ? "`t" : "" ) text "`t"
		data .= "`n"
	}
	return data
}




Base64Encode(String)
{
    static CharSet := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    VarSetCapacity(Output,Ceil(Length / 3) << 2)
    Index := 1, Length := StrLen(String)
    Loop, % Length // 3
    {
        Value := Asc(SubStr(String,Index,1)) << 16
            | Asc(SubStr(String,Index + 1,1)) << 8
            | Asc(SubStr(String,Index + 2,1))
        Index += 3
        Output .= SubStr(CharSet,(Value >> 18) + 1,1)
            . SubStr(CharSet,((Value >> 12) & 63) + 1,1)
            . SubStr(CharSet,((Value >> 6) & 63) + 1,1)
            . SubStr(CharSet,(Value & 63) + 1,1)
    }
    Length := Mod(Length,3)
    If Length = 0 ;no characters remaining
        Return, Output
    Value := Asc(SubStr(String,Index,1)) << 10
    If Length = 1
    {
        Return, Output ;one character remaining
            . SubStr(CharSet,(Value >> 12) + 1,1)
            . SubStr(CharSet,((Value >> 6) & 63) + 1,1) . "=="
    }
    Value |= Asc(SubStr(String,Index + 1,1)) << 2 ;insert the third character
    Return, Output ;two characters remaining
        . SubStr(CharSet,(Value >> 12) + 1,1)
        . SubStr(CharSet,((Value >> 6) & 63) + 1,1)
        . SubStr(CharSet,(Value & 63) + 1,1) . "="
}


uriDecode(str) {
	Loop
		If RegExMatch(str, "i)(?<=%)[\da-f]{1,2}", hex)
			StringReplace, str, str, `%%hex%, % Chr("0x" . hex), All
		Else Break
	Return, str
}


RunWaitOne(command) {
    ; WshShell object: http://msdn.microsoft.com/en-us/library/aew9yb99¬
    shell := ComObjCreate("WScript.Shell")
    ; Execute a single command via cmd.exe
    exec := shell.Exec(ComSpec " /C " command)
    ; Read and return the command's output
    return exec.StdOut.ReadAll()
}

RunWaitMany(commands) {
    shell := ComObjCreate("WScript.Shell")
    ; Open cmd.exe with echoing of commands disabled
    exec := shell.Exec(ComSpec " /Q /K echo off")
    ; Send the commands to execute, separated by newline
    exec.StdIn.WriteLine(commands "`nexit")  ; Always exit at the end!
    ; Read and return the output of all commands
    return exec.StdOut.ReadAll()
}

;-------------------------------------------------------------------------------
QPC() { ; microseconds precision
;-------------------------------------------------------------------------------
    static Freq, init := DllCall("QueryPerformanceFrequency", "Int64P", Freq)
    DllCall("QueryPerformanceCounter", "Int64P", Count)
    Return, Count / Freq
}