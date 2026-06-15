@echo OFF
REM Cleaner of old stuff (for WebSigner)
REM 
:CHECKPERMISSION
ATTRIB %windir%\system32 -h | FINDSTR /I "system32" >nul
IF %ERRORLEVEL% NEQ 1 (
    ECHO.
    ECHO This script MUST be launched in Administrator mode.
    ECHO.
    GOTO ERROR_ADMIN
)
echo Launching CLEANER sequence. This process may take several minutes...

set PATCH644_GUID=37B6CEA4-66D9-4597-8FE2-2D2675EE8E6D
set PATCH644_EXE_NAME=Classic_Client_644_Patch_x86_x64.exe
set PATCH645_GUID=F7296E96-16C9-41EE-8802-22B4BD682CB9
set PATCH645_EXE_NAME=Classic_Client_645_Patch_x86_x64.exe

REM Managing x86/x64 machines (for efficiency)
if NOT "%ProgramW6432%"=="" GOTO 64B_UNINSTALL

:32B_UNINSTALL
echo Uninstall eSigner (32 bits machine)
REM ////////// eSigner 7.1.0 32 Bit CORP/IS //////////
MsiExec.exe /X {5A62CB5B-92D5-4800-BB5C-03F9AB77578A} /qn
REM ////////// eSigner 7.1.1 32 Bit CORP/IS and next //////////
MsiExec.exe /X {eb07c76a-f0be-4e4a-813c-00237bafb160} /qn
MsiExec.exe /X {EB07C76A-F0BE-4E4A-813C-00237BAFB160} /qn
REM ////////// eSigner 6.x 32 Bit Bundle //////////
MsiExec.exe /x {A44955F5-F937-4F62-AF4F-04FF3983A720} /qn
REM ///////////////////////eSigner 5.x IS/Corp 32 Bit/////////////////
MsiExec.exe /x {562D3E7B-705F-40EC-A8F8-D8A664A09F3E} /qn
REM /////////////////////////eSigner 4.0.7.003/////////////////////////
MsiExec.exe /x {A43BF6A5-D5F0-4AAA-BF41-65995063EC44} /qn
REM ////////////////////////////eSigner 4/////////////////////////////
MsiExec.exe /x {C96C56FE-03C4-4CE6-AAFF-2642B09BB72B} /qn
REM /////////////////////////eSigner 3.0.4 Corp///////////////////////
MsiExec.exe /x {A05997D5-C080-49E3-93E6-ADE04B272B4F} /qn
REM ////////////////////////eSigner 3.0.4 IS//////////////////////////
MsiExec.exe /x {240EDC84-5F1F-455A-A094-645106D77E08} /qn
REM //////////////////////ISIL Component  (3.0.2)/////////////////////
MsiExec.exe /x {0267003F-9A3B-4C70-84D2-0F3A279463D0} /qn
REM //////////////eSigner CORP 3.0.2 eSigner_Core Module//////////////
MsiExec.exe /x {9710F174-2AA2-426B-A052-D2D15328383E} /qn

echo Uninstall PC PINPad 32b (if any)
REM ////////// PC PINPad Legacy 4.1.3.3 //////////////
MsiExec.exe /x {7252E9B2-C88E-4B8D-A9D9-C7E13A48FC80} /qn

echo Uninstall CCID 32b (if any)
REM ////////// CCID 4.1.4.0 //////////////
MsiExec.exe /x {1A30B094-4E37-44AB-AE35-E72C30F54F76} /qn

echo Uninstall MD 32b (if any)
REM ////////// MD SafeNet minidriver 10.8.x //////////////
MsiExec.exe /x {6092516A-295C-49D0-86AA-9EC869B9D3F2} /qn

GOTO COMMON_UNINSTALL

