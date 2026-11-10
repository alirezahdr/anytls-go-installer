# AnyTLS-Go Server Installer and Control Panel

[English](#english) · [فارسی](#persian)

<a id="english"></a>

## English

Install the latest stable AnyTLS-Go release on Linux with systemd, manage its service from an interactive terminal panel, or configure a direct TCP forward on an Iran-side server with GOST.

## Quick install

Run this single line in an interactive Linux terminal:

~~~bash
installer=$(curl -fsSL https://raw.githubusercontent.com/alirezahdr/anytls-go-installer/main/install-anytls.sh) && sudo bash -c "$installer"
~~~

The installer offers three choices:

1. **Install or reconfigure AnyTLS-Go** — downloads the latest stable official release and asks for the server listen IP, port, and password.
2. **Set up direct forwarding with GOST** — configure an Iran-side entry point that forwards TCP to an AnyTLS server abroad. This does not install AnyTLS on the Iran server.
3. **Open the control panel** — manage the services already configured on this machine.

After installing the AnyTLS server, the panel opens automatically. Start it later with:

~~~bash
sudo anytls-panel
~~~

The TUI prompts and menus are in English.

## Iran-to-abroad direct forwarding

The data path is:

~~~text
AnyTLS client → Iran server IP:port → GOST TCP forward → foreign AnyTLS server IP:port
~~~

Choose **Set up direct Iran-to-abroad TCP forwarding with GOST**. The wizard asks for:

- The foreign AnyTLS server address (IP or DNS name).
- The AnyTLS TCP port.
- The listen IP on the Iran server.

The Iran entry port is set to the same number as the foreign AnyTLS port. In the client profile, replace only the server address with the **public IP of the Iran server**. Keep the existing port and AnyTLS password.

GOST relays the TCP stream to the configured foreign address and port; it does not need the AnyTLS password. The AnyTLS server must already be running abroad and reachable from the Iran server. Open the selected inbound TCP port in the Iran server firewall and provider firewall, and allow the Iran server to reach the foreign AnyTLS destination.

The wizard downloads the latest stable GOST release for Linux amd64 or arm64 from the official project and checks its SHA-256 digest before installing it. Forwarding runs as a systemd service, starts at boot, and restarts automatically after a failure. The service unit keeps the name anytls-tunnel for compatibility with the existing panel commands.

## Panel features

- Show status and start, stop, restart, enable at boot, or disable at boot for the AnyTLS server and forwarding service.
- Review or follow service logs.
- Change the AnyTLS server listen IP, port, and password.
- Set up or update the direct GOST TCP forward.
- View the non-secret forwarding address and port.
- Display the equivalent systemd commands.

## Service commands

These commands are also available from the TUI:

~~~bash
sudo systemctl status anytls
sudo systemctl start anytls
sudo systemctl stop anytls
sudo systemctl restart anytls
sudo systemctl enable anytls
sudo systemctl disable anytls
sudo journalctl -u anytls -f

sudo systemctl status anytls-tunnel
sudo systemctl start anytls-tunnel
sudo systemctl stop anytls-tunnel
sudo systemctl restart anytls-tunnel
sudo systemctl enable anytls-tunnel
sudo systemctl disable anytls-tunnel
sudo journalctl -u anytls-tunnel -f
~~~

Disabling a service prevents it from starting at boot but does not stop a service that is already running.

## Requirements and notes

- Linux with systemd and root or sudo access.
- curl, Python 3, and standard account utilities.
- GOST forwarding supports Linux amd64 and arm64.
- The forwarder listens on the IP selected in the wizard. Use **0.0.0.0** to accept connections on all IPv4 interfaces; restrict access through firewalls as needed.
- The listen port must be available on the Iran server.
- AnyTLS-Go describes itself as a reference implementation and warns that its sample configuration assumes there is no man-in-the-middle attack. Read the [upstream project documentation](https://github.com/anytls/anytls-go) before using it for sensitive traffic.

---

<a id="persian"></a>

## فارسی

آخرین نسخهٔ پایدار AnyTLS-Go را روی لینوکس دارای systemd نصب کنید، سرویس را از پنل تعاملی مدیریت کنید یا روی سرور ایران با GOST فوروارد مستقیم TCP به سرور AnyTLS خارج بسازید.

## نصب سریع

این یک خط را در ترمینال تعاملی لینوکس اجرا کنید:

~~~bash
installer=$(curl -fsSL https://raw.githubusercontent.com/alirezahdr/anytls-go-installer/main/install-anytls.sh) && sudo bash -c "$installer"
~~~

نصب‌کننده سه گزینه دارد:

1. **نصب یا تنظیم دوبارهٔ AnyTLS-Go** — آخرین نسخهٔ پایدار رسمی را می‌گیرد و IP شنود، پورت و رمز سرور را می‌پرسد.
2. **راه‌اندازی فوروارد مستقیم با GOST** — سرور ایران را به ورودی اتصال تبدیل می‌کند و TCP را به AnyTLS روی سرور خارج می‌فرستد. در این حالت AnyTLS روی سرور ایران نصب نمی‌شود.
3. **بازکردن پنل مدیریت** — سرویس‌های تنظیم‌شده را مدیریت می‌کند.

پس از نصب سرور AnyTLS، پنل خودکار باز می‌شود. برای اجرای دوباره:

~~~bash
sudo anytls-panel
~~~

منو و پرسش‌های TUI انگلیسی هستند.

## فوروارد مستقیم از ایران به خارج

مسیر داده به این شکل است:

~~~text
کلاینت AnyTLS → IP و پورت سرور ایران → فوروارد TCP با GOST → IP و پورت سرور AnyTLS خارج
~~~

گزینهٔ **Set up direct Iran-to-abroad TCP forwarding with GOST** را انتخاب کنید. راهنما این موارد را می‌پرسد:

- آدرس سرور AnyTLS خارج (IP یا نام دامنه).
- پورت TCP سرور AnyTLS.
- IP شنود روی سرور ایران.

پورت ورودی ایران با همان شمارهٔ پورت AnyTLS خارج تنظیم می‌شود. در پروفایل کلاینت فقط آدرس سرور را با **IP عمومی سرور ایران** جایگزین کنید؛ پورت و رمز AnyTLS را همان قبلی نگه دارید.

GOST جریان TCP را به آدرس و پورت سرور خارج منتقل می‌کند و به رمز AnyTLS نیاز ندارد. سرور AnyTLS باید از قبل روی سرور خارج فعال باشد و سرور ایران بتواند به آن دسترسی داشته باشد. پورت ورودی TCP را در فایروال سرور ایران و فایروال ارائه‌دهنده باز کنید و دسترسی خروجی سرور ایران به مقصد AnyTLS خارج را نیز مجاز کنید.

راهنما آخرین نسخهٔ پایدار رسمی GOST برای Linux amd64 یا arm64 را دانلود و پیش از نصب SHA-256 آن را بررسی می‌کند. فوروارد به‌صورت سرویس systemd اجرا می‌شود، پس از راه‌اندازی مجدد سرور خودکار بالا می‌آید و در صورت خطا دوباره اجرا می‌شود. برای سازگاری با فرمان‌های پنل، نام سرویس anytls-tunnel باقی مانده است.

## امکانات پنل

- نمایش وضعیت و اجرای start، stop، restart، enable هنگام بوت یا disable برای سرور AnyTLS و سرویس فوروارد.
- مشاهده یا دنبال‌کردن گزارش سرویس‌ها.
- تغییر IP شنود، پورت و رمز سرور AnyTLS.
- راه‌اندازی یا تنظیم دوبارهٔ فوروارد مستقیم TCP با GOST.
- نمایش آدرس و پورت فوروارد؛ رمز AnyTLS در این تنظیمات ذخیره نمی‌شود.
- نمایش دستورهای معادل systemd.

## دستورهای سرویس

این عملیات از داخل TUI هم در دسترس هستند:

~~~bash
sudo systemctl status anytls
sudo systemctl start anytls
sudo systemctl stop anytls
sudo systemctl restart anytls
sudo systemctl enable anytls
sudo systemctl disable anytls
sudo journalctl -u anytls -f

sudo systemctl status anytls-tunnel
sudo systemctl start anytls-tunnel
sudo systemctl stop anytls-tunnel
sudo systemctl restart anytls-tunnel
sudo systemctl enable anytls-tunnel
sudo systemctl disable anytls-tunnel
sudo journalctl -u anytls-tunnel -f
~~~

disable اجرای خودکار هنگام بوت را متوقف می‌کند، اما سرویسی را که اکنون فعال است متوقف نمی‌کند.

## پیش‌نیازها و نکته‌ها

- لینوکس دارای systemd و دسترسی root یا sudo.
- curl، Python 3 و ابزارهای استاندارد مدیریت حساب.
- فوروارد GOST از Linux amd64 و arm64 پشتیبانی می‌کند.
- فوروارد روی IP انتخاب‌شده در راهنما شنود می‌کند. برای پذیرش اتصال روی همهٔ رابط‌های IPv4 مقدار **0.0.0.0** را انتخاب کنید و دسترسی را با فایروال محدود کنید.
- پورت ورودی باید روی سرور ایران آزاد باشد.
- AnyTLS-Go خود را پیاده‌سازی مرجع معرفی می‌کند و هشدار می‌دهد تنظیم نمونه با فرض نبود حملهٔ MITM است. پیش از استفاده برای ترافیک حساس، [مستندات پروژهٔ اصلی](https://github.com/anytls/anytls-go) را بخوانید.
