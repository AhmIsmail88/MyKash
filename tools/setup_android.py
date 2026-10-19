#!/usr/bin/env python3
"""يجهّز مشروع أندرويد بعد `flutter create` (آمن للتكرار):
  - صلاحيات INTERNET والكاميرا (والكاميرا غير إجبارية)
  - اسم التطبيق MyKash
  - minSdk = 23

  python tools/setup_android.py <مجلد مشروع Flutter>
"""
import os, re, sys

root = sys.argv[1] if len(sys.argv) > 1 else "."
manifest = os.path.join(root, "android/app/src/main/AndroidManifest.xml")
if not os.path.exists(manifest):
    sys.exit("لم أجد AndroidManifest.xml. شغّل flutter create أولًا وأعطني مجلد المشروع.")

s = open(manifest, encoding="utf-8").read()
needed = [
    '<uses-permission android:name="android.permission.INTERNET" />',
    '<uses-permission android:name="android.permission.CAMERA" />',
    '<uses-feature android:name="android.hardware.camera" android:required="false" />',
]
add = [n for n in needed if n.split('android:name="')[1].split('"')[0] not in s]
if add:
    s = re.sub(r"(<manifest[^>]*>)", lambda m: m.group(1) + "\n    " + "\n    ".join(add), s, count=1)
s = re.sub(r'android:label="[^"]*"', 'android:label="MyKash"', s, count=1)
open(manifest, "w", encoding="utf-8").write(s)
print("AndroidManifest.xml: تم (صلاحيات + الاسم)")

done = False
for name in ("build.gradle.kts", "build.gradle"):
    path = os.path.join(root, "android/app", name)
    if not os.path.exists(path):
        continue
    g = open(path, encoding="utf-8").read()
    g2 = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 23", g)
    g2 = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 23", g2)
    g2 = re.sub(r"minSdk\s*=\s*(\d+)", lambda m: "minSdk = 23" if int(m.group(1)) < 23 else m.group(0), g2)
    g2 = re.sub(r"minSdkVersion\s+(\d+)", lambda m: "minSdkVersion 23" if int(m.group(1)) < 23 else m.group(0), g2)
    open(path, "w", encoding="utf-8").write(g2)
    print(f"{name}: minSdk -> 23" + ("" if g2 != g else " (لا تغيير مطلوب أو لم أجد السطر، راجعه يدويًا)"))
    done = True
if not done:
    print("تنبيه: لم أجد build.gradle(.kts)؛ اضبط minSdk = 23 يدويًا.")