:64B_UNINSTALL
echo Uninstall eSigner (64 bits machine)
REM ////////// eSigner 7.1.0 32 Bit CORP/IS //////////
MsiExec.exe /X {5A62CB5B-92D5-4800-BB5C-03F9AB77578A} /qn
REM ////////// eSigner 7.1.1 32 Bit CORP/IS and next //////////
MsiExec.exe /X {eb07c76a-f0be-4e4a-813c-00237bafb160} /qn
MsiExec.exe /X {EB07C76A-F0BE-4E4A-813C-00237BAFB160} /qn
REM ////////// eSigner 7.1.0 64 Bit CORP/IS //////////
MsiExec.exe /X {6299E39D-7445-4FF3-BC85-74450096A287} /qn
REM ////////// eSigner 7.1.1 64 Bit CORP/IS and next //////////
MsiExec.exe /X {a6c2d805-2c27-4476-8ff4-989508cfc573} /qn
MsiExec.exe /X {A6C2D805-2C27-4476-8FF4-989508CFC573} /qn
REM /////////// eSigner 6.x 64Bit Bundle////////////
MsiExec.exe /x {ABBA3283-FE97-4223-BE77-281D85A8CB6D} /qn
REM ///////////////////////Schlumberger uninstall/////////////////////
MsiExec.exe /x {440CB343-185B-4A98-92B4-9F73334DD4F8} /passive
REM ///////////////////////eSigner 5.x Corp/IS 32bits/////////////////
MsiExec.exe /x {562D3E7B-705F-40EC-A8F8-D8A664A09F3E} /qn
REM //////////////////eSigner 4.3 IS 64 Bit and 4.4 Corp 64 bits//////
MsiExec.exe /x {167F8EE9-83CE-471C-A7D1-BC777F0A8638} /qn
REM ///////////////////////eSigner 4.2.18 64 Bit//////////////////////
MsiExec.exe /x {A72D849D-3320-43F6-B974-8CB3F0056E47} /qn
REM ////////////////////////eSigner 4 .7.003/////////////////////////
MsiExec.exe /x {A43BF6A5-D5F0-4AAA-BF41-65995063EC44} /qn
REM ////////////////////////////eSigner 4////////////////////////////
MsiExec.exe /x {C96C56FE-03C4-4CE6-AAFF-2642B09BB72B} /qn
REM ////////////////////////eSigner 3.0.6 Corp////////////////////////
MsiExec.exe /x {A05997D5-C080-49E3-93E6-ADE04B272B4F} /qn
REM ////////////////////////eSigner 3.0.6 IS//////////////////////////
MsiExec.exe /x {240EDC84-5F1F-455A-A094-645106D77E08} /qn

echo Uninstall PC PINPad 64b (if any)
REM ////////// PC PINPad Legacy 4.1.3.3 //////////////
MsiExec.exe /x {92A4E5F7-3817-4576-9FDC-12869B89CAED} /qn

echo Uninstall MD 64b (if any)
REM ////////// MD SafeNet minidriver 10.8.x //////////////
MsiExec.exe /x {0BBF52CA-BC5D-4A2C-9A8C-957D91986EBF} /qn

GOTO COMMON_UNINSTALL

:ERROR_ADMIN
pause
GOTO END

