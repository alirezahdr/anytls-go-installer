# AnyTLS-Go Server Installer and Control Panel

[English](#english) · [فارسی](#persian)

<a id="english"></a>

## English

Install the interactive control panel on Linux with systemd. From the panel, install or manage AnyTLS, configure a direct TCP forward on an Iran-side server with GOST, or view the command reference.

## Quick install

Run this single line in an interactive Linux terminal:

~~~bash
installer=$(curl -fsSL https://raw.githubusercontent.com/alirezahdr/anytls-go-installer/main/install-anytls.sh) && sudo bash -c "$installer"
~~~

The control panel opens directly after quick installation. Choose **AnyTLS server management** to install or configure the server when needed, or **Direct Iran-to-abroad TCP forwarding management (GOST)** to configure the Iran-side entry point. Both workflows are available from this same panel. Start it later with:

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

## Single-password client profiles

This installer runs the upstream AnyTLS-Go server with one shared password. In **AnyTLS server management → Export client QR and JSON profiles**, choose the address clients should use: the Iran server IP when GOST forwarding is configured, or the foreign server IP for a direct connection. The panel creates Android, iOS, and Windows sing-box JSON profiles and a QR image under `/root/anytls-clients`; it also prints the selected JSON in the terminal for copying. Existing exported files are kept.

The JSON profiles enable `tls.insecure`, set ALPN to `h2` and `http/1.1`, and use a device-specific uTLS fingerprint (`android`, `ios`, or `chrome` for Windows). The QR contains an AnyTLS URI with the server address, shared password, SNI, and insecure setting; import the JSON when you need the ALPN and uTLS options. The default SNI is `www.cloudflare.com`; replace it with your own server domain when available. SNI does not route traffic through Cloudflare or guarantee that a connection will pass filtering. `tls.insecure` disables certificate verification and can expose the connection to interception. uTLS fingerprint imitation does not guarantee that traffic will avoid detection.

## Panel features

- Show status and start, stop, restart, enable at boot, or disable at boot for the AnyTLS server and forwarding service.
- Review or follow service logs.
- Change the AnyTLS server listen IP, port, and shared password.
- Export one shared-password QR link and Android, iOS, and Windows sing-box JSON profiles.
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

### Troubleshooting startup

If `journalctl -u anytls` shows `create netlink socket: address family not supported by protocol`, the systemd address-family allow-list is blocking a socket AnyTLS needs. The quick installer adds a persistent drop-in for existing AnyTLS and GOST services. Restart the affected service after the installer finishes. You can apply the AnyTLS fix manually with:

~~~bash
sudo install -d -m 0755 /etc/systemd/system/anytls.service.d
sudo tee /etc/systemd/system/anytls.service.d/zz-netlink.conf >/dev/null <<'UNIT'
[Service]
RestrictAddressFamilies=
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK
UNIT
sudo systemctl daemon-reload
sudo systemctl reset-failed anytls
sudo systemctl restart anytls
~~~

## Requirements and notes

- Linux with systemd and root or sudo access.
- curl, Python 3, and standard system utilities.
- The installer installs qrencode automatically when installing or opening the AnyTLS panel, so QR export is ready to use. Supported package managers are apt, dnf, yum, zypper, and apk.
- GOST forwarding supports Linux amd64 and arm64.
- The server installer supports Linux amd64 and arm64.
- The forwarder listens on the IP selected in the wizard. Use **0.0.0.0** to accept connections on all IPv4 interfaces; restrict access through firewalls as needed.
- The listen port must be available on the Iran server.
- AnyTLS-Go describes itself as a reference implementation and warns that its sample configuration assumes there is no man-in-the-middle attack. Read the [upstream project documentation](https://github.com/anytls/anytls-go) before using it for sensitive traffic.

---

<a id="persian"></a>

## فارسی

پنل تعاملی را روی لینوکس دارای systemd نصب کنید. از داخل پنل می‌توانید AnyTLS را نصب یا مدیریت کنید، روی سرور ایران فوروارد مستقیم TCP با GOST بسازید یا راهنمای فرمان‌ها را ببینید.

## نصب سریع

این یک خط را در ترمینال تعاملی لینوکس اجرا کنید:

~~~bash
installer=$(curl -fsSL https://raw.githubusercontent.com/alirezahdr/anytls-go-installer/main/install-anytls.sh) && sudo bash -c "$installer"
~~~

پس از نصب سریع، پنل اصلی مستقیم باز می‌شود. برای نصب یا تنظیم سرور، **AnyTLS server management** را انتخاب کنید؛ برای ساخت ورودی ایران، **Direct Iran-to-abroad TCP forwarding management (GOST)** را بزنید. هر دو کار از همین پنل انجام می‌شوند. برای اجرای دوبارهٔ پنل:

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

## ساخت QR و فایل‌های کلاینت

این نصب‌کننده سرور اصلی AnyTLS-Go را با یک رمز مشترک اجرا می‌کند. از مسیر **AnyTLS server management → Export client QR and JSON profiles**، آدرسی را وارد کنید که کلاینت باید استفاده کند: IP سرور ایران، اگر فوروارد GOST فعال است؛ یا IP سرور خارج برای اتصال مستقیم. پنل فایل‌های sing-box برای Android، iOS و Windows و تصویر QR را در مسیر `/root/anytls-clients` می‌سازد و امکان نمایش JSON در ترمینال برای کپی را می‌دهد. فایل‌های خروجی قبلی پاک نمی‌شوند.

در JSON گزینهٔ `tls.insecure` فعال است، ALPN برابر `h2` و `http/1.1` است و uTLS fingerprint بر اساس دستگاه تنظیم می‌شود (`android`، `ios` یا `chrome` برای Windows). QR شامل لینک AnyTLS با آدرس سرور، رمز مشترک، SNI و گزینهٔ insecure است؛ برای استفاده از ALPN و uTLS، فایل JSON را وارد کنید. SNI پیش‌فرض `www.cloudflare.com` است؛ در صورت داشتن دامنهٔ خودتان آن را جایگزین کنید. SNI اتصال را از مسیر Cloudflare عبور نمی‌دهد و عبور از فیلترینگ را تضمین نمی‌کند. گزینهٔ `tls.insecure` بررسی گواهی را غیرفعال می‌کند و می‌تواند اتصال را در برابر رهگیری آسیب‌پذیر کند. تقلید uTLS نیز تضمینی برای شناسایی‌نشدن ترافیک نیست.

راهنما آخرین نسخهٔ پایدار رسمی GOST برای Linux amd64 یا arm64 را دانلود و پیش از نصب SHA-256 آن را بررسی می‌کند. فوروارد به‌صورت سرویس systemd اجرا می‌شود، پس از راه‌اندازی مجدد سرور خودکار بالا می‌آید و در صورت خطا دوباره اجرا می‌شود. برای سازگاری با فرمان‌های پنل، نام سرویس anytls-tunnel باقی مانده است.

## امکانات پنل

- نمایش وضعیت و اجرای start، stop، restart، enable هنگام بوت یا disable برای سرور AnyTLS و سرویس فوروارد.
- مشاهده یا دنبال‌کردن گزارش سرویس‌ها.
- تغییر IP شنود، پورت و رمز مشترک سرور AnyTLS-Go.
- ساخت QR و فایل JSON کلاینت sing-box برای Android، iOS و Windows.
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

### عیب‌یابی اجرا

اگر در `journalctl -u anytls` پیام `create netlink socket: address family not supported by protocol` دیدید، فهرست خانواده‌های آدرس systemd جلوی سوکتی را گرفته که AnyTLS به آن نیاز دارد. اجرای دوبارهٔ نصب‌کننده برای سرویس‌های موجود AnyTLS و GOST تنظیم پایدار اضافه می‌کند. پس از پایان، سرویس مربوط را restart کنید. اصلاح دستی AnyTLS:

~~~bash
sudo install -d -m 0755 /etc/systemd/system/anytls.service.d
sudo tee /etc/systemd/system/anytls.service.d/zz-netlink.conf >/dev/null <<'UNIT'
[Service]
RestrictAddressFamilies=
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK
UNIT
sudo systemctl daemon-reload
sudo systemctl reset-failed anytls
sudo systemctl restart anytls
~~~

## پیش‌نیازها و نکته‌ها

- لینوکس دارای systemd و دسترسی root یا sudo.
- curl، Python 3 و ابزارهای استاندارد مدیریت حساب.
- نصب‌کننده هنگام نصب AnyTLS یا بازکردن پنل، qrencode را خودکار نصب می‌کند تا خروجی QR آماده باشد. package managerهای پشتیبانی‌شده apt، dnf، yum، zypper و apk هستند. برای مهاجرت به حالت چندکاربره و ساخت پروفایل pin‌شده OpenSSL لازم است.
- فوروارد GOST از Linux amd64 و arm64 پشتیبانی می‌کند.
- فوروارد روی IP انتخاب‌شده در راهنما شنود می‌کند. برای پذیرش اتصال روی همهٔ رابط‌های IPv4 مقدار **0.0.0.0** را انتخاب کنید و دسترسی را با فایروال محدود کنید.
- پورت ورودی باید روی سرور ایران آزاد باشد.
- AnyTLS-Go خود را پیاده‌سازی مرجع معرفی می‌کند و هشدار می‌دهد تنظیم نمونه با فرض نبود حملهٔ MITM است. پیش از استفاده برای ترافیک حساس، [مستندات پروژهٔ اصلی](https://github.com/anytls/anytls-go) را بخوانید.
