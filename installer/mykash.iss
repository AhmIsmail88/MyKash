; مثبّت MyKash لويندوز (Inno Setup 6). الاستخدام:
;   1) flutter build windows --release
;   2) افتح هذا الملف في Inno Setup Compiler واضغط Compile
;   3) المثبّت يظهر في مجلد dist\
; غيّر AppId إلى GUID جديد خاص بك (Tools > Generate GUID) مرة واحدة ولا تغيّره بعدها.

#define MyAppName "MyKash"
#define MyAppVersion "0.8.0"
#define MyAppPublisher "MyKash"
#define MyAppExeName "mykash.exe"
#define BuildDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={{ACA5C5E5-DA8A-481D-91CD-6AEAE1AB991D}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\MyKash
DefaultGroupName=MyKash
OutputDir=..\dist
OutputBaseFilename=MyKash-Setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#MyAppExeName}
; أيقونة المثبّت (اختياري): ولّد ملف .ico من assets/branding/icon_full.png وضعه هنا
SetupIconFile=..\windows\runner\resources\app_icon.ico

[Tasks]
Name: "desktopicon"; Description: "إنشاء اختصار على سطح المكتب"; Flags: unchecked

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{autoprograms}\MyKash"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\MyKash"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; السماح بمنفذ المزامنة (47615) على الشبكات الخاصة فقط
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""MyKash Sync"" dir=in action=allow protocol=TCP localport=47615 profile=private program=""{app}\{#MyAppExeName}"""; Flags: runhidden; StatusMsg: "ضبط جدار الحماية..."
Filename: "{app}\{#MyAppExeName}"; Description: "تشغيل MyKash"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""MyKash Sync"""; Flags: runhidden; RunOnceId: "RemoveFirewallRule"

; ملاحظة: حذف البرنامج لا يحذف بياناتك (قاعدة البيانات في مجلد المستندات: mykash.sqlite و mykash_backups).
; على جهاز نظيف قد يحتاج Flutter مكتبة Visual C++ Redistributable x64 من مايكروسوفت.
