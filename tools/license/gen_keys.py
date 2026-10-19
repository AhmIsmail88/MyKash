#!/usr/bin/env python3
"""يولّد زوج مفاتيح Ed25519 لنظام الترخيص (مرة واحدة فقط).

  python tools/license/gen_keys.py

الناتج:
  license_private.key  ← سرّي: احتفظ به عندك فقط (لا تضعه في المشروع ولا ترسله لأحد)
  ويطبع المفتاح العام لتلصقه في lib/core/license/license_key.dart (kLicensePublicKeyB64)
المتطلبات: pip install cryptography
"""
import base64, os, sys
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives import serialization

out = sys.argv[1] if len(sys.argv) > 1 else "license_private.key"
if os.path.exists(out):
    sys.exit(f"الملف {out} موجود بالفعل. لن أستبدله (فقدان المفتاح الخاص يعني أن كل التراخيص السابقة لا يمكن إصدار مثلها).")

key = Ed25519PrivateKey.generate()
raw_priv = key.private_bytes(serialization.Encoding.Raw, serialization.PrivateFormat.Raw, serialization.NoEncryption())
raw_pub = key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
with open(out, "w") as f:
    f.write(base64.b64encode(raw_priv).decode())
os.chmod(out, 0o600)
print("تم إنشاء المفتاح الخاص في:", out, "(احفظ نسخة احتياطية منه في مكان آمن)")
print("\nالصق هذا المفتاح العام في lib/core/license/license_key.dart:\n")
print("const String kLicensePublicKeyB64 = '%s';" % base64.b64encode(raw_pub).decode())
print("\nثم اجعل kLicensingEnabled = true وأعد بناء التطبيق.")
