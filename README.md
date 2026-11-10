# AnyTLS-Go Server Installer and Control Panel

[English](#english) · [فارسی](#persian)

<a id="english"></a>

## English

Install the latest stable AnyTLS-Go release on Linux with systemd, manage its service from an interactive terminal panel, or configure an SSH TCP forward on an Iran-side server to reach an AnyTLS server abroad.

## Quick install

Run this single line in an interactive Linux terminal:

~~~bash
installer=$(curl -fsSL https://raw.githubusercontent.com/alirezahdr/anytls-go-installer/main/install-anytls.sh) && sudo bash -c "$installer"
~~~

The installer asks which role this server should perform:

1. **AnyTLS server** — downloads the latest stable official release and asks for the listen IP, port, and password.
2. **Iran-to-abroad SSH tunnel** — configures this server as the client-facing TCP entrypoint and forwards connections over SSH to AnyTLS running abroad. It does not install a local AnyTLS server.
3. **Control panel** — opens the service menus without changing the current configuration.

After a server installation, the panel opens automatically. Start it later with:

~~~bash
sudo anytls-panel
~~~

The command downloads the installer into a shell variable, then runs it with root privileges while keeping the terminal available for the interactive prompts. Review the installer and panel source before using them on a production server.

## What the panel can do

- Show status and start, stop, restart, enable at boot, or disable at boot for the AnyTLS server.
- Follow or review AnyTLS service logs.
- Change the AnyTLS server listen IP, port, and password.
- Set up or update the Iran-to-abroad SSH TCP forward.
- Show status and control the tunnel service, and inspect its non-secret connection settings.
- Display the equivalent systemd commands.

The TUI prompts and menu are in English.

## Iran-to-abroad forwarding

The tunnel direction is:

~~~text
AnyTLS clients → Iran server IP:port → SSH connection → AnyTLS host:port reachable from the foreign server
~~~

In the installer menu, select **Iran-to-abroad SSH tunnel**. The wizard asks for:

- The foreign server's SSH host, port, and account name.
- The listen IP and client-facing port on the Iran server.
- The AnyTLS host and port as reachable from the foreign server. Use 127.0.0.1 when AnyTLS listens on that same foreign server.
- SSH key authorization and SSH host-key verification.

The wizard creates a dedicated Ed25519 key and displays its public key. Add that key to the selected account's authorized_keys file on the foreign server. The foreign sshd must allow local TCP forwarding to the configured AnyTLS destination; use AllowTcpForwarding local and, where appropriate, restrict PermitOpen to the required host and port. The wizard does not change the foreign server.

The tunnel runs as the anytls-tunnel systemd service, starts at boot, and reconnects after a connection failure. Before trusting the foreign SSH host key, independently verify the fingerprint shown by the wizard using the foreign server console or another trusted channel.

Clients connect to the **public IP of the Iran server** on the selected local port, using the AnyTLS password configured on the foreign AnyTLS server. Allow inbound TCP on that port in both the Iran server's firewall and its hosting provider firewall. The SSH port on the foreign server must be reachable outbound from Iran.

## Service commands

The same actions are available from the TUI. You can also run them directly:

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

The tunnel commands apply after you configure the SSH forward. Disabling a service prevents boot startup but does not stop a service that is already running.

## Requirements

- Linux with systemd and root or sudo access.
- The installer requires curl, python3, base64, and standard account utilities.
- For the SSH tunnel, the OpenSSH client commands ssh, ssh-keygen, and ssh-keyscan must be installed. If the panel reports one missing, install your distribution's OpenSSH client package and run the setup again.
- AnyTLS-Go official release archives are selected for amd64 or arm64.

## Security notes

- The SSH tunnel listens on the IP you select. Use 0.0.0.0 only when clients should connect through the server's network interfaces, and restrict access with the server and provider firewalls.
- The tunnel uses a dedicated private key stored under /etc/anytls-tunnel with restrictive permissions. The AnyTLS password is not copied into the tunnel configuration.
- Verify the remote SSH host-key fingerprint independently before accepting it.
- AnyTLS-Go describes itself as a reference implementation and warns that its sample configuration assumes there is no man-in-the-middle attack. Read the [upstream project documentation](https://github.com/anytls/anytls-go) before using it for sensitive traffic.

---

<a id="persian"></a>

## فارسی

آخرین نسخهٔ پایدار AnyTLS-Go را روی لینوکس و systemd نصب کنید، سرویس را از پنل تعاملی ترمینال مدیریت کنید، یا روی سرور ایران یک فوروارد TCP از طریق SSH به AnyTLS روی سرور خارج بسازید.

## نصب سریع

این یک خط را در ترمینال تعاملی لینوکس اجرا کنید:

~~~bash
installer=$(curl -fsSL https://raw.githubusercontent.com/alirezahdr/anytls-go-installer/main/install-anytls.sh) && sudo bash -c "$installer"
~~~

نصب‌کننده می‌پرسد این سرور چه نقشی داشته باشد:

1. **سرور AnyTLS** — آخرین نسخهٔ پایدار رسمی را می‌گیرد و IP شنود، پورت و رمز را می‌پرسد.
2. **تونل SSH از ایران به خارج** — این سرور را به نقطهٔ ورودی کاربران تبدیل می‌کند و اتصال‌ها را از طریق SSH به AnyTLS روی سرور خارج فوروارد می‌کند. در این حالت AnyTLS روی سرور ایران نصب نمی‌شود.
3. **پنل مدیریت** — منوهای سرویس را باز می‌کند و پیکربندی فعلی را تغییر نمی‌دهد.

پس از نصب سرور، پنل خودکار باز می‌شود. برای اجرای دوبارهٔ آن:

~~~bash
sudo anytls-panel
~~~

این فرمان ابتدا نصب‌کننده را در یک متغیر پوسته دریافت می‌کند، سپس آن را با دسترسی root اجرا می‌کند و ورودی ترمینال را برای پرسش‌های تعاملی باز نگه می‌دارد. پیش از استفاده روی سرور عملیاتی، سورس نصب‌کننده و پنل را بررسی کنید.

## امکانات پنل

- نمایش وضعیت و اجرای start، stop، restart، enable هنگام بوت و disable سرویس AnyTLS.
- مشاهدهٔ گزارش‌های سرویس.
- تغییر IP شنود، پورت و رمز سرور AnyTLS.
- راه‌اندازی یا تنظیم دوبارهٔ فوروارد SSH از ایران به خارج.
- نمایش وضعیت و مدیریت سرویس تونل و مشاهدهٔ تنظیمات اتصالِ غیرمحرمانه.
- نمایش دستورهای معادل systemd.

منو و پرسش‌های TUI به زبان انگلیسی هستند.

## فوروارد از ایران به خارج

جهت تونل به این صورت است:

~~~text
کاربر AnyTLS → IP و پورت سرور ایران → اتصال SSH → میزبان و پورت AnyTLS از دید سرور خارج
~~~

در منوی نصب، **Iran-to-abroad SSH tunnel** را انتخاب کنید. راهنما این موارد را می‌پرسد:

- میزبان SSH سرور خارج، پورت SSH و نام حساب کاربری.
- IP شنود و پورت ورودی کاربران روی سرور ایران.
- میزبان و پورت AnyTLS از دید سرور خارج. اگر AnyTLS روی همان سرور خارج اجرا می‌شود، مقدار میزبان را 127.0.0.1 بگذارید.
- مجوز کلید SSH و تأیید کلید میزبان SSH.

راهنما یک کلید اختصاصی Ed25519 می‌سازد و کلید عمومی را نمایش می‌دهد. آن را به فایل authorized_keys حساب انتخاب‌شده روی سرور خارج اضافه کنید. سرویس SSH سرور خارج باید فوروارد TCP محلی به مقصد AnyTLS تنظیم‌شده را مجاز بداند؛ از AllowTcpForwarding local استفاده کنید و در صورت نیاز PermitOpen را به همان میزبان و پورت محدود کنید. این راهنما تنظیمات سرور خارج را تغییر نمی‌دهد.

تونل به‌صورت سرویس systemd با نام anytls-tunnel اجرا می‌شود، هنگام بوت فعال است و پس از قطع اتصال دوباره تلاش می‌کند. پیش از اعتماد به کلید میزبان SSH سرور خارج، اثرانگشتی را که راهنما نشان می‌دهد از طریق کنسول سرور خارج یا یک مسیر مطمئن دیگر جداگانه بررسی کنید.

کاربران باید به **IP عمومی سرور ایران** و پورت ورودی انتخاب‌شده وصل شوند و از رمز AnyTLS تعریف‌شده روی سرور خارج استفاده کنند. پورت TCP ورودی را هم در فایروال خود سرور ایران و هم در فایروال پنل ارائه‌دهنده باز کنید. پورت SSH سرور خارج نیز باید از ایران قابل‌دسترسی باشد.

## دستورهای سرویس

همین عملیات از داخل TUI هم در دسترس است. دستورهای مستقیم:

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

دستورهای تونل پس از پیکربندی فوروارد SSH قابل استفاده هستند. disable اجرای خودکار هنگام بوت را متوقف می‌کند، اما سرویسی را که اکنون فعال است متوقف نمی‌کند.

## پیش‌نیازها

- لینوکس دارای systemd و دسترسی root یا sudo.
- نصب‌کننده به curl، python3، base64 و ابزارهای استاندارد مدیریت حساب نیاز دارد.
- برای تونل SSH، دستورهای ssh، ssh-keygen و ssh-keyscan باید نصب باشند. اگر پنل اعلام کرد دستوری موجود نیست، بستهٔ OpenSSH client توزیع خود را نصب و راهنما را دوباره اجرا کنید.
- فایل‌های رسمی AnyTLS-Go برای معماری‌های amd64 و arm64 انتخاب می‌شوند.

## نکات امنیتی

- تونل روی IP انتخابی شما شنود می‌کند. فقط زمانی 0.0.0.0 را انتخاب کنید که کاربران باید از طریق رابط‌های شبکهٔ سرور وصل شوند و دسترسی را با فایروال سرور و ارائه‌دهنده محدود کنید.
- تونل از یک کلید خصوصی اختصاصی استفاده می‌کند که با مجوز محدود در /etc/anytls-tunnel ذخیره می‌شود. رمز AnyTLS داخل تنظیمات تونل کپی نمی‌شود.
- اثرانگشت کلید میزبان SSH سرور خارج را پیش از تأیید، جداگانه بررسی کنید.
- AnyTLS-Go خود را پیاده‌سازی مرجع معرفی می‌کند و هشدار می‌دهد تنظیم نمونه با فرض نبود حملهٔ MITM است. پیش از استفاده برای ترافیک حساس، [مستندات پروژهٔ اصلی](https://github.com/anytls/anytls-go) را بخوانید.
