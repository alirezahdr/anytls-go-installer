# AnyTLS-Go server installer

نصب‌کنندهٔ تعاملی سرور [AnyTLS-Go](https://github.com/anytls/anytls-go) برای Linux با systemd.

## نصب

فایل `install-anytls.sh` را روی سرور کپی کنید و در یک نشست تعاملی SSH اجرا کنید:

```bash
sudo bash install-anytls.sh
```

نصب‌کننده آخرین Release پایدار رسمی را از GitHub دریافت می‌کند، IP شنود و پورت را می‌پرسد، رمز حداقل ۱۶ نویسه‌ای را مخفیانه دریافت می‌کند و سرویس `anytls` را نصب و فعال می‌کند. برای شنود روی همهٔ رابط‌های IPv4، IP پیش‌فرض `0.0.0.0` را نگه دارید. پورت انتخابی را در فایروال سرور و پنل ارائه‌دهنده برای TCP باز کنید.

## مدیریت سرویس

```bash
sudo systemctl status anytls
sudo systemctl start anytls
sudo systemctl stop anytls
sudo systemctl restart anytls
sudo systemctl enable anytls
sudo systemctl disable anytls
sudo journalctl -u anytls -f
```

سرویس پس از نصب برای اجرای خودکار هنگام راه‌اندازی سیستم فعال می‌شود. فایل تنظیمات رمز در `/etc/anytls/anytls.env` با مجوز root-only ذخیره می‌شود.

## پیش‌نیازها و محدودیت‌ها

- توزیع Linux با systemd و دسترسی root
- `curl` و `python3`
- معماری `amd64` یا `arm64`

این نصب‌کننده سرور مرجع AnyTLS-Go را نصب می‌کند؛ مستندات upstream هشدار می‌دهد پیکربندی نمونه با فرض نبود حملهٔ MITM است. پیش از استفادهٔ حساس، ملاحظات امنیتی پروژه را بررسی کنید.