:COMMON_UNINSTALL
echo Uninstall Classic Client
REM ////////// ClassicClient 6.5.2 b01         32 &  64 Bit //////////////
MsiExec.exe /x {1E29E48D-034A-4B69-AF02-6863169CC965} /qn REBOOT=ReallySuppress
REM ////////// ClassicClient 6.5.1 b01         32 &  64 Bit //////////////
MsiExec.exe /x {599D24F5-5ABC-4ECB-897D-11B6D6F0DECC} /qn REBOOT=ReallySuppress
REM ////////// ClassicClient 6.5.0 b01         32 &  64 Bit //////////////
MsiExec.exe /x {AA9963C7-99B2-40BE-845B-97343E2725A0} /qn REBOOT=ReallySuppress
REM ////////// ClassicClient 6.4.5 b01         32 &  64 Bit //////////////
MsiExec.exe /x {2E8883D6-9186-406D-8653-E0822F9D747D} /qn REBOOT=ReallySuppress
REM ////////// ClassicClient 6.4.4 b01         32 &  64 Bit //////////////
MsiExec.exe /x {16BE3026-5D56-4C70-99CE-AD00C660A280} /qn REBOOT=ReallySuppress
REM ////////// ClassicClient 6.4.3 b01         32 &  64 Bit //////////////
MsiExec.exe /x {84e3816e-1302-4d7b-b16c-b9f74419341a} /qn REBOOT=ReallySuppress
REM ////////// ClassicClient 6.4.2 b01         32 &  64 Bit //////////////
MsiExec.exe /x {036c0c0e-ad06-423c-96c6-259f272cb7fe} /qn REBOOT=ReallySuppress
REM ////////// ClassicClient 6.4.1 b01         32 &  64 Bit //////////////
MsiExec.exe /x {34b5bb7a-bde2-452d-ae2d-a96b8fff8191} /qn REBOOT=ReallySuppress
REM ////////// ClassicClient 6.4.0 b05         32 &  64 Bit //////////////
MsiExec.exe /x {57950ec0-e4ac-4199-9b2e-fc1c45828626} /qn REBOOT=ReallySuppress
REM ////////// ClassicClient 6.3.12 b08         32 &  64 Bit //////////////
MsiExec.exe /x {a1a489a6-6957-4f0f-8ad3-93290cb10fc6} /qn REBOOT=ReallySuppress
REM ////////// ClassicClient 6.3.12 b07         32 &  64 Bit //////////////
MsiExec.exe /x {3a06e0d8-7b7c-4044-bf75-2817fd4384aa} /qn REBOOT=ReallySuppress
REM ////////// ClassicClient 6.3.12 b06 		32 &  64 Bit //////////////
MsiExec.exe /x {47242eef-f9f0-4725-b495-36b78b2b764e} /qn REBOOT=ReallySuppress
REM ////////// ClassicClient 6.3.12 b05 		32 &  64 Bit //////////////
MsiExec.exe /x {1a475ce0-072f-4112-a944-63f50b932b24} /qn REBOOT=ReallySuppress
REM ////////// ClassicClient 6.3.12 b04 		32 &  64 Bit //////////////
MsiExec.exe /x {ca69022e-232e-4017-a35f-83ae631154f6} /qn REBOOT=ReallySuppress
REM ////////// ClassicClient 6.3.12 b03 		32 &  64 Bit //////////////
MsiExec.exe /x {e261c1a9-9c5a-4732-aadd-afd2a7fb04dd} /qn REBOOT=ReallySuppress
REM ////////// ClassicClient 6.3.11 b04 		32 &  64 Bit //////////////
MsiExec.exe /x {f6b6174e-984e-4b98-b1cf-71263af6a481} /qn REBOOT=ReallySuppress
REM ////////// ClassicClient 6.3.11 b03 		32 &  64 Bit //////////////
MsiExec.exe /x {91ee7a0b-8b33-44b4-9346-42768baea540} /qn REBOOT=ReallySuppress
REM ////////// ClassicClient 6.3.9 b05 		32 &  64 Bit //////////////
MsiExec.exe /x {27dbdce3-2ac3-4f49-8558-2bb38bc70cfe} /qn REBOOT=ReallySuppress
REM ////////// ClassicClient 6.3.9 b04 		32 &  64 Bit //////////////
MsiExec.exe /x {29e11125-3be6-4a31-ba40-be820c72b678} /qn REBOOT=ReallySuppress 
REM ////////// ClassicClient 6.3.8 		32 & 64 ////////////////////
MsiExec.exe /x {49C80959-79B0-4ED2-8D46-47BA27F0EAE3} /qn REBOOT=ReallySuppress
REM ////////// ClassicClient 6.3.5 		32 & 64 ////////////////////
MsiExec.exe /x {41CF4483-F028-4476-B73A-34B185F6389C} /qn REBOOT=ReallySuppress
REM ////////// ClassicClient 6.3.4 		32 & 64 //////////////////////
MsiExec.exe /x {56936EDD-D7B5-4A97-946D-602FA7B7E575} /qn REBOOT=ReallySuppress
REM ////////// ClassicClient 6.3 Patch 2 	32 & 64/////////////////
MsiExec.exe /x {A21ADD97-F57A-4971-9435-6D4A47A6EDDE} /qn REBOOT=ReallySuppress
REM ////////// ClassicClient 6.3 Patch 1 32 & 64    ////////////////
MsiExec.exe /x {E85DA95A-9C1F-43DB-93CC-FEF94CE654D0} /qn REBOOT=ReallySuppress
REM ////////// ClassicClient 6.3 			32 & 64 ///////////////////////
MsiExec.exe /x {D641B12D-CD39-47C2-AAE8-032A0EAF1416} /qn REBOOT=ReallySuppress
REM ////////// ClassicClient 6.2 SP1 		32 & 64//////////////////////
MsiExec.exe /x {66B35780-9D34-4586-B60A-AEFBFD53976E} /qn REBOOT=ReallySuppress
REM ////////// ClassicClient 6.1 SP3			32 & 64///////////////////////
MsiExec.exe /x {F2B7F75B-0BE7-476C-A1A9-F227D25C9439} /qn REBOOT=ReallySuppress
REM ////////// ClassicClient 6.0 SP1  Update1 	32 & 64//////////////////
MsiExec.exe /x {B6F6C95C-AA88-47A8-BB2A-125EBDF4C5C8} /qn REBOOT=ReallySuppress
REM ////////// Classic Client 6 Patch 3		32 & 64////////////////////
MsiExec.exe /x {DB3231BE-1316-4002-80BE-1EB9E8818EEB} /qn REBOOT=ReallySuppress
REM ////////// Classic Client 6 			32 & 64////////////////////////
MsiExec.exe /x {8D4DAF79-8A5A-4469-9AB6-FC8B411AD8F7} /qn REBOOT=ReallySuppress
REM ////////// ClassicClient SP1  6.0 Update1 ADMIN ////////////////
MsiExec.exe /x {64D19F0F-4881-4E2B-930A-ED1B1E98E1DE} /qn REBOOT=ReallySuppress
REM ////////// Classic Client 5.2 				32 & 64/////////////////
MsiExec.exe /x {D7D8623B-00E8-496C-BAAF-822FBE33A46B}  /qn REBOOT=ReallySuppress

