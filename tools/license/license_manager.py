#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""أداة إصدار تراخيص MyKash — واجهة رسومية بلا سطر أوامر.

التشغيل:
    pythonw tools/license/license_manager.py

تتطلب: pip install cryptography
"""

import base64
import json
import os
import re
import sys
import time
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

try:
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
except ImportError:
    import tkinter.messagebox as mb

    mb.showerror(
        "مكتبة ناقصة",
        "ثبّت المكتبة أولاً:\n\npip install cryptography",
    )
    sys.exit(1)

MACHINE_RE = re.compile(r"^MACH-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}$")
HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_KEY = os.path.join(HERE, "license_private.key")


def b64u(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def load_private_key(path: str) -> Ed25519PrivateKey:
    raw = base64.b64decode(open(path, "r", encoding="utf-8").read().strip())
    return Ed25519PrivateKey.from_private_bytes(raw)


def generate_private_key(path: str) -> str:
    key = Ed25519PrivateKey.generate()
    raw = key.private_bytes(
        serialization.Encoding.Raw,
        serialization.PrivateFormat.Raw,
        serialization.NoEncryption(),
    )
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(base64.b64encode(raw).decode())
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass
    return public_key_b64(key)


def public_key_b64(key: Ed25519PrivateKey) -> str:
    pub = key.public_key().public_bytes(
        serialization.Encoding.Raw, serialization.PublicFormat.Raw
    )
    return base64.b64encode(pub).decode()


def issue_token(key: Ed25519PrivateKey, shop: str, machines, expires: str) -> str:
    payload = {
        "v": 1,
        "shop": shop.strip(),
        "devices": machines,
        "exp": "" if expires.strip().lower() in ("", "never", "دائم") else expires.strip(),
        "issued": time.strftime("%Y-%m-%d"),
    }
    data = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    return "MYK1.%s.%s" % (b64u(data), b64u(key.sign(data)))


def normalise_machines(text: str):
    """Returns (machines, invalid) after splitting on whitespace/commas."""
    machines, invalid = [], []
    for chunk in re.split(r"[\s,;]+", text or ""):
        value = chunk.strip().upper()
        if not value:
            continue
        if value == "*":
            return ["*"], []
        if not MACHINE_RE.match(value):
            invalid.append(value)
            continue
        if value not in machines:
            machines.append(value)
    return machines, invalid


class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("MyKash — إدارة التراخيص")
        self.geometry("720x640")
        self.minsize(680, 600)
        self.key_path = tk.StringVar(value=DEFAULT_KEY)
        self.shop = tk.StringVar()
        self.expires = tk.StringVar(value="never")
        self.status = tk.StringVar(value="جاهز")
        self._build()

    # ---------- layout ----------
    def _build(self):
        pad = {"padx": 12, "pady": 6}
        outer = ttk.Frame(self)
        outer.pack(fill="both", expand=True, padx=10, pady=10)

        key_box = ttk.LabelFrame(outer, text="1) مفتاح التوقيع")
        key_box.pack(fill="x", **pad)

        row = ttk.Frame(key_box)
        row.pack(fill="x", padx=8, pady=6)
        ttk.Entry(row, textvariable=self.key_path).pack(side="left", fill="x", expand=True)
        ttk.Button(row, text="اختيار...", command=self._pick_key).pack(side="left", padx=4)
        ttk.Button(row, text="إنشاء مفتاح جديد", command=self._create_key).pack(side="left")

        self.pub_label = ttk.Entry(key_box)
        self.pub_label.pack(fill="x", padx=8, pady=(0, 6))
        self.pub_label.insert(0, "المفتاح العام سيظهر هنا بعد اختيار المفتاح")
        self.pub_label.configure(state="readonly")
        ttk.Button(key_box, text="نسخ المفتاح العام", command=self._copy_pub).pack(
            anchor="e", padx=8, pady=(0, 8)
        )
        self._refresh_pub()

        issue_box = ttk.LabelFrame(outer, text="2) إصدار ترخيص")
        issue_box.pack(fill="both", expand=True, **pad)

        form = ttk.Frame(issue_box)
        form.pack(fill="x", padx=8, pady=6)
        ttk.Label(form, text="اسم المحل").grid(row=0, column=0, sticky="w")
        ttk.Entry(form, textvariable=self.shop, width=42).grid(
            row=0, column=1, columnspan=2, sticky="we", padx=6
        )
        ttk.Label(form, text="تاريخ الانتهاء").grid(row=1, column=0, sticky="w", pady=6)
        ttk.Entry(form, textvariable=self.expires, width=18).grid(
            row=1, column=1, sticky="w", padx=6
        )
        ttk.Label(form, text="(YYYY-MM-DD أو never)").grid(row=1, column=2, sticky="w")
        form.columnconfigure(1, weight=1)

        ttk.Label(
            issue_box, text="بصمات الأجهزة (واحدة في كل سطر)"
        ).pack(anchor="w", padx=8)
        self.machines_text = tk.Text(issue_box, height=7, wrap="word")
        self.machines_text.pack(fill="both", expand=True, padx=8, pady=(2, 6))

        actions = ttk.Frame(issue_box)
        actions.pack(fill="x", padx=8, pady=(0, 6))
        ttk.Button(actions, text="لصق من الحافظة", command=self._paste).pack(side="left")
        ttk.Button(actions, text="إصدار", command=self._issue).pack(side="left", padx=6)
        ttk.Button(actions, text="نسخ الرمز", command=self._copy_token).pack(side="left")
        ttk.Button(actions, text="حفظ ملف ترخيص...", command=self._save_file).pack(
            side="left", padx=6
        )

        self.token_text = tk.Text(outer, height=5, wrap="char")
        self.token_text.pack(fill="both", expand=False, padx=12, pady=(0, 6))

        ttk.Label(outer, textvariable=self.status, foreground="#0B6B57").pack(
            anchor="w", padx=12, pady=(0, 8)
        )

    # ---------- key handling ----------
    def _pick_key(self):
        path = filedialog.askopenfilename(
            title="اختر ملف المفتاح الخاص",
            filetypes=[("Key files", "*.key"), ("All files", "*.*")],
        )
        if path:
            self.key_path.set(path)
            self._refresh_pub()

    def _create_key(self):
        path = filedialog.asksaveasfilename(
            title="حفظ المفتاح الخاص",
            defaultextension=".key",
            initialfile="license_private.key",
            filetypes=[("Key files", "*.key")],
        )
        if not path:
            return
        if os.path.exists(path) and not messagebox.askyesno(
            "تحذير",
            "الملف موجود بالفعل. استبداله يُبطل كل التراخيص السابقة.\n\nهل أنت متأكد؟",
        ):
            return
        pub = generate_private_key(path)
        self.key_path.set(path)
        self._refresh_pub()
        messagebox.showinfo(
            "تم إنشاء المفتاح",
            "احتفظ بهذا الملف في مكان آمن ولا ترسله لأي عميل.\n\n"
            "انسخ المفتاح العام إلى license_key.dart:\n\n"
            "const String kLicensePublicKeyB64 = '%s';" % pub,
        )

    def _refresh_pub(self):
        path = self.key_path.get().strip()
        text = "لا يوجد مفتاح صالح"
        if os.path.exists(path):
            try:
                text = public_key_b64(load_private_key(path))
            except Exception as error:  # noqa: BLE001
                text = "تعذر قراءة المفتاح: %s" % error
        self.pub_label.configure(state="normal")
        self.pub_label.delete(0, "end")
        self.pub_label.insert(0, text)
        self.pub_label.configure(state="readonly")

    def _copy_pub(self):
        self.clipboard_clear()
        self.clipboard_append(self.pub_label.get())
        self.status.set("تم نسخ المفتاح العام")

    # ---------- issuing ----------
    def _paste(self):
        try:
            data = self.clipboard_get()
        except tk.TclError:
            return
        current = self.machines_text.get("1.0", "end").strip()
        self.machines_text.delete("1.0", "end")
        self.machines_text.insert("1.0", (current + "\n" + data).strip())

    def _build_token(self):
        path = self.key_path.get().strip()
        if not os.path.exists(path):
            messagebox.showerror("خطأ", "اختر ملف المفتاح الخاص أولاً.")
            return None
        machines, invalid = normalise_machines(self.machines_text.get("1.0", "end"))
        if invalid:
            messagebox.showerror(
                "بصمة غير صالحة",
                "هذه القيم ليست بصمات أجهزة صحيحة:\n\n%s\n\n"
                "الصيغة الصحيحة: MACH-XXXX-XXXX-XXXX" % "\n".join(invalid),
            )
            return None
        if not machines:
            messagebox.showerror("خطأ", "أضف بصمة جهاز واحدة على الأقل.")
            return None
        if machines == ["*"] and not messagebox.askyesno(
            "تأكيد",
            "العلامة * تجعل الترخيص يعمل على أي جهاز وتلغي الحماية.\n\nمتابعة؟",
        ):
            return None
        try:
            key = load_private_key(path)
            return issue_token(key, self.shop.get(), machines, self.expires.get())
        except Exception as error:  # noqa: BLE001
            messagebox.showerror("خطأ", "تعذر إصدار الترخيص:\n%s" % error)
            return None

    def _issue(self):
        token = self._build_token()
        if not token:
            return
        self.token_text.delete("1.0", "end")
        self.token_text.insert("1.0", token)
        self.clipboard_clear()
        self.clipboard_append(token)
        self.status.set("تم الإصدار ونسخه إلى الحافظة")

    def _copy_token(self):
        token = self.token_text.get("1.0", "end").strip()
        if not token:
            self._issue()
            return
        self.clipboard_clear()
        self.clipboard_append(token)
        self.status.set("تم نسخ الرمز")

    def _save_file(self):
        token = self.token_text.get("1.0", "end").strip() or self._build_token()
        if not token:
            return
        self.token_text.delete("1.0", "end")
        self.token_text.insert("1.0", token)
        path = filedialog.asksaveasfilename(
            title="حفظ ملف الترخيص",
            defaultextension=".myklic",
            initialfile="mykash-license.myklic",
            filetypes=[("MyKash licence", "*.myklic")],
        )
        if not path:
            return
        with open(path, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(token)
        self.status.set("تم حفظ الملف: %s" % os.path.basename(path))


if __name__ == "__main__":
    App().mainloop()