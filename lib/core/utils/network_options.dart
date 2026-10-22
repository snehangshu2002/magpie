import 'dart:io';

/// Sets up [client] for yt-dlp's network [options] (`networkArgs`): the
/// last `--proxy`, `-4` and the last `--user-agent` (else
/// [defaultUserAgent], else the client's own), as yt-dlp reads them.
void applyNetworkOptions(
  HttpClient client,
  List<String> options, {
  String? defaultUserAgent,
}) {
  String? valueOf(String name) {
    final i = options.lastIndexOf(name);
    return i >= 0 && i + 1 < options.length ? options[i + 1] : null;
  }

  client.userAgent =
      valueOf('--user-agent') ?? defaultUserAgent ?? client.userAgent;
  final proxy = Uri.tryParse(valueOf('--proxy') ?? '');
  // shortcut: HttpClient speaks only to plain HTTP proxies, so https:// and
  // SOCKS proxies are skipped and these lookups go direct; upgrade with a
  // SOCKS/TLS-capable client if users rely on those proxies for privacy.
  if (proxy != null && proxy.scheme == 'http' && proxy.host.isNotEmpty) {
    final auth = proxy.userInfo.isEmpty ? '' : '${proxy.userInfo}@';
    final directive = 'PROXY $auth${proxy.host}:${proxy.port}';
    client.findProxy = (_) => directive;
  }
  if (options.contains('-4')) {
    client.connectionFactory = (url, proxyHost, proxyPort) async {
      final host = proxyHost ?? url.host;
      final addresses = await InternetAddress.lookup(
        host,
        type: InternetAddressType.IPv4,
      );
      final task = await Socket.startConnect(
        addresses.first,
        proxyPort ?? url.port,
      );
      // HttpClient expects TLS already set up for https without a proxy.
      if (proxyHost != null || url.scheme != 'https') return task;
      return ConnectionTask.fromSocket(
        task.socket.then((s) => SecureSocket.secure(s, host: url.host)),
        task.cancel,
      );
    };
  }
}
