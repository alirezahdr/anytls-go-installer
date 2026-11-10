# AnyTLS-Go Server Installer

An interactive installer for the [AnyTLS-Go](https://github.com/anytls/anytls-go) server on Linux with systemd.

نصب‌کنندهٔ تعاملی سرور [AnyTLS-Go](https://github.com/anytls/anytls-go) برای لینوکس و systemd.

## Quick install | نصب سریع

Run the command below in an interactive SSH session. It downloads this installer to a temporary file, runs it, and removes the temporary file when it exits.

فرمان زیر را در یک نشست تعاملی SSH اجرا کنید. نصب‌کننده موقتاً دانلود و اجرا می‌شود و پس از پایان کار فایل موقت را پاک می‌کند.

```bash
tmp_script="$(mktemp)" || exit 1
trap 'rm -f "$tmp_script"' EXIT
curl -fsSL "https://raw.githubusercontent.com/alirezahdr/anytls-go-installer/main/install-anytls.sh" -o "$tmp_script" && sudo bash "$tmp_script"
```

## What the installer does | کار نصب‌کننده

- Downloads the latest stable official AnyTLS-Go release from GitHub when run.
- Prompts for the server listen IP, port, and a password of at least 16 characters. Password input is hidden and must be confirmed.
- Installs the server as a systemd service, enables it at boot, and starts it.
- Stores the service configuration in `/etc/anytls/anytls.env`, readable only by root.

- هنگام اجرا، آخرین نسخهٔ پایدار رسمی AnyTLS-Go را از GitHub دریافت می‌کند.
- IP شنود سرور، پورت و رمز حداقل ۱۶ نویسه‌ای را می‌پرسد. هنگام واردکردن رمز چیزی نمایش داده نمی‌شود و رمز باید تکرار شود.
- سرور را به‌صورت سرویس systemd نصب و فعال می‌کند تا با روشن‌شدن سیستم خودکار اجرا شود.
- تنظیمات سرویس را در `/etc/anytls/anytls.env` ذخیره می‌کند؛ این فایل فقط برای root قابل‌خواندن است.

### Listen IP and firewall | IP شنود و فایروال

Use `0.0.0.0` to listen on all IPv4 interfaces. The listen IP is the local address the server binds to. Allow the selected port for TCP in both the server firewall and your hosting provider's firewall.

برای شنود روی همهٔ رابط‌های IPv4، مقدار `0.0.0.0` را نگه دارید. IP شنود، نشانی محلی‌ای است که سرویس روی آن گوش می‌دهد. پورت انتخابی را برای TCP در فایروال سرور و پنل ارائه‌دهندهٔ سرور باز کنید.

## Manage the service | مدیریت سرویس

```bash
sudo systemctl status anytls
sudo systemctl start anytls
sudo systemctl stop anytls
sudo systemctl restart anytls
sudo systemctl enable anytls
sudo systemctl disable anytls
sudo journalctl -u anytls -f
```

`enable` turns on automatic startup at boot; `disable` turns it off. Use `journalctl` to follow live service logs.

`enable` اجرای خودکار هنگام راه‌اندازی سیستم را فعال می‌کند؛ `disable` آن را غیرفعال می‌کند. برای مشاهدهٔ گزارش‌های زنده از `journalctl` استفاده کنید.

## Requirements and reconfiguration | پیش‌نیازها و تنظیم دوباره

- Linux with systemd and root or `sudo` access.
- `bash`, `curl`, `python3`, `base64`, and standard Linux account utilities such as `useradd` and `getent`.
- Official release binaries are provided for `amd64` and `arm64`.

- لینوکس با systemd و دسترسی root یا `sudo` لازم است.
- وجود `bash`، `curl`، `python3`، `base64` و ابزارهای متداول مدیریت حساب مثل `useradd` و `getent` لازم است.
- فایل‌های اجرایی رسمی برای معماری‌های `amd64` و `arm64` ارائه شده‌اند.

If you run the installer again, it asks you to type `yes` before replacing an existing AnyTLS installation's IP, port, and password settings.

اگر نصب‌کننده را دوباره اجرا کنید، پیش از جایگزین‌کردن IP، پورت و رمز نصب قبلی، از شما می‌خواهد `yes` را وارد کنید.

## Security note | نکتهٔ امنیتی

AnyTLS-Go describes itself as a reference implementation, and its upstream documentation warns that the sample configuration assumes there is no man-in-the-middle attack. Review the [upstream security notes](https://github.com/anytls/anytls-go) before using it for sensitive traffic.

AnyTLS-Go یک پیاده‌سازی مرجع است و مستندات پروژه هشدار می‌دهد پیکربندی نمونه با فرض نبود حملهٔ MITM ارائه شده است. پیش از استفاده برای ترافیک حساس، [ملاحظات امنیتی پروژه](https://github.com/anytls/anytls-go) را بررسی کنید.
