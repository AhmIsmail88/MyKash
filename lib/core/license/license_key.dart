/// المفتاح العام للتحقق من أكواد الترخيص (Ed25519، Base64).
/// يُولَّد مرة واحدة بالأداة tools/license/gen_keys.py ويُلصق هنا.
/// المفتاح الخاص (license_private.key) يبقى عندك أنت فقط ولا يوضع في المشروع أبدًا.
const String kLicensePublicKeyB64 = '2lAiuObfKxp6gvw5WJ5IzDg7lUUFCI6y/tAdm+jwAqw=';

/// فعّله بعد ضبط المفتاح العام. وهو معطّل افتراضيًا فلا يُقفل التطبيق أثناء التجربة.
const bool kLicensingEnabled = true;
/// Salt used to make the local licence-state file tamper-evident.
///
/// This is obfuscation, not secrecy: it stops a hand-edited state file from
/// being accepted, but anyone with the binary can recover it. The guarantee
/// that actually matters is the Ed25519 signature on the licence code.
const String kLicenseStateSecret = 'mykash-state-v1-7d41c9ab3e6f5082';