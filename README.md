# AnyTLS-Go Server Installer and Control Panel

[English](#english) · [فارسی](#persian)

<a id="english"></a>

## English

Install the interactive control panel on Linux with systemd. From the panel, install or manage AnyTLS, configure direct or reverse GOST forwarding between Iran and a foreign server, or view the command reference.

## Quick install

Run this single line in an interactive Linux terminal:

~~~bash
installer=$(curl -fsSL https://raw.githubusercontent.com/alirezahdr/anytls-go-installer/main/install-anytls.sh) && sudo bash -c "$installer"
~~~

The control panel opens directly after quick installation. Choose **AnyTLS server management** to install or configure the server, or **GOST forwarding management** to configure direct forwarding or a reverse tunnel. Start it later with:

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

## Iran-to-abroad reverse GOST tunnel

Use this mode when the foreign AnyTLS server can initiate a connection to Iran, while direct Iran-to-abroad forwarding is unavailable. GOST's Relay BIND function lets the foreign agent create the AnyTLS entry port on the Iran server. The panel uses the Relay protocol over TLS and a generated username/password. See the [GOST Relay documentation](https://gost.run/en/tutorials/protocols/relay/) for the protocol's remote port forwarding mode.

~~~text
AnyTLS client → Iran server IP:entry port → TLS Relay on Iran → outbound GOST agent abroad → 127.0.0.1:AnyTLS port
~~~

Configure the two roles separately:

1. On the Iran server, open **GOST forwarding management → Set up or update reverse GOST tunnel → Configure Iran relay server**. Save the generated relay username and password. Allow the relay control TCP port (default `8444`) from the foreign server's public IP in the Iran and provider firewalls.
2. On the foreign server that runs AnyTLS, open **GOST forwarding management → Set up or update reverse GOST tunnel → Configure foreign AnyTLS server agent**. Enter the Iran relay address, the control port and credentials, the Iran client entry port, and the local AnyTLS port. The entry and AnyTLS ports default to `8443`.
3. Allow the Iran entry TCP port from client networks in the Iran and provider firewalls. In the AnyTLS client profile, use the Iran server public IP and entry port; keep the AnyTLS password unchanged.

The foreign agent initiates the connection to Iran, so the Iran firewall must allow its control port. Restrict that port to the foreign server IP when possible. The relay credentials and GOST configuration are stored in a restricted file. TLS encrypts the relay data, but the agent does not verify GOST's automatically generated certificate; source-IP firewall restrictions are recommended. Setting up either GOST mode replaces the `anytls-tunnel` configuration on that host, so configure the Iran relay and foreign agent on their respective servers.

## Single-user server and client profiles

The server runs the upstream AnyTLS-Go implementation with one shared password. A fresh installation generates a random 32-character password and prints it once so you can save it; the password is stored in the root-only server settings. Reconfiguring the listen IP or port also generates and saves a new random password, then shows it once. This invalidates existing client profiles, so export fresh QR/JSON profiles from option 3. The panel exports a QR/link for NekoBox and JSON profiles for Android, iOS, and Windows sing-box clients. The profile name is `AnyTLS-Go` in the QR link and JSON outbound tag; each JSON file is named `AnyTLS-Go.json` inside its platform directory.

Choose the Iran server IP when GOST forwarding is configured, or the foreign server IP for a direct connection. For NekoBox, import the AnyTLS QR/link. The JSON profiles are full sing-box configurations: they enable `tls.insecure`, set ALPN to `h2` and `http/1.1`, use a device-specific uTLS fingerprint (`android`, `ios`, or `chrome` for Windows), and send DNS through the AnyTLS outbound. NekoBox imports sing-box outbound nodes without their routing rules, and its URL test uses direct DNS; therefore, its `cp.cloudflare.com` / “missing default interface” test error may remain. A failed URL test alone does not prove the AnyTLS connection failed; confirm by opening a website through the connected proxy. The default SNI is `www.cloudflare.com`; replace it with your own server domain when available. SNI does not route traffic through Cloudflare or guarantee that a connection will pass filtering. `tls.insecure` disables certificate verification and can expose the connection to interception. uTLS fingerprint imitation does not guarantee that traffic will avoid detection.

If a server still uses the legacy sing-box multi-user backend, choose **AnyTLS server management → Restore AnyTLS-Go single-user mode**. The first active account password becomes the shared AnyTLS-Go password. Existing sing-box settings and client exports are saved in a backup directory.

## Panel features

- Show status and start, stop, restart, enable at boot, or disable at boot for the AnyTLS server and forwarding service.
- Review or follow service logs.
- Change the AnyTLS server listen IP and port while generating a new shared password; restore the previous settings if the service fails to start.
- Restore legacy sing-box installations to the AnyTLS-Go single-user backend.
- Export an AnyTLS-Go QR code and Android, iOS, and Windows sing-box JSON profiles.
- Set up or update direct GOST TCP forwarding or the two roles of a reverse GOST tunnel.
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
- Direct and reverse GOST forwarding support Linux amd64 and arm64. Reverse mode requires the foreign server to reach the Iran relay control port.
- The server installer supports Linux amd64 and arm64.
- Direct forwarding listens on the IP selected in its wizard. Use **0.0.0.0** to accept connections on all IPv4 interfaces; restrict access through firewalls as needed.
- The listen port must be available on the Iran server.
- AnyTLS-Go describes itself as a reference implementation and warns that its sample configuration assumes there is no man-in-the-middle attack. Read the [upstream project documentation](https://github.com/anytls/anytls-go) before using it for sensitive traffic.

---

<a id="persian"></a>

## فارسی

پنل تعاملی را روی لینوکس دارای systemd نصب کنید. از داخل پنل می‌توانید AnyTLS را نصب یا مدیریت کنید، فوروارد مستقیم یا معکوس GOST بین ایران و سرور خارج بسازید یا راهنمای فرمان‌ها را ببینید.

## نصب سریع

این یک خط را در ترمینال تعاملی لینوکس اجرا کنید:

~~~bash
installer=$(curl -fsSL https://raw.githubusercontent.com/alirezahdr/anytls-go-installer/main/install-anytls.sh) && sudo bash -c "$installer"
~~~

پس از نصب سریع، پنل اصلی مستقیم باز می‌شود. برای نصب یا تنظیم سرور، **AnyTLS server management** و برای تنظیم فوروارد مستقیم یا معکوس، **GOST forwarding management** را انتخاب کنید. برای اجرای دوبارهٔ پنل:

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

## تونل معکوس GOST از خارج به ایران

این حالت را وقتی انتخاب کنید که سرور خارج بتواند به ایران اتصال خروجی بزند اما فوروارد مستقیم ایران به خارج برقرار نمی‌شود. قابلیت Relay BIND در GOST به Agent روی سرور خارج اجازه می‌دهد پورت ورودی AnyTLS را روی سرور ایران ایجاد کند. پنل Relay را روی TLS و با نام‌کاربری و رمز تصادفی اجرا می‌کند. جزئیات این روش در [مستند رسمی Relay در GOST](https://gost.run/en/tutorials/protocols/relay/) آمده است.

~~~text
کلاینت AnyTLS → IP ایران:پورت ورودی → Relay روی ایران → اتصال خروجی Agent در خارج → 127.0.0.1:پورت AnyTLS
~~~

دو نقش را جداگانه تنظیم کنید:

1. در سرور ایران، **GOST forwarding management → Set up or update reverse GOST tunnel → Configure Iran relay server** را انتخاب کنید. نام‌کاربری و رمز ساخته‌شده را نگه دارید. پورت کنترل TCP (پیش‌فرض `8444`) را در فایروال ایران و ارائه‌دهنده فقط برای IP عمومی سرور خارج باز کنید.
2. در سرور خارج که AnyTLS روی آن اجراست، **GOST forwarding management → Set up or update reverse GOST tunnel → Configure foreign AnyTLS server agent** را انتخاب کنید. آدرس ایران، پورت کنترل و مشخصات ورود، پورت ورودی کلاینت در ایران و پورت محلی AnyTLS را وارد کنید. پورت ورودی و پورت AnyTLS هر دو به‌طور پیش‌فرض `8443` هستند.
3. پورت ورودی ایران را در فایروال سرور و ارائه‌دهنده برای کلاینت‌ها باز کنید. در پروفایل AnyTLS، IP عمومی ایران و پورت ورودی را قرار دهید و رمز AnyTLS را بدون تغییر نگه دارید.

در این روش Agent از خارج به ایران وصل می‌شود؛ بنابراین پورت کنترل ایران باید از سرور خارج قابل‌دسترسی باشد. اگر امکان دارد، دسترسی آن را در فایروال به IP سرور خارج محدود کنید. مشخصات Relay و تنظیمات GOST در فایلی با دسترسی محدود ذخیره می‌شوند. TLS دادهٔ تونل را رمز می‌کند، اما Agent گواهی خودکار GOST را بررسی نمی‌کند؛ محدودکردن دسترسی پورت کنترل به IP مبدأ توصیه می‌شود. انتخاب هرکدام از حالت‌های GOST، تنظیم سرویس `anytls-tunnel` همان سرور را جایگزین می‌کند؛ Relay ایران و Agent خارج را روی سرورهای مربوط به خود تنظیم کنید.

## ساخت پروفایل کلاینت

سرور با پیاده‌سازی اصلی AnyTLS-Go و یک رمز مشترک اجرا می‌شود. نصب تازه یک رمز تصادفی ۳۲ کاراکتری می‌سازد و آن را یک‌بار برای ذخیره‌کردن نشان می‌دهد؛ رمز در تنظیمات فقط‌خواندنی برای root ذخیره می‌شود. با تغییر IP شنود یا پورت، رمز تصادفی تازه‌ای هم ساخته و ذخیره می‌شود و یک‌بار نمایش داده می‌شود. پروفایل‌های قبلی پس از این تغییر کار نمی‌کنند؛ از گزینهٔ ۳، QR/JSON تازه بسازید. پنل برای NekoBox لینک و QR و برای sing-box در Android، iOS و Windows فایل JSON می‌سازد. نام پروفایل در QR و تگ outbound فایل JSON برابر `AnyTLS-Go` است و نام هر فایل `AnyTLS-Go.json` در پوشهٔ پلتفرم مربوطه خواهد بود.

برای اتصال مستقیم IP سرور خارج را وارد کنید؛ اگر فوروارد GOST روی ایران دارید، IP عمومی ایران را وارد کنید. برای NekoBox، QR یا لینک AnyTLS را وارد کنید. فایل‌های JSON پیکربندی کامل sing-box هستند: `tls.insecure`، ALPN برابر `h2` و `http/1.1`، fingerprint متناسب با دستگاه (`android`، `ios` یا `chrome` برای Windows) و DNS از مسیر AnyTLS را تنظیم می‌کنند. NekoBox از JSONهای sing-box فقط outbound را وارد می‌کند و قوانین مسیریابی را نادیده می‌گیرد؛ تست URL آن نیز DNS مستقیم دارد. به همین دلیل ممکن است خطای `cp.cloudflare.com` یا `missing default interface` در تست باقی بماند. خطای تست به‌تنهایی ثابت نمی‌کند اتصال AnyTLS برقرار نشده؛ پس از اتصال، یک سایت را در مرورگر باز کنید. SNI پیش‌فرض `www.cloudflare.com` است؛ در صورت داشتن دامنهٔ خودتان آن را جایگزین کنید. SNI اتصال را از مسیر Cloudflare عبور نمی‌دهد و عبور از فیلترینگ را تضمین نمی‌کند. گزینهٔ `tls.insecure` بررسی گواهی را غیرفعال می‌کند و می‌تواند اتصال را در برابر رهگیری آسیب‌پذیر کند. تقلید uTLS نیز تضمینی برای شناسایی‌نشدن ترافیک نیست.

اگر سروری هنوز از بک‌اند قدیمی sing-box چندکاربره استفاده می‌کند، از مسیر **AnyTLS server management → Restore AnyTLS-Go single-user mode** برگردید. رمز اولین حساب فعال به رمز مشترک AnyTLS-Go تبدیل می‌شود و تنظیمات و خروجی‌های sing-box در پوشهٔ پشتیبان نگه داشته می‌شوند.

راهنما آخرین نسخهٔ پایدار رسمی GOST برای Linux amd64 یا arm64 را دانلود و پیش از نصب SHA-256 آن را بررسی می‌کند. فوروارد به‌صورت سرویس systemd اجرا می‌شود، پس از راه‌اندازی مجدد سرور خودکار بالا می‌آید و در صورت خطا دوباره اجرا می‌شود. برای سازگاری با فرمان‌های پنل، نام سرویس anytls-tunnel باقی مانده است.

## امکانات پنل

- نمایش وضعیت و اجرای start، stop، restart، enable هنگام بوت یا disable برای سرور AnyTLS و سرویس فوروارد.
- مشاهده یا دنبال‌کردن گزارش سرویس‌ها.
- تغییر IP شنود و پورت همراه با ساخت رمز مشترک تازه؛ اگر سرویس اجرا نشود تنظیم قبلی بازگردانده می‌شود.
- بازگرداندن نصب‌های قدیمی sing-box به حالت تک‌کاربرهٔ AnyTLS-Go.
- ساخت QR برای AnyTLS-Go و فایل JSON sing-box برای Android، iOS و Windows.
- راه‌اندازی فوروارد مستقیم GOST یا هر دو نقش تونل معکوس GOST.
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
- curl، Python 3 و ابزارهای استاندارد سیستم.
- نصب‌کننده هنگام نصب AnyTLS یا بازکردن پنل، qrencode را خودکار نصب می‌کند تا خروجی QR آماده باشد. package managerهای پشتیبانی‌شده apt، dnf، yum، zypper و apk هستند.
- فوروارد GOST از Linux amd64 و arm64 پشتیبانی می‌کند.
- فوروارد روی IP انتخاب‌شده در راهنما شنود می‌کند. برای پذیرش اتصال روی همهٔ رابط‌های IPv4 مقدار **0.0.0.0** را انتخاب کنید و دسترسی را با فایروال محدود کنید.
- پورت ورودی باید روی سرور ایران آزاد باشد.
- AnyTLS-Go خود را پیاده‌سازی مرجع معرفی می‌کند و هشدار می‌دهد تنظیم نمونه با فرض نبود حملهٔ MITM است. پیش از استفاده برای ترافیک حساس، [مستندات پروژهٔ اصلی](https://github.com/anytls/anytls-go) را بخوانید.
