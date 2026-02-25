import 'dart:io';
import 'dart:isolate';

import 'package:console_markdown/console_markdown.dart';
import 'package:http/http.dart';
import 'package:http/io_client.dart';

import 'package:tom_basics/tom_basics.dart';

class TomStandalonePlatformUtils extends TomFallbackPlatformUtils {
  TomStandalonePlatformUtils() {
    getTomEnvVars().addAll(Platform.environment);
  }

  @override
  bool isDesktop() =>
      Platform.isWindows ||
      Platform.isLinux ||
      Platform.isMacOS ||
      Platform.isFuchsia;
  @override
  bool isMobile() => Platform.isAndroid || Platform.isIOS;
  @override
  bool isWeb() => !isDesktop() && !isMobile();
  @override
  bool isWindows() => Platform.isWindows;
  @override
  bool isLinux() => Platform.isLinux;
  @override
  bool isMacOs() => Platform.isMacOS;
  @override
  bool isFuchsia() => Platform.isFuchsia;
  @override
  bool isAndroid() => Platform.isAndroid;
  @override
  bool isIos() => Platform.isIOS;
  
  @override
  void out(String s) {
    print(s.toConsole());
  }

  @override
  void outError(String s) {
    print(s.toConsole());
  }


  //const _maxCacheSize = 2 * 1024 * 1024;

  @override
  Client httpClient() {
    return IOClient(
      HttpClient()
        ..badCertificateCallback =
            (X509Certificate cert, String host, int port) {
              // allow bad certificates on local machine
              return (host.compareTo("0.0.0.0") == 0 ||
                  host.compareTo("localhost") == 0 ||
                  host.compareTo("127.0.0.1") == 0);
            },
    );
  }

  @override
  String? getBrowserLocation() {
    return null;
  }

  @override
  String getIsolateName() {
    return Isolate.current.debugName ?? "main";
  }

  @override
  String toString() => "TomPlatformUtis: standalone/server";
}

TomPlatformUtils get standalonePlatformUtils =>
    TomStandalonePlatformUtils();