REM ///////////////////////CC 5.2 Administrator///////////////////////
MsiExec.exe /x {A1B1950C-2A63-4110-9C19-5D1B52960E16} /qn REBOOT=ReallySuppress
REM //////////////////////CC 5.1.5 Administrator//////////////////////
MsiExec.exe /x {CCB8DE10-F2E8-4965-A112-6A495FAAE028} /qn REBOOT=ReallySuppress 
REM ///////////////////////Classic Client 5.1.5///////////////////////
MsiExec.exe /x {4BF18ED6-C888-4BCF-A4AF-AC7A16305BC1} /qn REBOOT=ReallySuppress

echo Uninstall GBDM (if any)
REM ////////// GBDM 3.3.0 //////////////
MsiExec.exe /X {5837F1B6-1BC9-47BA-A900-0603237DB2BE} /qn REBOOT=ReallySuppress
REM ////////// GBDM 4.0.3.x //////////////
MsiExec.exe /X {036F8B2A-F741-47F9-8EFC-416935985A2B} /qn REBOOT=ReallySuppress

REM //// PreInstall eSigner 6x (for Suite MSI) ///
MsiExec.exe /x {53CD1D9C-C91E-4EE3-B22F-69A2197427C9} /qn

echo Uninstall CCID 64b (if any)
REM ////////// CCID 4.1.4.0 //////////////
MsiExec.exe /x {39417D48-AC92-47A7-9F53-3CA2049231B0} /qn

:END_UNINSTALL

REM Managing x86/x64 machines again for Bundles uninstallation (after chained MSIs)
if NOT "%ProgramW6432%"=="" GOTO 64B_UNINSTALL_BUNDLES

