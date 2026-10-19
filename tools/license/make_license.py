#!/usr/bin/env python3
"""يُصدر كود ترخيص موقّعًا لمحل.

أمثلة:
  python tools/license/make_license.py --key license_private.key --shop "بقالة النور" \
      --device <معرّف جهاز 1> --device <معرّف جهاز 2> --expires 2027-12-31
  python tools/license/make_license.py --key license_private.key --shop "محل تجريبي" --device '*' --expires never
  python tools/license/make_license.py --verify "MYK1...." --pub <المفتاح العام Base64>

معرّف الجهاز يظهر في التطبيق: الإعدادات ← الترخيص (يمكن نسخه).
'*' = يصلح لأي جهاز (أقل أمانًا: يمكن مشاركته). expires: YYYY-MM-DD أو never.
المتطلبات: pip install cryptography
"""
import argparse, base64, json, re, sys, time
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey
from cryptography.exceptions import InvalidSignature

MACHINE_RE = re.compile(r"^MACH-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}$")


def normalise_machines(values):
    """Validate machine fingerprints; '*' means any device."""
    out = []
    for value in values:
        value = value.strip()
        if value == "*":
            return ["*"]
        value = value.upper()
        if not MACHINE_RE.match(value):
            sys.exit("بصمة جهاز غير صالحة: %s (الصيغة الصحيحة: MACH-XXXX-XXXX-XXXX)" % value)
        if value not in out:
            out.append(value)
    return out


def b64u(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()

def unb64u(s: str) -> bytes:
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))

def make(key_path, shop, devices, expires):
    raw = base64.b64decode(open(key_path).read().strip())
    key = Ed25519PrivateKey.from_private_bytes(raw)
    payload = {
        "v": 1,
        "shop": shop,
        "devices": devices,
        "exp": "" if expires == "never" else expires,
        "issued": time.strftime("%Y-%m-%d"),
    }
    payload_bytes = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    sig = key.sign(payload_bytes)
    return "MYK1.%s.%s" % (b64u(payload_bytes), b64u(sig))

def verify(code, pub_b64):
    parts = code.strip().split(".")
    assert len(parts) == 3 and parts[0] == "MYK1", "صيغة غير صحيحة"
    payload_bytes, sig = unb64u(parts[1]), unb64u(parts[2])
    pub = Ed25519PublicKey.from_public_bytes(base64.b64decode(pub_b64))
    try:
        pub.verify(sig, payload_bytes)
    except InvalidSignature:
        return None
    return json.loads(payload_bytes.decode("utf-8"))

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--key")
    ap.add_argument("--shop", default="")
    ap.add_argument("--device", "--machine", dest="devices", action="append", default=[], metavar="MACH-XXXX-XXXX-XXXX")
    ap.add_argument("--expires", default="never")
    ap.add_argument("--verify")
    ap.add_argument("--pub")
    a = ap.parse_args()
    if a.verify:
        if not a.pub:
            sys.exit("--verify يحتاج --pub")
        p = verify(a.verify, a.pub)
        print(json.dumps(p, ensure_ascii=False, indent=2) if p else "توقيع غير صالح")
    else:
        if not a.key or not a.devices:
            sys.exit("مطلوب --key و --device (مرة أو أكثر)")
        print(make(a.key, a.shop, normalise_machines(a.devices), a.expires))
