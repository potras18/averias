export 'download_file_stub.dart'
    if (dart.library.html) 'download_file_web.dart'
    if (dart.library.io) 'download_file_mobile.dart';