echo Uninstall WebSigner Bundle (32 bits machine)
REM //////////////WebSigner backend 32b (Barclays)//////////////
MsiExec.exe /x {F1F0FF6B-84B8-461B-A79F-F902DE28D4F3} /qn
REM //////////////WebSigner backend 32b (Demo)//////////////
MsiExec.exe /x {4EAC6FD4-E647-4A3D-87C5-B6D30AC1FDD4} /qn
REM ////////////////////////WebSigner Bundle 32b RnD ////////////////////
MsiExec.exe /x {1A9BCF2B-19B6-42CF-BD3F-530AC3C7BF0C} /qn
REM ////////////////////////WebSigner Bundle 32b (Barclays) ////////////////////
MsiExec.exe /x {551884B3-41F9-4769-8DF8-F4D2010C740F} /qn
REM //////////////WebSigner backend 32b (CYBG)//////////////
MsiExec.exe /x {663FD148-4DC1-44EB-A733-A2554281E7C2} /qn

REM special action for patch 644 (if any)
if exist "C:\Program Files\InstallShield Installation Information\{%PATCH644_GUID%}\%PATCH644_EXE_NAME%" (
  echo Uninstall CC Patch 6.4.4
  "C:\Program Files\InstallShield Installation Information\{%PATCH644_GUID%}\%PATCH644_EXE_NAME%" -passive -remove -runfromtemp
  del /Q "C:\Program Files\InstallShield Installation Information\{%PATCH644_GUID%}\%PATCH644_EXE_NAME%"
)
REM idem for patch 645 (if any)
if exist "C:\Program Files\InstallShield Installation Information\{%PATCH645_GUID%}\%PATCH645_EXE_NAME%" (
  echo Uninstall CC Patch 6.4.5
  "C:\Program Files\InstallShield Installation Information\{%PATCH645_GUID%}\%PATCH645_EXE_NAME%" -passive -remove -runfromtemp
  del /Q "C:\Program Files\InstallShield Installation Information\{%PATCH645_GUID%}\%PATCH645_EXE_NAME%"
)

GOTO END_CLEANER

:64B_UNINSTALL_BUNDLES

echo Uninstall WebSigner Bundle and BEs (64 bits machine)
REM //////////////WebSigner backend 64b(Barclays)//////////////
MsiExec.exe /x {1C1525A9-8CE3-4E4D-9902-E96C2DE301E5} /qn
REM //////////////WebSigner backend 64b (Demo)//////////////
MsiExec.exe /x {273C8350-AFAA-4A58-895C-A00BDE882E94} /qn
REM ////////////////////////WebSigner Bundle RnD ////////////////////
MsiExec.exe /x {6D93B9F2-B027-421D-BB40-685EAC34EFBF} /qn
REM // Special case (after Bundle RnD above) ///
MsiExec.exe /X {aa2a4fa2-cf34-4f40-af66-d5b18ac48a33} /qn
REM ////////////////////////WebSigner Bundle 64b Barclays////////////////////
MsiExec.exe /x {7B9FA02E-4AF7-42AE-91E8-CBC83D5527A8} /qn
REM //////////////WebSigner backend 64b (CYBG)//////////////
MsiExec.exe /x {3FE51E2B-55C4-4334-8172-9F04050A851F} /qn

REM special action for patch 644 (if any)
if exist "C:\Program Files (x86)\InstallShield Installation Information\{%PATCH644_GUID%}\%PATCH644_EXE_NAME%" (
  echo Uninstall CC Patch 6.4.4
  "C:\Program Files (x86)\InstallShield Installation Information\{%PATCH644_GUID%}\%PATCH644_EXE_NAME%" -passive -remove -runfromtemp
  del /Q "C:\Program Files (x86)\InstallShield Installation Information\{%PATCH644_GUID%}\%PATCH644_EXE_NAME%"
)
REM idem for patch 645 (if any)
if exist "C:\Program Files (x86)\InstallShield Installation Information\{%PATCH645_GUID%}\%PATCH645_EXE_NAME%" (
  echo Uninstall CC Patch 6.4.5
  "C:\Program Files (x86)\InstallShield Installation Information\{%PATCH645_GUID%}\%PATCH645_EXE_NAME%" -passive -remove -runfromtemp
  del /Q "C:\Program Files\InstallShield Installation Information\{%PATCH645_GUID%}\%PATCH645_EXE_NAME%"
)

:END_CLEANER
echo Cleaner sequence done.

:END
