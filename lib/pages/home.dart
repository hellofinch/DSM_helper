import 'dart:async';
import 'dart:io';

import 'package:dsm_helper/pages/download/download.dart';
import 'package:dsm_helper/pages/file/file.dart';
import 'package:dsm_helper/pages/setting/setting.dart';
import 'package:dsm_helper/util/function.dart';
import 'package:dsm_helper/widgets/update_dialog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sharing_intent/flutter_sharing_intent.dart';
import 'package:flutter_sharing_intent/model/sharing_file.dart';
import 'package:neumorphic/neumorphic.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_vibrate/flutter_vibrate.dart';

import 'dashborad/dashboard.dart';
import 'download_station/add_task.dart';
import 'file/upload.dart';
import 'login/auth_page.dart';

class Home extends StatefulWidget {
  @override
  _HomeState createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  int _currentIndex = 0;
  DateTime lastPopTime;
  PackageInfo packageInfo;
  GlobalKey<FilesState> _filesStateKey = GlobalKey<FilesState>();
  GlobalKey<DashboardState> _dashboardStateKey = GlobalKey<DashboardState>();
  //判断是否需要启动密码
  bool launchAuth = false;
  bool password = false;
  bool biometrics = false;
  bool authPage = false;
  List<SharedFile> _sharedFiles;
  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    getData();
    Util.setStorage("agreement", "1");
    FlutterSharingIntent.instance
        .getInitialSharing()
        .then((List<SharedFile> value) {
      print("Shared: getInitialMedia ${value.map((f) => f.path).join(",")}");
      handleFiles(value);
    });
    // For sharing images coming from outside the app while the app is in the memory
    FlutterSharingIntent.instance.getMediaStream().listen(
        (List<SharedFile> value) {
      handleFiles(value);
      print("Shared: getMediaStream ${value.map((f) => f.path).join(",")}");
    }, onError: (err) {
      print("getIntentDataStream error: $err");
    });
    // For sharing images coming from outside the app while the app is in the memory
    // ReceiveSharingIntent.getMediaStream().listen((List<SharedMediaFile> value) {
    //   handleFiles(value);
    // }, onError: (err) {
    //   debugPrint("getIntentDataStream error: $err");
    // });
    //
    // // For sharing images coming from outside the app while the app is closed
    // ReceiveSharingIntent.getInitialMedia().then((List<SharedMediaFile> value) {
    //   handleFiles(value);
    // });
    // // For sharing or opening urls/text coming from outside the app while the app is in the memory
    // ReceiveSharingIntent.getTextStream().listen((String value) {
    //   // Util.toast("getTextStream:$value");
    //   if (value != null) {
    //     handleTorrent(value);
    //   }
    // }, onError: (err) {
    //   debugPrint("getLinkStream error: $err");
    // });
    //
    // // For sharing or opening urls/text coming from outside the app while the app is closed
    // ReceiveSharingIntent.getInitialText().then((String value) {
    //   if (value != null) {
    //     handleTorrent(value);
    //   }
    // });
    super.initState();
  }

  handleFiles(List<SharedFile> files) async {
    _sharedFiles = files;
    if (_sharedFiles != null && _sharedFiles.length > 0) {
      if (_sharedFiles.length == 1 &&
          _sharedFiles.first.path.endsWith(".torrent")) {
        String filePath = '';
        if (Platform.isAndroid) {
          filePath = await FlutterSharingIntent.getAbsolutePath(
              _sharedFiles.first.path);
        } else {
          filePath = _sharedFiles.first.path;
        }
        Navigator.of(context).push(CupertinoPageRoute(builder: (context) {
          return AddDownloadTask(
            torrentPath: filePath,
          );
        }));
        //   if (content.startsWith("content://") && content.endsWith(".torrent")) {
        //     // final filePath = await FlutterSharingIntent.getAbsolutePath(content);
        //
        //     }));
        //     // if (filePath.endsWith("torrent")) {}
        //   }
      } else {
        Navigator.of(context).push(CupertinoPageRoute(builder: (context) {
          return Upload(
            "",
            selectedFilesPath: _sharedFiles.map((e) => e.path).toList(),
          );
        }));
      }
    }
  }

  // handleTorrent(String content) async {
  //   if (content.startsWith("content://") && content.endsWith(".torrent")) {
  //     // final filePath = await FlutterSharingIntent.getAbsolutePath(content);
  //     Navigator.of(context).push(CupertinoPageRoute(builder: (context) {
  //       return AddDownloadTask(
  //         torrentPath: ,
  //       );
  //     }));
  //     // if (filePath.endsWith("torrent")) {}
  //   }
  // }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      checkAuth();
    }
  }

  checkAuth() async {
    // print("是否需要启动密码")
    String launchAuthStr = await Util.getStorage("launch_auth");
    String launchAuthPasswordStr =
        await Util.getStorage("launch_auth_password");
    String launchAuthBiometricsStr =
        await Util.getStorage("launch_auth_biometrics");
    if (launchAuthStr != null) {
      launchAuth = launchAuthStr == "1";
    } else {
      launchAuth = false;
    }
    if (launchAuthPasswordStr != null) {
      password = launchAuthPasswordStr == "1";
    } else {
      password = false;
    }
    if (launchAuthBiometricsStr != null) {
      biometrics = launchAuthBiometricsStr == "1";
    } else {
      biometrics = false;
    }

    authPage = launchAuth && (password || biometrics);
    if (Util.isAuthPage == false && authPage) {
      Navigator.of(context).push(CupertinoPageRoute(builder: (context) {
        return AuthPage(
          launch: false,
        );
      }));
    }
  }

  getData() async {
    if (Platform.isAndroid) {
      packageInfo = await PackageInfo.fromPlatform();
      // String buildNumber = packageInfo.buildNumber;
      // if (kDebugMode) {
      //   buildNumber = '1';
      // }
      // var res = await Api.update(buildNumber); //packageInfo.buildNumber
      // if (res['code'] == 1) {
      //   showCupertinoDialog(
      //     context: context,
      //     builder: (context) {
      //       return UpdateDialog(res['data'], packageInfo);
      //     },
      //   );
      // }
    }
  }

  Future<bool> onWillPop() {
    Util.vibrate(FeedbackType.light);
    Future<bool> value = Future.value(true);
    if (_currentIndex == 0) {
      if (_dashboardStateKey.currentState.isDrawerOpen) {
        _dashboardStateKey.currentState.closeDrawer();
        return Future.value(false);
      }
    } else if (_currentIndex == 1) {
      if (_filesStateKey.currentState.isDrawerOpen) {
        _filesStateKey.currentState.closeDrawer();
        return Future.value(false);
      }
      value = _filesStateKey.currentState.onWillPop();
    } else if (_currentIndex == 2) {
      value = Util.downloadKey.currentState.onWillPop();
    }
    value.then((v) {
      if (v) {
        if (lastPopTime == null ||
            DateTime.now().difference(lastPopTime) > Duration(seconds: 2)) {
          lastPopTime = DateTime.now();
          Util.toast('再按一次退出${Util.appName}');
        } else {
          lastPopTime = DateTime.now();
          // 退出app
          SystemNavigator.pop();
        }
      }
    });
    return Future.value(false);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope( //PopScope instead 3.12.0 Deprecated
      onWillPop: onWillPop,
      child: Scaffold(
        appBar: null,
        body: IndexedStack(
          children: [
            Dashboard(key: _dashboardStateKey),
            Files(key: _filesStateKey),
            Download(key: Util.downloadKey),
            Setting(),
          ],
          index: _currentIndex,
        ),
        bottomNavigationBar: NeuSwitch(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          thumbColor: Theme.of(context).scaffoldBackgroundColor,
          // padding: EdgeInsets.symmetric(vertical: 5),
          onValueChanged: (v) {
            setState(() {
              _currentIndex = v;
            });
          },
          groupValue: _currentIndex,
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
          children: {
            0: Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  Image.asset(
                    "assets/tabbar/meter.png",
                    width: 30,
                    height: 30,
                  ),
                  Text(
                    "控制台",
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            1: Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  Image.asset(
                    "assets/tabbar/folder.png",
                    width: 30,
                    height: 30,
                  ),
                  Text(
                    "文件",
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            2: Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  Image.asset(
                    "assets/tabbar/save.png",
                    width: 30,
                    height: 30,
                  ),
                  Text(
                    "下载",
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            3: Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  Image.asset(
                    "assets/tabbar/setting.png",
                    width: 30,
                    height: 30,
                  ),
                  Text(
                    "设置",
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          },
        ),
      ),
    );
  }
}
