# بناء MyKash وإصداره

## 0) إعداد المشروع (مرة واحدة)
```bash
flutter create --platforms=android,windows --org com.mykash --project-name mykash mykash_app
# انسخ pubspec.yaml و lib/ و assets/ و tools/ و installer/ و docs/ فوق mykash_app
cd mykash_app
python tools/setup_android.py .          # صلاحيات + اسم التطبيق + minSdk 23
flutter pub get
dart run build_runner build --delete-conflicting-outputs
dart run flutter_launcher_icons          # أيقونة العملة الذهبية K
```
**اسم الحزمة (Package ID):** الافتراضي `com.mykash.mykash`. غيّره الآن لو تريد اسمًا آخر
(`applicationId` في `android/app/build.gradle(.kts)`)، لأنه لا يتغير بعد النشر على Google Play.

## 1) ترخيص (اختياري، لو ستبيع التطبيق)
```bash
pip install cryptography
python tools/license/gen_keys.py          # ينشئ license_private.key (سرّي!) ويطبع المفتاح العام
```
1. الصق المفتاح العام في `lib/core/license/license_key.dart` ثم اجعل `kLicensingEnabled = true`.
2. **احتفظ بـ `license_private.key` خارج المشروع** وبنسخة احتياطية؛ لو ضاع لن تستطيع إصدار تراخيص جديدة تطابق التطبيق.
3. العميل ينسخ «معرّف الجهاز» من الإعدادات ← الترخيص ويرسله لك، وأنت تصدر:
```bash
python tools/license/make_license.py --key license_private.key --shop "اسم المحل" \
  --machine <معرّف_الديسك_توب> --machine <معرّف_الموبايل> --expires 2027-12-31
```
4. العميل يلصق الكود في الإعدادات ← الترخيص. التجربة المجانية 30 يومًا (`kTrialDays`).

> الترخيص الأوفلاين يمنع الاستخدام العادي غير المرخّص لكن يمكن لمستخدم متمكّن الالتفاف عليه.
> بعد انتهاء الترخيص يُمنع البيع لكن يبقى تفعيل الكود وتصدير نسخة احتياطية متاحين (لا تُحجز بيانات العميل).

## 2) ويندوز
```bash
flutter build windows --release
```
ثم ثبّت [Inno Setup 6](https://jrsoftware.org/isinfo.php)، افتح `installer/mykash.iss`، غيّر `AppId` لـ GUID خاص بك، واضغط Compile.
المثبّت يظهر في `dist/` ويضبط جدار الحماية لمنفذ المزامنة (الشبكات الخاصة). على جهاز نظيف ثبّت
*Visual C++ Redistributable x64* إن طلبه التطبيق.

## 3) أندرويد (APK موقّع)
1. أنشئ مفتاح التوقيع (مرة واحدة، **احفظه واحفظ كلمة السر**؛ لا يمكن تحديث التطبيق بدونه):
```bash
keytool -genkey -v -keystore ~/mykash-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias mykash
```
2. أنشئ `android/key.properties` (ولا ترفعه لأي مستودع):
```
storePassword=كلمة_السر
keyPassword=كلمة_السر
keyAlias=mykash
storeFile=/المسار/الكامل/mykash-release.jks
```
3. في `android/app/build.gradle.kts` أضف أعلى الملف:
```kotlin
import java.util.Properties
import java.io.FileInputStream
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) load(FileInputStream(f))
}
```
وداخل `android { ... }`:
```kotlin
signingConfigs {
    create("release") {
        keyAlias = keystoreProperties["keyAlias"] as String
        keyPassword = keystoreProperties["keyPassword"] as String
        storeFile = file(keystoreProperties["storeFile"] as String)
        storePassword = keystoreProperties["storePassword"] as String
    }
}
buildTypes { release { signingConfig = signingConfigs.getByName("release") } }
```
(لو مشروعك بصيغة Groovy `build.gradle` فالمبدأ نفسه؛ راجع توثيق Flutter «Build and release an Android app».)
4. البناء:
```bash
flutter build apk --release           # ملف للتثبيت المباشر على أجهزة المحل
flutter build appbundle --release     # لو ستنشر على Google Play
```
الناتج: `build/app/outputs/flutter-apk/app-release.apk`.

## 4) رفع الإصدار
عند كل إصدار: غيّر `version` في `pubspec.yaml`، و`kAppVersion` في `lib/core/app_info.dart`، و`MyAppVersion` في `installer/mykash.iss`.
تغيير `kAppVersion` يجعل التطبيق يأخذ نسخة أمان من القاعدة قبل أي ترحيل عند أول تشغيل بعد التحديث.
