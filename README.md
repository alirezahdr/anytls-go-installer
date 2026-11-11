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

## Multiple accounts and client profiles

The default server is upstream AnyTLS-Go and uses one shared password. Before migrating, **Export shared-password client QR and JSON** still creates client profiles for that password. To enable multiple passwords on the same port, open **AnyTLS server management → Manage accounts and client configs** and confirm the migration to the sing-box server backend. The current AnyTLS-Go password is retained as the first account. The panel can list, add, and revoke accounts, set each account's expiration, and export a QR code plus Android, iOS, and Windows sing-box JSON profiles. New passwords are shown once. Existing client exports are kept when an account is removed or expires.

Choose the Iran server IP when GOST forwarding is configured, or the foreign server IP for a direct connection. The JSON profiles enable `tls.insecure`, set ALPN to `h2` and `http/1.1`, use a device-specific uTLS fingerprint (`android`, `ios`, or `chrome` for Windows), and send DNS through the AnyTLS outbound. Import the Android JSON profile when NekoBox reports a direct DNS or “missing default interface” error; the QR contains only an AnyTLS URI and does not include DNS routing. The default SNI is `www.cloudflare.com`; replace it with your own server domain when available. SNI does not route traffic through Cloudflare or guarantee that a connection will pass filtering. `tls.insecure` disables certificate verification and can expose the connection to interception. uTLS fingerprint imitation does not guarantee that traffic will avoid detection.

Migration validates the generated sing-box configuration before changing the service, avoids automatic network-interface discovery for compatibility with OpenVZ/venet hosts, and restores the previous AnyTLS-Go service files if the new service fails to remain active. To return explicitly to AnyTLS-Go, run `sudo /usr/local/libexec/anytls-installer --restore-anytls-go`; the first active account password becomes the shared password. Per-account device-count and data-volume limits are not supported; use one account per device if you need to revoke devices separately.

## Panel features

- Show status and start, stop, restart, enable at boot, or disable at boot for the AnyTLS server and forwarding service.
- Review or follow service logs.
- Change the AnyTLS server listen IP and port; change the shared password while using AnyTLS-Go.
- Manage multiple accounts and expiration after enabling the sing-box backend.
- Export per-account QR codes and Android, iOS, and Windows sing-box JSON profiles.
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

## مدیریت کاربران و ساخت پروفایل کلاینت

سرور به‌صورت پیش‌فرض با AnyTLS-Go اصلی و یک رمز مشترک نصب می‌شود. پیش از مهاجرت، گزینهٔ **Export shared-password client QR and JSON** برای همین رمز فایل‌های کلاینت را می‌سازد. برای فعال‌کردن چند رمز روی یک پورت، مسیر **AnyTLS server management → Manage accounts and client configs** را باز کنید و مهاجرت به بک‌اند sing-box را تأیید کنید. رمز فعلی به‌عنوان حساب اول نگه داشته می‌شود. پنل امکان نمایش حساب‌ها، افزودن و حذف حساب، تعیین تاریخ انقضا، و ساخت QR و فایل JSON sing-box برای Android، iOS و Windows را می‌دهد. رمز حساب تازه فقط یک‌بار نمایش داده می‌شود. فایل‌های خروجی قبلی با حذف یا انقضای حساب پاک نمی‌شوند.

برای اتصال مستقیم IP سرور خارج را وارد کنید؛ اگر فوروارد GOST روی ایران دارید، IP عمومی ایران را وارد کنید. در JSON گزینهٔ `tls.insecure` فعال است، ALPN برابر `h2` و `http/1.1` است، uTLS fingerprint بر اساس دستگاه تنظیم می‌شود (`android`، `ios` یا `chrome` برای Windows) و درخواست DNS از مسیر AnyTLS عبور می‌کند. اگر NekoBox خطای DNS مستقیم یا `missing default interface` داد، فایل JSON اندروید را وارد کنید؛ QR فقط لینک AnyTLS را دارد و تنظیم مسیریابی DNS را شامل نمی‌شود. SNI پیش‌فرض `www.cloudflare.com` است؛ در صورت داشتن دامنهٔ خودتان آن را جایگزین کنید. SNI اتصال را از مسیر Cloudflare عبور نمی‌دهد و عبور از فیلترینگ را تضمین نمی‌کند. گزینهٔ `tls.insecure` بررسی گواهی را غیرفعال می‌کند و می‌تواند اتصال را در برابر رهگیری آسیب‌پذیر کند. تقلید uTLS نیز تضمینی برای شناسایی‌نشدن ترافیک نیست.

مهاجرت پیش از تغییر سرویس، کانفیگ sing-box را بررسی می‌کند و برای سازگاری با برخی سرورهای OpenVZ/venet، تشخیص خودکار رابط شبکه را خاموش می‌گذارد. اگر سرویس جدید فعال نماند، فایل‌ها و سرویس قبلی AnyTLS-Go برگردانده می‌شوند. برای برگشت آگاهانه به AnyTLS-Go اجرا کنید: `sudo /usr/local/libexec/anytls-installer --restore-anytls-go`. رمز اولین حساب فعال به رمز مشترک تبدیل می‌شود. محدودیت تعداد دستگاه یا حجم جداگانه برای هر حساب پشتیبانی نمی‌شود؛ برای لغو دسترسی دستگاه‌ها، یک حساب جدا برای هر دستگاه بسازید.

راهنما آخرین نسخهٔ پایدار رسمی GOST برای Linux amd64 یا arm64 را دانلود و پیش از نصب SHA-256 آن را بررسی می‌کند. فوروارد به‌صورت سرویس systemd اجرا می‌شود، پس از راه‌اندازی مجدد سرور خودکار بالا می‌آید و در صورت خطا دوباره اجرا می‌شود. برای سازگاری با فرمان‌های پنل، نام سرویس anytls-tunnel باقی مانده است.

## امکانات پنل

- نمایش وضعیت و اجرای start، stop، restart، enable هنگام بوت یا disable برای سرور AnyTLS و سرویس فوروارد.
- مشاهده یا دنبال‌کردن گزارش سرویس‌ها.
- تغییر IP شنود و پورت؛ تغییر رمز مشترک و خروجی QR/JSON رمز مشترک تا زمانی که بک‌اند AnyTLS-Go فعال است.
- مدیریت حساب‌ها و تاریخ انقضا پس از فعال‌کردن بک‌اند sing-box.
- ساخت QR و فایل JSON sing-box برای هر حساب و پلتفرم Android، iOS و Windows.
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
- نصب‌کننده هنگام نصب AnyTLS یا بازکردن پنل، qrencode را خودکار نصب می‌کند تا خروجی QR آماده باشد. package managerهای پشتیبانی‌شده apt، dnf، yum، zypper و apk هستند. OpenSSL برای ساخت گواهی TLS هنگام مهاجرت به حالت چندکاربره لازم است.
- فوروارد GOST از Linux amd64 و arm64 پشتیبانی می‌کند.
- فوروارد روی IP انتخاب‌شده در راهنما شنود می‌کند. برای پذیرش اتصال روی همهٔ رابط‌های IPv4 مقدار **0.0.0.0** را انتخاب کنید و دسترسی را با فایروال محدود کنید.
- پورت ورودی باید روی سرور ایران آزاد باشد.
- AnyTLS-Go خود را پیاده‌سازی مرجع معرفی می‌کند و هشدار می‌دهد تنظیم نمونه با فرض نبود حملهٔ MITM است. پیش از استفاده برای ترافیک حساس، [مستندات پروژهٔ اصلی](https://github.com/anytls/anytls-go) را بخوانید.
