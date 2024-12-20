import 'dart:async';
import 'dart:io';
import 'package:android_intent_plus/android_intent.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:draggable_scrollbar/draggable_scrollbar.dart';
import 'package:dsm_helper/util/log.dart';
import 'package:flutter_floating/floating/listener/event_listener.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:dsm_helper/pages/common/audio_player.dart';
import 'package:dsm_helper/pages/common/image_preview.dart';
import 'package:dsm_helper/pages/common/pdf_viewer.dart';
import 'package:dsm_helper/pages/common/text_editor.dart';
import 'package:dsm_helper/pages/common/video_player.dart';
import 'package:dsm_helper/pages/control_panel/shared_folders/add_shared_folder.dart';
import 'package:dsm_helper/pages/file/detail.dart';
import 'package:dsm_helper/pages/file/favorite.dart';
import 'package:dsm_helper/pages/file/remote_folder.dart';
import 'package:dsm_helper/pages/file/search.dart';
import 'package:dsm_helper/pages/file/select_folder.dart';
import 'package:dsm_helper/pages/file/share.dart';
import 'package:dsm_helper/pages/file/share_manager.dart';
import 'package:dsm_helper/pages/file/upload.dart';
import 'package:dsm_helper/providers/audio_player_provider.dart';
import 'package:dsm_helper/themes/app_theme.dart';
import 'package:dsm_helper/util/function.dart';
import 'package:dsm_helper/widgets/animation_progress_bar.dart';
import 'package:dsm_helper/widgets/file_icon.dart';
import 'package:dsm_helper/widgets/transparent_router.dart';
import 'package:extended_image/extended_image.dart';
import 'package:extended_text/extended_text.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_floating/floating/assist/floating_slide_type.dart';
import 'package:flutter_floating/floating/floating.dart';
import 'package:flutter_floating/floating/manager/floating_manager.dart';
import 'package:neumorphic/neumorphic.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:flutter_vibrate/flutter_vibrate.dart';

enum ListType { list, icon }

class Files extends StatefulWidget {
  Files({key}) : super(key: key);
  @override
  FilesState createState({key}) => FilesState();
}

class FilesState extends State<Files> {
  GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  List paths = [];
  List files = [];
  List smbFolders = [];
  List ftpFolders = [];
  List sftpFolders = [];
  List davFolders = [];
  bool loading = true;
  bool favoriteLoading = true;
  List favorites = [];
  bool success = true;
  String msg = "";
  bool multiSelect = false;
  List selectedFiles = [];
  ScrollController _pathScrollController = ScrollController();
  ScrollController _fileScrollController = ScrollController();
  Map backgroundProcess = {};
  bool showProcessList = false;
  String sortBy = "name";
  String sortDirection = "ASC";
  bool searchResult = false;
  bool searching = false;
  Timer searchTimer;
  Timer processingTimer;
  ListType listType = ListType.list;
  Map scrollPosition = {};
  Floating audioPlayerFloating;
  @override
  void dispose() {
    searchTimer?.cancel();
    processingTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    getShareList();
    getSmbFolder();
    getFtpFolder();
    getSftpFolder();
    getDavFolder();
    processingTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      getBackgroundTask();
    });

    _fileScrollController.addListener(() {
      String path = "";
      if (paths.length > 0) {
        path = "/" + paths.join("/");
      } else {
        path = "/";
      }
      scrollPosition[path] = _fileScrollController.offset;
    });
    super.initState();
  }

  getBackgroundTask() async {
    var res = await Api.backgroundTask();
    if (res['success']) {
      if (res['data']['tasks'] != null && res['data']['tasks'].length > 0) {
        for (var task in res['data']['tasks']) {
          if (backgroundProcess[task['taskid']] == null) {
            String type = "";
            switch (task['api']) {
              case 'SYNO.FileStation.CopyMove':
                if (task['params']['remove_src']) {
                  type = "move";
                } else {
                  type = "copy";
                }
                break;
              case 'SYNO.FileStation.Delete':
                type = "delete";
                break;
              case 'SYNO.FileStation.Compress':
                type = "compress";
                break;
              case 'SYNO.FileStation.Extract':
                type = 'extract';
                break;
            }
            if (type.isNotBlank) {
              backgroundProcess[task['taskid']] = {
                "timer": null,
                "data": task,
                'type': type,
                'path': task['params']['path'],
              };
              getProcessingTaskResult(task['taskid']);
            }
          }
        }
      }
    }
  }

  getCopyMoveTaskResult(String taskId) async {
    //获取复制/移动进度
    var result = await Api.copyMoveResult(taskId);
    Log.logger.info(result);
    if (result['success'] != null && result['success']) {
      setState(() {
        backgroundProcess[taskId]['data'] = result['data'];
      });
      if (result['data']['finished']) {
        if (showProcessList = true) {
          Util.toast(
              "${result['data']['path']} ${backgroundProcess[taskId]['type'] == 'copy' ? '复制' : '移动'}到 ${result['data']['dest_folder_path']} 完成");
        }

        backgroundProcess[taskId]['timer']?.cancel();
        backgroundProcess[taskId]['timer'] = null;
        backgroundProcess.remove(taskId);
        refresh();
      }
    }
  }

  getDeleteTaskResult(String taskId) async {
    //获取删除进度
    try {
      var result = await Api.deleteResult(taskId);
      if (result['success'] != null && result['success']) {
        if (result['data']['finished']) {
          if (showProcessList = true) {
            Util.toast("文件删除完成");
          }
          backgroundProcess[taskId]['timer']?.cancel();
          backgroundProcess[taskId]['timer'] = null;
          backgroundProcess.remove(taskId);
          refresh();
        }
      }
    } catch (e) {
      Util.toast("文件删除出错");
      backgroundProcess[taskId]['timer']?.cancel();
      backgroundProcess[taskId]['timer'] = null;
      backgroundProcess.remove(taskId);
    }
  }

  getExtractTaskResult(String taskId) async {
    var result = await Api.extractResult(taskId);
    if (result['success'] != null && result['success']) {
      if (result['data']['finished']) {
        if (result['data']['errors'] != null &&
            result['data']['errors'].length > 0) {
          if (result['data']['errors'][0]['code'] == 1403) {
            String password = "";
            showCupertinoDialog(
                context: context,
                builder: (context) {
                  return Material(
                    color: Colors.transparent,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        NeuCard(
                          width: double.infinity,
                          margin: EdgeInsets.symmetric(horizontal: 50),
                          curveType: CurveType.emboss,
                          bevel: 5,
                          decoration: NeumorphicDecoration(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Column(
                              children: [
                                Text(
                                  "解压密码",
                                  style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w500),
                                ),
                                SizedBox(
                                  height: 16,
                                ),
                                NeuCard(
                                  decoration: NeumorphicDecoration(
                                    color: Theme.of(context)
                                        .scaffoldBackgroundColor,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  bevel: 20,
                                  curveType: CurveType.flat,
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 5),
                                  child: TextField(
                                    onChanged: (v) => password = v,
                                    decoration: InputDecoration(
                                      border: InputBorder.none,
                                      hintText: "请输入解压密码",
                                      labelText: "解压密码",
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  height: 20,
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: NeuButton(
                                        onPressed: () async {
                                          if (password == "") {
                                            Util.toast("请输入解压密码");
                                            return;
                                          }
                                          Navigator.of(context).pop();
                                          extractFile(result['data']['path'],
                                              password: password);
                                        },
                                        decoration: NeumorphicDecoration(
                                          color: Theme.of(context)
                                              .scaffoldBackgroundColor,
                                          borderRadius:
                                              BorderRadius.circular(25),
                                        ),
                                        bevel: 20,
                                        padding:
                                            EdgeInsets.symmetric(vertical: 10),
                                        child: Text(
                                          "确定",
                                          style: TextStyle(fontSize: 18),
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 16,
                                    ),
                                    Expanded(
                                      child: NeuButton(
                                        onPressed: () async {
                                          Navigator.of(context).pop();
                                        },
                                        decoration: NeumorphicDecoration(
                                          color: Theme.of(context)
                                              .scaffoldBackgroundColor,
                                          borderRadius:
                                              BorderRadius.circular(25),
                                        ),
                                        bevel: 20,
                                        padding:
                                            EdgeInsets.symmetric(vertical: 10),
                                        child: Text(
                                          "取消",
                                          style: TextStyle(fontSize: 18),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                });
          }
        } else {
          if (showProcessList = true) {
            Util.toast("文件解压完成");
          }
        }
        backgroundProcess[taskId]['timer']?.cancel();
        backgroundProcess[taskId]['timer'] = null;
        backgroundProcess.remove(taskId);
        refresh();
      } else {
        setState(() {
          backgroundProcess[taskId]['data'] = result['data'];
        });
      }
    }
  }

  getCompressTaskResult(String taskId) async {
    //获取压缩进度
    try {
      var result = await Api.compressResult(taskId);
      if (result['success'] != null && result['success']) {
        if (result['data']['finished']) {
          if (showProcessList = true) {
            Util.toast("文件压缩完成");
          }

          backgroundProcess[taskId]['timer']?.cancel();
          backgroundProcess[taskId]['timer'] = null;
          backgroundProcess.remove(taskId);
          refresh();
        }
      }
    } catch (e) {
      Util.toast("文件压缩出错");
      backgroundProcess[taskId]['timer']?.cancel();
      backgroundProcess[taskId]['timer'] = null;
      backgroundProcess.remove(taskId);
    }
  }

  getProcessingTaskResult(String taskId) {
    if (backgroundProcess[taskId] == null) {
      return;
    }
    backgroundProcess[taskId]['timer'] =
        Timer.periodic(Duration(seconds: 1), (_) async {
      switch (backgroundProcess[taskId]['type']) {
        case 'copy':
        case 'move':
          getCopyMoveTaskResult(taskId);
          break;
        case 'extract':
          getExtractTaskResult(taskId);
          break;
        case 'delete':
          getDeleteTaskResult(taskId);
          break;
        case 'compress':
          getCompressTaskResult(taskId);
          break;
      }
    });
  }

  initFloating() {
    if (audioPlayerFloating == null) {
      var audioPlayerProvider = context.read<AudioPlayerProvider>();
      ja.AudioPlayer player = audioPlayerProvider.player;

      audioPlayerFloating = floatingManager.createFloating(
        "audio_player_floating",
        Floating(
          SizedBox(
            width: 50,
            height: 50,
            child: Stack(
              children: [
                NeuCard(
                  decoration: NeumorphicDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).scaffoldBackgroundColor,
                  ),
                  bevel: 10,
                  width: 50,
                  height: 50,
                  child: ExtendedImage.asset("assets/music_cover.png"),
                ),
                StreamBuilder(
                  stream: player.positionStream,
                  builder:
                      (BuildContext context, AsyncSnapshot<Duration> snapshot) {
                    Duration _duration = player.duration ?? Duration.zero;
                    Duration _position = snapshot.data ?? Duration(seconds: 1);
                    return CircularPercentIndicator(
                      radius: 25,
                      animation: true,
                      progressColor: Colors.blue,
                      animateFromLastPercent: true,
                      circularStrokeCap: CircularStrokeCap.round,
                      lineWidth: 3,
                      backgroundColor: Colors.black12,
                      percent: _position.inMilliseconds.toDouble() /
                          _duration.inMilliseconds.toDouble(),
                    );
                  },
                ),
              ],
            ),
          ),
          slideType: FloatingSlideType.onRightAndBottom,
          bottom: 200,
          right: 0,
          isShowLog: true,
          slideBottomHeight: 100,
        ),
      );
      FloatingEventListener listener = FloatingEventListener()
        ..downListener = (point) {
          if (audioPlayerFloating.isShowing) {
            audioPlayerFloating.close();
          }
          Navigator.of(context).push(CupertinoPageRoute(builder: (context) {
            return AudioPlayer();
          })).then((_) {
            AudioPlayerProvider audioPlayerProvider =
                context.read<AudioPlayerProvider>();
            if (audioPlayerProvider.player.playing &&
                audioPlayerProvider.player.playerState.processingState !=
                    ja.ProcessingState.completed) {
              audioPlayerFloating.open(context);
            }
          });
        };
      audioPlayerFloating.addFloatingListener(listener);
      audioPlayerProvider.player.playerStateStream
          .forEach((ja.PlayerState playerState) {
        if (playerState.playing == false ||
            playerState.processingState == ja.ProcessingState.completed) {
          audioPlayerFloating.close();
        }
      });
    }
  }

  Future<List> getVolumes() async {
    var res = await Api.volumes();
    if (res['success']) {
      return res['data']['volumes'];
    } else {
      return [];
    }
  }

  refresh() {
    String path = "";
    if (paths.length > 0 && paths[0].contains("//")) {
      debugPrint("远程");
      path = paths.join("/");
    } else {
      debugPrint("本地");
      path = (paths.length > 0 ? "/" : '') + paths.join("/");
    }
    goPath(path);
  }

  bool get isDrawerOpen {
    return _scaffoldKey.currentState.isDrawerOpen;
  }

  closeDrawer() {
    if (_scaffoldKey.currentState.isDrawerOpen) {
      Navigator.of(context).pop();
    }
  }

  setPaths(String path) {
    setState(() {
      searchResult = false;
      searching = false;
    });
    if (path == "") {
      setState(() {
        paths = [];
      });
    } else {
      if (path.startsWith("/")) {
        List<String> items = path.split("/").sublist(1);
        setState(() {
          paths = items;
        });
      } else {
        List<String> parts = path.split("://");
        String scheme = parts[0];
        String first = "$scheme://${parts[1].split("/").first}";
        // String first = "${uri.scheme}://${uri.userInfo}@${uri.host}";
        List<String> items = path.replaceAll(first, "").split("/");
        items[0] = first;
        setState(() {
          paths = items;
        });
      }
    }
  }

  search(List<String> folders, String pattern, bool searchContent) async {
    setState(() {
      searchResult = true;
      searching = true;
      loading = true;
    });
    var res =
        await Api.searchTask(folders, pattern, searchContent: searchContent);
    if (res['success']) {
      bool r = await result(res['data']['taskid']);
      if (r != null && r == false) {
        //搜索未结束
        searchTimer = Timer.periodic(Duration(seconds: 2), (timer) {
          result(res['data']['taskid']);
        });
      }
    } else {
      debugPrint("搜索出错");
    }
  }

  downloadFiles(List files) async {
    ConnectivityResult connectivityResult =
        await Connectivity().checkConnectivity();
    if (connectivityResult == ConnectivityResult.mobile) {
      Util.vibrate(FeedbackType.warning);
      showCupertinoModalPopup(
        context: context,
        builder: (context) {
          return Material(
            color: Colors.transparent,
            child: NeuCard(
              width: double.infinity,
              padding: EdgeInsets.all(22),
              bevel: 5,
              curveType: CurveType.emboss,
              decoration: NeumorphicDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(22))),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      "下载确认",
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                    ),
                    SizedBox(
                      height: 12,
                    ),
                    Text(
                      "您当前正在使用数据网络，下载文件可能会产生流量费用，是否继续下载？",
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w400),
                    ),
                    SizedBox(
                      height: 22,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: NeuButton(
                            onPressed: () async {
                              Navigator.of(context).pop(true);
                              download(files);
                            },
                            decoration: NeumorphicDecoration(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              borderRadius: BorderRadius.circular(25),
                            ),
                            bevel: 5,
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Text(
                              "下载",
                              style: TextStyle(
                                  fontSize: 18, color: Colors.redAccent),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 20,
                        ),
                        Expanded(
                          child: NeuButton(
                            onPressed: () async {
                              Navigator.of(context).pop(false);
                            },
                            decoration: NeumorphicDecoration(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              borderRadius: BorderRadius.circular(25),
                            ),
                            bevel: 5,
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Text(
                              "取消",
                              style: TextStyle(fontSize: 18),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(
                      height: 8,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ).then((value) {
        if (value == null || value == false) {
          return;
        }
      });
    } else {
      download(files);
    }
  }

  download(files) async {
    // 检查权限
    if (Platform.isAndroid) {
      DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      if (androidInfo.version.sdkInt >= 30) {
        bool permission = false;
        permission = await Permission.manageExternalStorage.request().isGranted;
        if (!permission) {
          Util.toast("安卓11以上需授权文件管理权限");
          return;
        }
      } else {
        bool permission = false;
        permission = await Permission.storage.request().isGranted;
        if (!permission) {
          Util.toast("请先授权APP访问存储权限");
          return;
        }
      }
    }

    for (var file in files) {
      String url = Util.baseUrl +
          "/webapi/entry.cgi?api=SYNO.FileStation.Download&version=2&method=download&path=${Uri.encodeComponent(file['path'])}&mode=download&_sid=${Util.sid}";
      String filename = "";
      if (file['isdir']) {
        filename = file['name'] + ".zip";
      } else {
        filename = file['name'];
      }
      await Util.download(filename, url);
    }
    Util.toast("已添加${files.length > 1 ? "${files.length}个" : ""}下载任务，请至下载页面查看");
    Util.downloadKey.currentState.getData();
  }

  Future<bool> result(String taskId) async {
    var res = await Api.searchResult(taskId);
    if (res['success']) {
      if (res['data']['finished']) {
        searchTimer?.cancel();
      }
      setState(() {
        loading = false;
        searching = !res['data']['finished'];

        if (res['data']['files'] != null) {
          files = res['data']['files'];
        } else {
          files = [];
        }
      });

      return res['data']['finished'];
    } else {
      return null;
    }
  }

  getSmbFolder() async {
    var res = await Api.smbFolder();
    if (res['success']) {
      setState(() {
        smbFolders = res['data']['folders'];
      });
    }
  }

  getFtpFolder() async {
    var res = await Api.remoteLink("ftp");
    if (res['success']) {
      setState(() {
        ftpFolders = res['data']['folders'];
      });
    }
  }

  getSftpFolder() async {
    var res = await Api.remoteLink("sftp");
    if (res['success']) {
      setState(() {
        sftpFolders = res['data']['folders'];
      });
    }
  }

  getDavFolder() async {
    var res = await Api.remoteLink("davs");
    if (res['success']) {
      setState(() {
        davFolders = res['data']['folders'];
      });
    }
  }

  getShareList() async {
    String listTypeStr = await Util.getStorage("file_list_type");

    setState(() {
      if (listTypeStr.isNotBlank) {
        if (listTypeStr == "list") {
          listType = ListType.list;
        } else {
          listType = ListType.icon;
        }
      } else {
        listType = ListType.list;
      }
      loading = true;
    });
    var res = await Api.shareList();
    setState(() {
      loading = false;
      success = res['success'];
    });
    if (res['success']) {
      setState(() {
        files = res['data']['shares'];
      });
    } else {
      if (loading) {
        setState(() {
          msg = res['msg'] ?? "加载失败，code:${res['error']['code']}";
        });
      }
    }
  }

  getFileList(String path) async {
    setState(() {
      loading = true;
    });
    var res =
        await Api.fileList(path, sortBy: sortBy, sortDirection: sortDirection);
    setState(() {
      loading = false;
      success = res['success'];
    });
    if (res['success']) {
      setState(() {
        files = res['data']['files'];
        print(files);
      });
    } else {
      setState(() {
        msg = res['msg'] ?? Util.notReviewAccount
            ? '暂无文件'
            : "加载失败，code:${res['error']['code']}";
      });
    }
  }

  goPath(String path) async {
    debugPrint("path:$path");
    Util.vibrate(FeedbackType.light);
    setState(() {
      success = true;
    });
    setPaths(path);
    if (path == "/" || path == "") {
      await getShareList();
    } else {
      await getFileList(path);
    }
    double offset = _pathScrollController.position.maxScrollExtent;
    _pathScrollController.animateTo(offset,
        duration: Duration(milliseconds: 200), curve: Curves.ease);
    _fileScrollController.jumpTo(scrollPosition[path] ?? 0);
  }

  openPlainFile(file) async {
    setState(() {
      loading = true;
    });
    var res = await Util.get(
        Util.baseUrl +
            "/webapi/entry.cgi?api=SYNO.FileStation.Download&version=1&method=download&path=${Uri.encodeComponent(file['path'])}&mode=open&_sid=${Util.sid}",
        decode: false);
    setState(() {
      loading = false;
    });
    Navigator.of(context).push(CupertinoPageRoute(builder: (context) {
      return TextEditor(
        fileName: file['name'],
        content: res,
      );
    }));
  }

  Widget _buildSortMenu(BuildContext context, StateSetter setState) {
    return Material(
      color: Colors.transparent,
      child: NeuCard(
        width: double.infinity,
        bevel: 5,
        curveType: CurveType.emboss,
        decoration: NeumorphicDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              NeuCard(
                curveType: CurveType.flat,
                decoration: NeumorphicDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                bevel: 20,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              sortBy = "name";
                            });
                          },
                          child: Row(
                            children: [
                              Expanded(
                                child: Text("名称"),
                              ),
                              NeuCard(
                                decoration: NeumorphicDecoration(
                                  color:
                                      Theme.of(context).scaffoldBackgroundColor,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                curveType: sortBy == "name"
                                    ? CurveType.emboss
                                    : CurveType.flat,
                                padding: EdgeInsets.all(5),
                                bevel: 5,
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: sortBy == "name"
                                      ? Icon(
                                          CupertinoIcons.checkmark_alt,
                                          color: Color(0xffff9813),
                                        )
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 5),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              sortBy = "size";
                            });
                          },
                          child: Row(
                            children: [
                              Expanded(
                                child: Text("大小"),
                              ),
                              NeuCard(
                                decoration: NeumorphicDecoration(
                                  color:
                                      Theme.of(context).scaffoldBackgroundColor,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                curveType: sortBy == "size"
                                    ? CurveType.emboss
                                    : CurveType.flat,
                                padding: EdgeInsets.all(5),
                                bevel: 5,
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: sortBy == "size"
                                      ? Icon(
                                          CupertinoIcons.checkmark_alt,
                                          color: Color(0xffff9813),
                                        )
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 5),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              sortBy = "type";
                            });
                          },
                          child: Row(
                            children: [
                              Expanded(
                                child: Text("文件类型"),
                              ),
                              NeuCard(
                                decoration: NeumorphicDecoration(
                                  color:
                                      Theme.of(context).scaffoldBackgroundColor,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                curveType: sortBy == "type"
                                    ? CurveType.emboss
                                    : CurveType.flat,
                                padding: EdgeInsets.all(5),
                                bevel: 5,
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: sortBy == "type"
                                      ? Icon(
                                          CupertinoIcons.checkmark_alt,
                                          color: Color(0xffff9813),
                                        )
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 5),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              sortBy = "mtime";
                            });
                          },
                          child: Row(
                            children: [
                              Expanded(
                                child: Text("修改日期"),
                              ),
                              NeuCard(
                                decoration: NeumorphicDecoration(
                                  color:
                                      Theme.of(context).scaffoldBackgroundColor,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                curveType: sortBy == "mtime"
                                    ? CurveType.emboss
                                    : CurveType.flat,
                                padding: EdgeInsets.all(5),
                                bevel: 5,
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: sortBy == "mtime"
                                      ? Icon(
                                          CupertinoIcons.checkmark_alt,
                                          color: Color(0xffff9813),
                                        )
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 5),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              sortBy = "crtime";
                            });
                          },
                          child: Row(
                            children: [
                              Expanded(
                                child: Text("创建日期"),
                              ),
                              NeuCard(
                                decoration: NeumorphicDecoration(
                                  color:
                                      Theme.of(context).scaffoldBackgroundColor,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                curveType: sortBy == "crtime"
                                    ? CurveType.emboss
                                    : CurveType.flat,
                                padding: EdgeInsets.all(5),
                                bevel: 5,
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: sortBy == "crtime"
                                      ? Icon(
                                          CupertinoIcons.checkmark_alt,
                                          color: Color(0xffff9813),
                                        )
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 5),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              sortBy = "atime";
                            });
                          },
                          child: Row(
                            children: [
                              Expanded(
                                child: Text("最近访问时间"),
                              ),
                              NeuCard(
                                decoration: NeumorphicDecoration(
                                  color:
                                      Theme.of(context).scaffoldBackgroundColor,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                curveType: sortBy == "atime"
                                    ? CurveType.emboss
                                    : CurveType.flat,
                                padding: EdgeInsets.all(5),
                                bevel: 5,
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: sortBy == "atime"
                                      ? Icon(
                                          CupertinoIcons.checkmark_alt,
                                          color: Color(0xffff9813),
                                        )
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 5),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              sortBy = "posix";
                            });
                          },
                          child: Row(
                            children: [
                              Expanded(
                                child: Text("权限"),
                              ),
                              NeuCard(
                                decoration: NeumorphicDecoration(
                                  color:
                                      Theme.of(context).scaffoldBackgroundColor,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                curveType: sortBy == "posix"
                                    ? CurveType.emboss
                                    : CurveType.flat,
                                padding: EdgeInsets.all(5),
                                bevel: 5,
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: sortBy == "posix"
                                      ? Icon(
                                          CupertinoIcons.checkmark_alt,
                                          color: Color(0xffff9813),
                                        )
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 5),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              sortBy = "user";
                            });
                          },
                          child: Row(
                            children: [
                              Expanded(
                                child: Text("拥有者"),
                              ),
                              NeuCard(
                                decoration: NeumorphicDecoration(
                                  color:
                                      Theme.of(context).scaffoldBackgroundColor,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                curveType: sortBy == "user"
                                    ? CurveType.emboss
                                    : CurveType.flat,
                                padding: EdgeInsets.all(5),
                                bevel: 5,
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: sortBy == "user"
                                      ? Icon(
                                          CupertinoIcons.checkmark_alt,
                                          color: Color(0xffff9813),
                                        )
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 5),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              sortBy = "group";
                            });
                          },
                          child: Row(
                            children: [
                              Expanded(
                                child: Text("群组"),
                              ),
                              NeuCard(
                                decoration: NeumorphicDecoration(
                                  color:
                                      Theme.of(context).scaffoldBackgroundColor,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                curveType: sortBy == "group"
                                    ? CurveType.emboss
                                    : CurveType.flat,
                                padding: EdgeInsets.all(5),
                                bevel: 5,
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: sortBy == "group"
                                      ? Icon(
                                          CupertinoIcons.checkmark_alt,
                                          color: Color(0xffff9813),
                                        )
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 20,
              ),
              NeuCard(
                curveType: CurveType.flat,
                decoration: NeumorphicDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                bevel: 20,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            sortDirection = "ASC";
                          });
                        },
                        child: Row(
                          children: [
                            Expanded(
                              child: Text("由小至大"),
                            ),
                            NeuCard(
                              decoration: NeumorphicDecoration(
                                color:
                                    Theme.of(context).scaffoldBackgroundColor,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              curveType: sortDirection == "ASC"
                                  ? CurveType.emboss
                                  : CurveType.flat,
                              padding: EdgeInsets.all(5),
                              bevel: 5,
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: sortDirection == "ASC"
                                    ? Icon(
                                        CupertinoIcons.checkmark_alt,
                                        color: Color(0xffff9813),
                                      )
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 5),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            sortDirection = "DESC";
                          });
                        },
                        child: Row(
                          children: [
                            Expanded(
                              child: Text("由大至小"),
                            ),
                            NeuCard(
                              decoration: NeumorphicDecoration(
                                color:
                                    Theme.of(context).scaffoldBackgroundColor,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              curveType: sortDirection == "DESC"
                                  ? CurveType.emboss
                                  : CurveType.flat,
                              padding: EdgeInsets.all(5),
                              bevel: 5,
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: sortDirection == "DESC"
                                    ? Icon(
                                        CupertinoIcons.checkmark_alt,
                                        color: Color(0xffff9813),
                                      )
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                height: 22,
              ),
              NeuButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                },
                decoration: NeumorphicDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(25),
                ),
                bevel: 5,
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  "确定",
                  style: TextStyle(fontSize: 18),
                ),
              ),
              SizedBox(
                height: 8,
              ),
            ],
          ),
        ),
      ),
    );
  }

  deleteFile(List<String> files) {
    Util.vibrate(FeedbackType.warning);
    showCupertinoModalPopup(
      context: context,
      builder: (context) {
        return Material(
          color: Colors.transparent,
          child: NeuCard(
            width: double.infinity,
            padding: EdgeInsets.all(22),
            bevel: 5,
            curveType: CurveType.emboss,
            decoration: NeumorphicDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    "确认删除",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                  ),
                  SizedBox(
                    height: 12,
                  ),
                  Text(
                    "确认要删除文件？",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w400),
                  ),
                  SizedBox(
                    height: 22,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: NeuButton(
                          onPressed: () async {
                            Navigator.of(context).pop();
                            var res = await Api.deleteTask(files);
                            backgroundProcess[res['data']['taskid']] = {
                              "timer": null,
                              "data": {
                                "progress": 0,
                              },
                              "type": 'delete',
                              "path": files,
                            };
                            if (res['success']) {
                              setState(() {
                                selectedFiles = [];
                                multiSelect = false;
                              });
                              getProcessingTaskResult(res['data']['taskid']);
                            }
                          },
                          decoration: NeumorphicDecoration(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            borderRadius: BorderRadius.circular(25),
                          ),
                          bevel: 5,
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Text(
                            "确认删除",
                            style: TextStyle(
                                fontSize: 18, color: Colors.redAccent),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 20,
                      ),
                      Expanded(
                        child: NeuButton(
                          onPressed: () async {
                            Navigator.of(context).pop();
                          },
                          decoration: NeumorphicDecoration(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            borderRadius: BorderRadius.circular(25),
                          ),
                          bevel: 5,
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Text(
                            "取消",
                            style: TextStyle(fontSize: 18),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(
                    height: 8,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  extractFile(file, {String password}) async {
    var res = await Api.extractTask(file['path'], "/" + paths.join("/"),
        password: password);
    if (res['success']) {
      backgroundProcess[res['data']['taskid']] = {
        "timer": null,
        "data": null,
        "type": 'extract',
        "path": [file['path']],
      };
      getProcessingTaskResult(res['data']['taskid']);
    }
  }

  compressFile(List<String> file) {
    String zipName = "";
    String destPath = "";
    if (file.length == 1) {
      zipName = file[0].split("/").last + ".zip";
    } else {
      zipName = paths.last + ".zip";
    }
    destPath = "/" + paths.join("/") + "/" + zipName;
    showCupertinoModalPopup(
      context: context,
      builder: (context) {
        return Material(
          color: Colors.transparent,
          child: NeuCard(
            width: double.infinity,
            padding: EdgeInsets.all(22),
            bevel: 5,
            curveType: CurveType.emboss,
            decoration: NeumorphicDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    "压缩文件",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                  ),
                  SizedBox(
                    height: 12,
                  ),
                  Text(
                    "确认要压缩到$zipName？",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w400),
                  ),
                  SizedBox(
                    height: 22,
                  ),
                  NeuButton(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      var res = await Api.compressTask(file, destPath);
                      if (res['success']) {
                        backgroundProcess[res['data']['taskid']] = {
                          "timer": null,
                          "data": {
                            "dest_folder_path": destPath,
                            "progress": 0,
                          },
                          "path": [file],
                          "type": 'compress',
                        };
                        setState(() {
                          multiSelect = false;
                          selectedFiles = [];
                        });
                        getProcessingTaskResult(res['data']['taskid']);
                      }
                    },
                    decoration: NeumorphicDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    bevel: 5,
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      "开始压缩",
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                  SizedBox(
                    height: 16,
                  ),
                  NeuButton(
                    onPressed: () async {
                      // Navigator.of(context).pop();
                      Util.toast("敬请期待");
                    },
                    decoration: NeumorphicDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    bevel: 5,
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      "更多选项",
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                  SizedBox(
                    height: 16,
                  ),
                  NeuButton(
                    onPressed: () async {
                      Navigator.of(context).pop();
                    },
                    decoration: NeumorphicDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    bevel: 5,
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      "取消",
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                  SizedBox(
                    height: 8,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  openFile(file, {FileTypeEnum fileType, bool remote: false}) async {
    if (multiSelect) {
      setState(() {
        if (selectedFiles.contains(file)) {
          selectedFiles.remove(file);
        } else {
          selectedFiles.add(file);
        }
      });
    } else {
      if (file['isdir']) {
        goPath(file['path']);
        if (remote) {
          Navigator.of(context).pop();
        }
      } else {
        switch (fileType) {
          case FileTypeEnum.image:
            //获取当前目录全部图片文件
            List<String> images = [];
            List<String> thumbs = [];
            List<String> names = [];
            List<String> paths = [];
            int index = 0;
            for (int i = 0; i < files.length; i++) {
              if (Util.fileType(files[i]['name']) == FileTypeEnum.image) {
                images.add(Util.baseUrl +
                    "/webapi/entry.cgi?path=${Uri.encodeComponent(files[i]['path'])}&size=original&api=SYNO.FileStation.Thumb&method=get&version=2&_sid=${Util.sid}&animate=true");
                thumbs.add(Util.baseUrl +
                    "/webapi/entry.cgi?path=${Uri.encodeComponent(files[i]['path'])}&size=small&api=SYNO.FileStation.Thumb&method=get&version=2&_sid=${Util.sid}&animate=true");
                names.add(files[i]['name']);
                paths.add(files[i]['path']);
                if (files[i]['name'] == file['name']) {
                  index = images.length - 1;
                }
              }
            }
            Navigator.of(context).push(TransparentPageRoute(
              pageBuilder: (context, _, __) {
                return ImagePreview(
                  images,
                  index,
                  thumbs: thumbs,
                  names: names,
                  paths: paths,
                  onDelete: () {
                    refresh();
                  },
                );
              },
            ));
            break;
          case FileTypeEnum.movie:
            String videoPlayer = await Util.getStorage("video_player");
            String url = Util.baseUrl +
                "/fbdownload/${Uri.encodeComponent(file['name'])}?dlink=%22${Util.utf8Encode(file['path'])}%22&_sid=%22${Util.sid}%22&mode=open";
            // String url = Util.baseUrl + "/fbdownload/${file['name']}?dlink=%22${Util.utf8Encode(file['path'])}%22&_sid=%22${Util.sid}%22&mode=open";
            // print(url);
            // 调用nplayer
            // launchUrlString("nplayer-http://${Uri.encodeComponent(url)}");
            // 调用vlc player
            // launchUrlString("vlc://$url");
            // return;
            if (videoPlayer != null && videoPlayer == '1') {
              AndroidIntent intent = AndroidIntent(
                action: 'action_view',
                data: url,
                arguments: {},
                type: "video/*",
              );
              await intent.launch();
            } else {
              // 获取封面
              String name = file['name'];
              name = name.substring(0, name.lastIndexOf('.'));
              String cover;
              String nfo;
              try {
                cover = files.firstWhere((element) =>
                    element['name'].startsWith("$name-fanart") ||
                    element['name'].startsWith("fanart"))['path'];
              } catch (e) {
                try {
                  cover = files.firstWhere((element) =>
                      element['name'].startsWith("$name-thumb") ||
                      element['name'].startsWith("thumb"))['path'];
                } catch (e) {
                  try {
                    cover = files.firstWhere((element) =>
                        element['name'].startsWith("$name-poster") ||
                        element['name'].startsWith("poster"))['path'];
                  } catch (e) {
                    try {
                      cover = files.firstWhere((element) =>
                          element['name'].startsWith("$name-cover") ||
                          element['name'].startsWith("cover"))['path'];
                    } catch (e) {
                      debugPrint("无封面图");
                    }
                  }
                }
              }
              try {
                nfo = files.firstWhere(
                    (element) => element['name'] == "$name.nfo")['path'];
              } catch (e) {
                debugPrint("无NFO文件");
              }
              Navigator.of(context).push(CupertinoPageRoute(builder: (context) {
                return VideoPlayer(
                  url: url,
                  name: file['name'],
                  cover: cover,
                  nfo: nfo,
                );
              }));
            }

            break;
          case FileTypeEnum.music:
            initFloating();
            if (audioPlayerFloating.isShowing) {
              audioPlayerFloating.close();
            }
            String url = Util.baseUrl +
                "/fbdownload/${file['name']}?dlink=%22${Util.utf8Encode(file['path'])}%22&_sid=%22${Util.sid}%22&mode=open";
            Navigator.of(context).push(CupertinoPageRoute(builder: (context) {
              return AudioPlayer(
                url: url,
                name: file['name'],
              );
            })).then((_) {
              AudioPlayerProvider audioPlayerProvider =
                  context.read<AudioPlayerProvider>();
              if (audioPlayerProvider.player.playing &&
                  audioPlayerProvider.player.playerState.processingState !=
                      ja.ProcessingState.completed) {
                audioPlayerFloating.open(context);
              }
            });
            break;
          // case FileType.music:
          //   AndroidIntent intent = AndroidIntent(
          //     action: 'action_view',
          //     data: Util.baseUrl + "/webapi/entry.cgi?api=SYNO.FileStation.Download&version=1&method=download&path=${Uri.encodeComponent(file['path'])}&mode=open&_sid=${Util.sid}",
          //     arguments: {},
          //     type: "audio/*",
          //   );
          //   await intent.launch();
          //   break;
          // case FileType.word:
          //   AndroidIntent intent = AndroidIntent(
          //     action: 'action_view',
          //     data: Util.baseUrl + "/webapi/entry.cgi?api=SYNO.FileStation.Download&version=1&method=download&path=${Uri.encodeComponent(file['path'])}&mode=open&_sid=${Util.sid}",
          //     arguments: {},
          //     type: "application/msword|application/vnd.openxmlformats-officedocument.wordprocessingml.document",
          //   );
          //   await intent.launch();
          //   break;
          // case FileType.excel:
          //   AndroidIntent intent = AndroidIntent(
          //     action: 'action_view',
          //     data: Util.baseUrl + "/webapi/entry.cgi?api=SYNO.FileStation.Download&version=1&method=download&path=${Uri.encodeComponent(file['path'])}&mode=open&_sid=${Util.sid}",
          //     arguments: {},
          //     type: "application/vnd.ms-excel|application/x-excel|application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
          //   );
          //   await intent.launch();
          //   break;
          // case FileType.ppt:
          //   AndroidIntent intent = AndroidIntent(
          //     action: 'action_view',
          //     data: Util.baseUrl + "/webapi/entry.cgi?api=SYNO.FileStation.Download&version=1&method=download&path=${Uri.encodeComponent(file['path'])}&mode=open&_sid=${Util.sid}",
          //     arguments: {},
          //     type: "application/vnd.ms-powerpoint|application/vnd.openxmlformats-officedocument.presentationml.presentation",
          //   );
          //   await intent.launch();
          //   break;
          case FileTypeEnum.code:
            openPlainFile(file);
            break;
          case FileTypeEnum.text:
            openPlainFile(file);
            break;
          case FileTypeEnum.pdf:
            Navigator.of(context).push(CupertinoPageRoute(builder: (context) {
              return PdfViewer(
                  Util.baseUrl +
                      "/fbdownload/${file['name']}?dlink=%22${Util.utf8Encode(file['path'])}%22&_sid=%22${Util.sid}%22&mode=open",
                  file['name']);
            }));
            break;
          default:
            AndroidIntent intent = AndroidIntent(
              action: 'action_view',
              data: Util.baseUrl +
                  "/fbdownload/${file['name']}?dlink=%22${Util.utf8Encode(file['path'])}%22&_sid=%22${Util.sid}%22&mode=open",
              arguments: {},
              // type: "application/vnd.ms-powerpoint|application/vnd.openxmlformats-officedocument.presentationml.presentation",
            );
            await intent.launch();
          // Util.toast("暂不支持打开此类型文件");
        }
      }
    }
  }

  fileAction(file, {bool remote: false}) async {
    Util.vibrate(FeedbackType.light);
    showCupertinoModalPopup(
      context: context,
      builder: (context) {
        return Material(
          color: Colors.transparent,
          child: NeuCard(
            width: double.infinity,
            bevel: 5,
            curveType: CurveType.emboss,
            decoration: NeumorphicDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Stack(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "选择操作",
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                        if (!remote)
                          Row(
                            children: [
                              NeuButton(
                                decoration: NeumorphicDecoration(
                                  color:
                                      Theme.of(context).scaffoldBackgroundColor,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: EdgeInsets.all(5),
                                bevel: 5,
                                onPressed: () async {
                                  Navigator.of(context).pop();
                                  setState(() {
                                    selectedFiles.add(file);
                                    multiSelect = true;
                                  });
                                },
                                child: Row(
                                  children: [
                                    Image.asset(
                                      "assets/icons/select_all.png",
                                      width: 20,
                                      height: 20,
                                    ),
                                    SizedBox(
                                      width: 5,
                                    ),
                                    Text("多选"),
                                  ],
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    SizedBox(
                      height: 20,
                    ),
                    Container(
                      width: double.infinity,
                      child: Wrap(
                        runSpacing: 20,
                        spacing: 20,
                        children: [
                          Container(
                            constraints: BoxConstraints(maxWidth: 112),
                            width:
                                (MediaQuery.of(context).size.width - 100) / 4,
                            child: NeuButton(
                              onPressed: () async {
                                Navigator.of(context).pop();
                                Navigator.of(context).push(CupertinoPageRoute(
                                    builder: (context) {
                                      return FileDetail(file);
                                    },
                                    settings:
                                        RouteSettings(name: "file_detail")));
                              },
                              decoration: NeumorphicDecoration(
                                color:
                                    Theme.of(context).scaffoldBackgroundColor,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              bevel: 20,
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: Column(
                                children: [
                                  Image.asset(
                                    "assets/icons/info_liner.png",
                                    width: 30,
                                  ),
                                  Text(
                                    "详情",
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Container(
                            constraints: BoxConstraints(maxWidth: 112),
                            width:
                                (MediaQuery.of(context).size.width - 100) / 4,
                            child: NeuButton(
                              onPressed: () async {
                                Navigator.of(context).pop();
                                downloadFiles([file]);
                              },
                              decoration: NeumorphicDecoration(
                                color:
                                    Theme.of(context).scaffoldBackgroundColor,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              bevel: 20,
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: Column(
                                children: [
                                  Image.asset(
                                    "assets/icons/download.png",
                                    width: 30,
                                  ),
                                  Text(
                                    "下载",
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (Util.fileType(file['name']) == FileTypeEnum.zip &&
                              !remote &&
                              file['path'].startsWith("/"))
                            Container(
                              constraints: BoxConstraints(maxWidth: 112),
                              width:
                                  (MediaQuery.of(context).size.width - 100) / 4,
                              child: NeuButton(
                                onPressed: () async {
                                  Navigator.of(context).pop();
                                  extractFile(file);
                                },
                                decoration: NeumorphicDecoration(
                                  color:
                                      Theme.of(context).scaffoldBackgroundColor,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                bevel: 20,
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: Column(
                                  children: [
                                    Image.asset(
                                      "assets/icons/unzip.png",
                                      width: 30,
                                    ),
                                    Text(
                                      "解压",
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (paths.length > 1 &&
                              !remote &&
                              !remote &&
                              file['path'].startsWith("/"))
                            Container(
                              constraints: BoxConstraints(maxWidth: 112),
                              width:
                                  (MediaQuery.of(context).size.width - 100) / 4,
                              child: NeuButton(
                                onPressed: () async {
                                  Navigator.of(context).pop();
                                  compressFile([file['path']]);
                                },
                                decoration: NeumorphicDecoration(
                                  color:
                                      Theme.of(context).scaffoldBackgroundColor,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                bevel: 20,
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: Column(
                                  children: [
                                    Image.asset(
                                      "assets/icons/archive.png",
                                      width: 30,
                                    ),
                                    Text(
                                      "压缩",
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (!remote &&
                              !remote &&
                              file['path'].startsWith("/"))
                            Container(
                              constraints: BoxConstraints(maxWidth: 112),
                              width:
                                  (MediaQuery.of(context).size.width - 100) / 4,
                              child: NeuButton(
                                onPressed: () async {
                                  Navigator.of(context).pop();
                                  Navigator.of(context).push(CupertinoPageRoute(
                                      builder: (context) {
                                        return Share(paths: [file['path']]);
                                      },
                                      settings: RouteSettings(name: "share")));
                                },
                                decoration: NeumorphicDecoration(
                                  color:
                                      Theme.of(context).scaffoldBackgroundColor,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                bevel: 20,
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: Column(
                                  children: [
                                    Image.asset(
                                      "assets/icons/share.png",
                                      width: 30,
                                    ),
                                    Text(
                                      "共享",
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (file['isdir'] &&
                              !remote &&
                              !remote &&
                              file['path'].startsWith("/")) ...[
                            Container(
                              constraints: BoxConstraints(maxWidth: 112),
                              width:
                                  (MediaQuery.of(context).size.width - 100) / 4,
                              child: NeuButton(
                                onPressed: () async {
                                  Navigator.of(context).pop();
                                  Navigator.of(context).push(CupertinoPageRoute(
                                      builder: (context) {
                                        return Share(
                                          paths: [file['path']],
                                          fileRequest: true,
                                        );
                                      },
                                      settings: RouteSettings(name: "share")));
                                },
                                decoration: NeumorphicDecoration(
                                  color:
                                      Theme.of(context).scaffoldBackgroundColor,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                bevel: 20,
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: Column(
                                  children: [
                                    Image.asset(
                                      "assets/icons/upload.png",
                                      width: 30,
                                    ),
                                    Text(
                                      "文件请求",
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          if (paths.length > 0)
                            Container(
                              constraints: BoxConstraints(maxWidth: 112),
                              width:
                                  (MediaQuery.of(context).size.width - 100) / 4,
                              child: NeuButton(
                                onPressed: () async {
                                  TextEditingController nameController =
                                      TextEditingController.fromValue(
                                          TextEditingValue(text: file['name']));
                                  Navigator.of(context).pop();
                                  String name = "";
                                  showCupertinoDialog(
                                    context: context,
                                    builder: (context) {
                                      return Material(
                                        color: Colors.transparent,
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            NeuCard(
                                              width: double.infinity,
                                              margin: EdgeInsets.symmetric(
                                                  horizontal: 50),
                                              curveType: CurveType.emboss,
                                              bevel: 5,
                                              decoration: NeumorphicDecoration(
                                                color: Theme.of(context)
                                                    .scaffoldBackgroundColor,
                                                borderRadius:
                                                    BorderRadius.circular(25),
                                              ),
                                              child: Padding(
                                                padding: EdgeInsets.all(20),
                                                child: Column(
                                                  children: [
                                                    Text(
                                                      "重命名",
                                                      style: TextStyle(
                                                          fontSize: 20,
                                                          fontWeight:
                                                              FontWeight.w500),
                                                    ),
                                                    SizedBox(
                                                      height: 16,
                                                    ),
                                                    NeuCard(
                                                      decoration:
                                                          NeumorphicDecoration(
                                                        color: Theme.of(context)
                                                            .scaffoldBackgroundColor,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(20),
                                                      ),
                                                      bevel: 20,
                                                      curveType: CurveType.flat,
                                                      padding:
                                                          EdgeInsets.symmetric(
                                                              horizontal: 20,
                                                              vertical: 5),
                                                      child: TextField(
                                                        onChanged: (v) =>
                                                            name = v,
                                                        controller:
                                                            nameController,
                                                        decoration:
                                                            InputDecoration(
                                                          border:
                                                              InputBorder.none,
                                                          hintText: "请输入新的名称",
                                                          labelText: "文件名",
                                                        ),
                                                      ),
                                                    ),
                                                    SizedBox(
                                                      height: 16,
                                                    ),
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: NeuButton(
                                                            onPressed:
                                                                () async {
                                                              if (name.trim() ==
                                                                  "") {
                                                                Util.toast(
                                                                    "请输入新文件名");
                                                                return;
                                                              }
                                                              Navigator.of(
                                                                      context)
                                                                  .pop();
                                                              var res = await Api
                                                                  .rename(
                                                                      file[
                                                                          'path'],
                                                                      name);
                                                              if (res[
                                                                  'success']) {
                                                                Util.toast(
                                                                    "重命名成功");
                                                                refresh();
                                                              } else {
                                                                if (res['error']
                                                                            [
                                                                            'errors'] !=
                                                                        null &&
                                                                    res['error']['errors']
                                                                            .length >
                                                                        0 &&
                                                                    res['error']['errors'][0]
                                                                            [
                                                                            'code'] ==
                                                                        414) {
                                                                  Util.toast(
                                                                      "重命名失败：指定的名称已存在");
                                                                } else {
                                                                  Util.toast(
                                                                      "重命名失败");
                                                                }
                                                              }
                                                            },
                                                            decoration:
                                                                NeumorphicDecoration(
                                                              color: Theme.of(
                                                                      context)
                                                                  .scaffoldBackgroundColor,
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          25),
                                                            ),
                                                            bevel: 20,
                                                            padding: EdgeInsets
                                                                .symmetric(
                                                                    vertical:
                                                                        10),
                                                            child: Text(
                                                              "确定",
                                                              style: TextStyle(
                                                                  fontSize: 18),
                                                            ),
                                                          ),
                                                        ),
                                                        SizedBox(
                                                          width: 16,
                                                        ),
                                                        Expanded(
                                                          child: NeuButton(
                                                            onPressed:
                                                                () async {
                                                              Navigator.of(
                                                                      context)
                                                                  .pop();
                                                            },
                                                            decoration:
                                                                NeumorphicDecoration(
                                                              color: Theme.of(
                                                                      context)
                                                                  .scaffoldBackgroundColor,
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          25),
                                                            ),
                                                            bevel: 20,
                                                            padding: EdgeInsets
                                                                .symmetric(
                                                                    vertical:
                                                                        10),
                                                            child: Text(
                                                              "取消",
                                                              style: TextStyle(
                                                                  fontSize: 18),
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    )
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  );
                                },
                                decoration: NeumorphicDecoration(
                                  color:
                                      Theme.of(context).scaffoldBackgroundColor,
                                  borderRadius: BorderRadius.circular(25),
                                ),
                                bevel: 20,
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: Column(
                                  children: [
                                    Image.asset(
                                      "assets/icons/edit.png",
                                      width: 30,
                                    ),
                                    Text(
                                      "重命名",
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (file['isdir'] &&
                              !remote &&
                              !remote &&
                              file['path'].startsWith("/"))
                            Container(
                              constraints: BoxConstraints(maxWidth: 112),
                              width:
                                  (MediaQuery.of(context).size.width - 100) / 4,
                              child: NeuButton(
                                onPressed: () async {
                                  Navigator.of(context).pop();
                                  var res = await Api.favoriteAdd(
                                      "${file['name']} - ${paths[1]}",
                                      file['path']);
                                  if (res['success']) {
                                    Util.toast("收藏成功");
                                  } else {
                                    Util.toast(
                                        "收藏失败，代码${res['error']['code']}");
                                  }
                                },
                                decoration: NeumorphicDecoration(
                                  color:
                                      Theme.of(context).scaffoldBackgroundColor,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                bevel: 20,
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: Column(
                                  children: [
                                    Image.asset(
                                      "assets/icons/collect.png",
                                      width: 30,
                                    ),
                                    Text(
                                      "添加收藏",
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (file['additional']['mount_point_type'] ==
                                  "remote" &&
                              file['path'].startsWith("/"))
                            Container(
                              constraints: BoxConstraints(maxWidth: 112),
                              width:
                                  (MediaQuery.of(context).size.width - 100) / 4,
                              child: NeuButton(
                                onPressed: () async {
                                  Navigator.of(context).pop();
                                  var res =
                                      await Api.unMountFolder(file['path']);
                                  if (res['success']) {
                                    Util.toast("卸载成功");
                                    refresh();
                                    getSmbFolder();
                                  } else {
                                    Util.toast(
                                        "卸载失败，代码${res['error']['code']}");
                                  }
                                },
                                decoration: NeumorphicDecoration(
                                  color:
                                      Theme.of(context).scaffoldBackgroundColor,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                bevel: 20,
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: Column(
                                  children: [
                                    Image.asset(
                                      "assets/icons/eject.png",
                                      width: 30,
                                    ),
                                    Text(
                                      "卸载",
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (remote && !file['path'].startsWith("/"))
                            Container(
                              constraints: BoxConstraints(maxWidth: 112),
                              width:
                                  (MediaQuery.of(context).size.width - 100) / 4,
                              child: NeuButton(
                                onPressed: () async {
                                  Navigator.of(context).pop();
                                  var res =
                                      await Api.remoteUnConnect(file['path']);
                                  if (res['success']) {
                                    Util.toast("远程连接已断开");
                                    refresh();
                                    getSmbFolder();
                                  } else {
                                    Util.toast(
                                        "断开连接失败，代码${res['error']['code']}");
                                  }
                                },
                                decoration: NeumorphicDecoration(
                                  color:
                                      Theme.of(context).scaffoldBackgroundColor,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                bevel: 20,
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: Column(
                                  children: [
                                    Image.asset(
                                      "assets/icons/eject.png",
                                      width: 30,
                                    ),
                                    Text(
                                      "断开连接",
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (paths.length > 1)
                            Container(
                              constraints: BoxConstraints(maxWidth: 112),
                              width:
                                  (MediaQuery.of(context).size.width - 100) / 4,
                              child: NeuButton(
                                onPressed: () async {
                                  Navigator.of(context).pop();
                                  deleteFile([file['path']]);
                                },
                                decoration: NeumorphicDecoration(
                                  color:
                                      Theme.of(context).scaffoldBackgroundColor,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                bevel: 20,
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: Column(
                                  children: [
                                    Image.asset(
                                      "assets/icons/delete.png",
                                      width: 30,
                                    ),
                                    Text(
                                      "删除",
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.redAccent),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 16,
                    ),
                    NeuButton(
                      onPressed: () async {
                        Navigator.of(context).pop();
                      },
                      decoration: NeumorphicDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        borderRadius: BorderRadius.circular(25),
                      ),
                      bevel: 20,
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        "取消",
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
                    SizedBox(
                      height: 8,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFileItem(file, {bool remote: false}) {
    FileTypeEnum fileType = Util.fileType(file['name']);
    String path = file['path'];
    Widget actionButton = multiSelect
        ? NeuCard(
            decoration: NeumorphicDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(10),
            ),
            curveType: selectedFiles.contains(file)
                ? CurveType.emboss
                : CurveType.flat,
            padding: EdgeInsets.all(5),
            bevel: 5,
            child: SizedBox(
              width: 20,
              height: 20,
              child: selectedFiles.contains(file)
                  ? Icon(
                      CupertinoIcons.checkmark_alt,
                      color: Color(0xffff9813),
                    )
                  : null,
            ),
          )
        : GestureDetector(
            onTap: () {
              fileAction(file, remote: remote);
            },
            child: NeuCard(
              // padding: EdgeInsets.zero,
              curveType: CurveType.flat,
              padding: EdgeInsets.only(left: 6, right: 4, top: 5, bottom: 5),
              decoration: NeumorphicDecoration(
                // color: Colors.red,
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(10),
              ),
              bevel: 10,
              child: Icon(
                CupertinoIcons.right_chevron,
                size: 18,
              ),
            ),
          );
    return Container(
      constraints: listType == ListType.icon && !remote
          ? BoxConstraints(maxWidth: 112)
          : null,
      width: listType == ListType.icon && !remote
          ? (MediaQuery.of(context).size.width - 80) / 3
          : double.infinity,
      padding: listType == ListType.icon && !remote
          ? EdgeInsets.zero
          : EdgeInsets.only(bottom: 20.0),
      child: NeuButton(
        onLongPress: () {
          Util.vibrate(FeedbackType.light);
          fileAction(file, remote: remote);
          // if (paths.length > 1) {
          //   Util.vibrate(FeedbackType.light);
          //   setState(() {
          //     multiSelect = true;
          //     selectedFiles.add(file);
          //   });
          // } else {
          //   Util.vibrate(FeedbackType.warning);
          // }
        },
        onPressed: () {
          openFile(file, fileType: fileType, remote: remote);
        },
        padding: EdgeInsets.zero,
        decoration: NeumorphicDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(20),
        ),
        bevel: 20,
        child: listType == ListType.list || remote
            ? Padding(
                padding: EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    SizedBox(
                      width: 10,
                    ),
                    Hero(
                      tag: Util.baseUrl +
                          "/webapi/entry.cgi?path=${Uri.encodeComponent(path)}&size=original&api=SYNO.FileStation.Thumb&method=get&version=2&_sid=${Util.sid}&animate=true",
                      child: FileIcon(
                        file['isdir'] ? FileTypeEnum.folder : fileType,
                        thumb: file['path'],
                      ),
                    ),
                    SizedBox(
                      width: 10,
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ExtendedText(
                            file['name'],
                            style: TextStyle(
                                fontSize: 14,
                                color: file['additional']['mount_point_type'] ==
                                        "remotefail"
                                    ? AppTheme.of(context).placeholderColor
                                    : null),
                            overflowWidget: TextOverflowWidget(
                              position: TextOverflowPosition.middle,
                              align: TextOverflowAlign.right,
                              child: Text(
                                "…",
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                            maxLines: 2,
                          ),
                          SizedBox(
                            height: 5,
                          ),
                          if (!file['isdir'] && file['additional'] != null ||
                              (file['additional']['time'] != null &&
                                  file['additional']['time']['mtime'] != null))
                            Text.rich(
                              TextSpan(
                                children: [
                                  if (!file['isdir'])
                                    TextSpan(
                                        text:
                                            "${Util.formatSize(file['additional']['size'])}"),
                                  if (file['additional'] != null &&
                                      file['additional']['time'] != null &&
                                      file['additional']['time']['mtime'] !=
                                          null)
                                    TextSpan(
                                      text: (file['isdir'] ? "" : " | ") +
                                          DateTime.fromMillisecondsSinceEpoch(
                                                  file['additional']['time']
                                                          ['mtime'] *
                                                      1000)
                                              .format("Y/m/d H:i:s"),
                                    )
                                ],
                                style: TextStyle(
                                    fontSize: 12,
                                    color:
                                        AppTheme.of(context).placeholderColor),
                              ),
                            ),
                          if (remote)
                            Text(
                              file['path'],
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.of(context).placeholderColor),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 10,
                    ),
                    actionButton,
                    SizedBox(
                      width: 10,
                    ),
                  ],
                ),
              )
            : Stack(
                children: [
                  Align(
                    alignment: Alignment.center,
                    child: Container(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        children: [
                          Hero(
                            tag: Util.baseUrl +
                                "/webapi/entry.cgi?path=${Uri.encodeComponent(path)}&size=original&api=SYNO.FileStation.Thumb&method=get&version=2&_sid=${Util.sid}&animate=true",
                            child: FileIcon(
                              file['isdir'] ? FileTypeEnum.folder : fileType,
                              thumb: file['path'],
                              width:
                                  (MediaQuery.of(context).size.width - 140) / 3,
                              height: 60,
                            ),
                          ),
                          SizedBox(
                            height: 10,
                          ),
                          Text(
                            file['name'],
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (multiSelect)
                    Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.all(10.0),
                        child: actionButton,
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildPathItem(BuildContext context, int index) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: NeuButton(
        onPressed: () {
          String path = "";
          List<String> items = [];
          if (paths.length > 1 && paths[0].contains("//")) {
            debugPrint("远程");
            items = paths.getRange(0, index + 1).toList();
            path = items.join("/");
            goPath(path);
          } else {
            debugPrint("本地");
            items = paths.getRange(0, index + 1).toList();
            path = "/" + items.join("/");
          }
          goPath(path);
        },
        decoration: NeumorphicDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(20),
        ),
        bevel: 5,
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          paths[index],
          style: TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  Future<bool> onWillPop() {
    if (multiSelect) {
      setState(() {
        multiSelect = false;
        selectedFiles = [];
      });
    } else if (searchResult) {
      setState(() {
        refresh();
      });
    } else {
      if (paths.length > 0) {
        paths.removeLast();
        String path = "";
        print(paths);
        if (paths.length > 0 && paths[0].contains("//")) {
          debugPrint("远程");
          path = paths.join("/");
        } else {
          debugPrint("本地");
          path = (paths.length > 0 ? "/" : '') + paths.join("/");
        }
        goPath(path);
      } else {
        return Future.value(true);
      }
    }

    return Future.value(false);
  }

  Widget _buildProcessList() {
    List<Widget> children = [];
    Map<String, String> types = {
      "copy": "复制：",
      "move": "移动：",
      "delete": "删除：",
      "extract": "解压：",
      "compress": "压缩：",
    };
    backgroundProcess.forEach((key, task) {
      var value = task['data'];
      children.add(
        NeuCard(
          curveType: CurveType.flat,
          margin: EdgeInsets.only(left: 20, right: 20, bottom: 20),
          bevel: 10,
          width: double.infinity,
          decoration: NeumorphicDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: types["${task['type'] ?? ''}"],
                      ),
                      TextSpan(
                        text: task['path']
                            .map((e) => e.split("/").last)
                            .join(","),
                        style: TextStyle(
                            color: AppTheme.of(context).placeholderColor),
                      ),
                      if (['copy', 'move', 'achieve', 'compress']
                              .contains(task['type']) &&
                          value != null) ...[
                        TextSpan(
                          text: " 至 ",
                        ),
                        TextSpan(
                          text: value['dest_folder_path'] ?? '',
                          style: TextStyle(
                              color: AppTheme.of(context).placeholderColor),
                        ),
                      ],
                    ],
                  ),
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                SizedBox(
                  height: 10,
                ),
                if (value != null)
                  NeuCard(
                    curveType: CurveType.flat,
                    bevel: 10,
                    decoration: NeumorphicDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: FAProgressBar(
                      backgroundColor: Colors.transparent,
                      changeColorValue: 100,
                      changeProgressColor: Colors.green,
                      progressColor: Colors.blue,
                      size: 20,
                      currentValue:
                          (num.parse("${value['progress']}") * 100).toInt(),
                      displayText: '%',
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    });
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: Row(
          children: [
            Padding(
              padding: EdgeInsets.only(left: 10, top: 8, bottom: 8),
              child: NeuButton(
                decoration: NeumorphicDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: EdgeInsets.all(10),
                bevel: 5,
                onPressed: () async {
                  if (multiSelect) {
                    setState(() {
                      multiSelect = false;
                      selectedFiles = [];
                    });
                  } else {
                    _scaffoldKey.currentState.openDrawer();
                    setState(() {
                      favoriteLoading = true;
                    });
                    var res = await Api.favoriteList();
                    setState(() {
                      favoriteLoading = false;
                    });
                    if (res['success']) {
                      setState(() {
                        favorites = res['data']['favorites'];
                      });
                    }
                  }
                },
                child: multiSelect
                    ? Icon(Icons.close)
                    : Image.asset(
                        "assets/icons/collect.png",
                        width: 20,
                      ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(left: 10, top: 8, bottom: 8),
              child: NeuButton(
                decoration: NeumorphicDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: EdgeInsets.all(10),
                bevel: 5,
                onPressed: () async {
                  showCupertinoModalPopup(
                    context: context,
                    builder: (context) {
                      return Material(
                        color: Colors.transparent,
                        child: NeuCard(
                          width: double.infinity,
                          bevel: 5,
                          curveType: CurveType.emboss,
                          decoration: NeumorphicDecoration(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(22))),
                          child: SafeArea(
                            top: false,
                            child: Padding(
                              padding: EdgeInsets.all(20),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Stack(
                                    children: [
                                      Align(
                                        alignment: Alignment.center,
                                        child: Text(
                                          "远程文件夹",
                                          style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w500),
                                        ),
                                      ),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: Container(
                                          width: 30,
                                          height: 30,
                                          child: NeuButton(
                                            decoration: NeumorphicDecoration(
                                              color: Theme.of(context)
                                                  .scaffoldBackgroundColor,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            padding: EdgeInsets.all(5),
                                            bevel: 5,
                                            onPressed: () async {
                                              Util.toast("重新加载远程连接中");
                                              Navigator.of(context).pop();
                                              getFtpFolder();
                                              getSftpFolder();
                                              getSmbFolder();
                                              getDavFolder();
                                            },
                                            child: Icon(
                                              Icons.refresh,
                                              size: 20,
                                            ),
                                          ),
                                        ),
                                      )
                                    ],
                                  ),
                                  SizedBox(
                                    height: 20,
                                  ),
                                  Container(
                                    constraints: BoxConstraints(
                                      minHeight: 50,
                                      maxHeight:
                                          MediaQuery.of(context).size.height *
                                              0.8,
                                    ),
                                    child: SingleChildScrollView(
                                      child: Column(
                                        children: [
                                          if ((smbFolders +
                                                      ftpFolders +
                                                      sftpFolders +
                                                      davFolders)
                                                  .length >
                                              0) ...[
                                            ...(smbFolders +
                                                    ftpFolders +
                                                    sftpFolders +
                                                    davFolders)
                                                .map((folder) {
                                              return _buildFileItem(folder,
                                                  remote: true);
                                            }).toList(),
                                          ] else
                                            Center(
                                              child: Text(
                                                "未挂载远程文件夹",
                                                style: TextStyle(
                                                    color: AppTheme.of(context)
                                                        .placeholderColor),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    height: 16,
                                  ),
                                  NeuButton(
                                    onPressed: () async {
                                      Navigator.of(context).pop();
                                    },
                                    decoration: NeumorphicDecoration(
                                      color: Theme.of(context)
                                          .scaffoldBackgroundColor,
                                      borderRadius: BorderRadius.circular(25),
                                    ),
                                    bevel: 20,
                                    padding: EdgeInsets.symmetric(vertical: 10),
                                    child: Text(
                                      "取消",
                                      style: TextStyle(fontSize: 18),
                                    ),
                                  ),
                                  SizedBox(
                                    height: 8,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
                child: Image.asset(
                  "assets/icons/remote.png",
                  width: 20,
                ),
              ),
            ),
            if (Util.notReviewAccount && paths.length > 0 && !multiSelect)
              Padding(
                padding: EdgeInsets.only(left: 10, top: 8, bottom: 8),
                child: NeuButton(
                  decoration: NeumorphicDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: EdgeInsets.all(10),
                  bevel: 5,
                  onPressed: () async {
                    Navigator.of(context)
                        .push(CupertinoPageRoute(
                            builder: (context) {
                              return Upload("/" + paths.join("/"));
                            },
                            settings: RouteSettings(name: "upload")))
                        .then((value) {
                      refresh();
                    });
                  },
                  child: Image.asset(
                    "assets/icons/upload.png",
                    width: 20,
                  ),
                ),
              ),
            if (backgroundProcess.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(left: 10, top: 8, bottom: 8),
                child: NeuButton(
                  decoration: NeumorphicDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: EdgeInsets.all(10),
                  bevel: 5,
                  onPressed: () async {
                    setState(() {
                      showProcessList = !showProcessList;
                    });
                  },
                  child: Image.asset(
                    "assets/icons/bgtask.gif",
                    width: 20,
                  ),
                ),
              ),
            Spacer(),
            if (paths.length > 0)
              Padding(
                padding: EdgeInsets.only(right: 10, top: 8, bottom: 8),
                child: NeuButton(
                  onPressed: () async {
                    Navigator.of(context)
                        .push(CupertinoPageRoute(
                            builder: (content) {
                              return Search("/" + paths.join("/"));
                            },
                            settings: RouteSettings(name: "search")))
                        .then((res) {
                      if (res != null) {
                        search(res['folders'], res['pattern'],
                            res['search_content']);
                      }
                    });
                  },
                  decoration: NeumorphicDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  bevel: 5,
                  padding: EdgeInsets.all(10),
                  child: Image.asset(
                    "assets/icons/search.png",
                    width: 20,
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.only(right: 10, top: 8, bottom: 8),
              child: NeuButton(
                decoration: NeumorphicDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: EdgeInsets.all(10),
                bevel: 5,
                onPressed: () {
                  setState(() {
                    listType = listType == ListType.list
                        ? ListType.icon
                        : ListType.list;
                  });
                  Util.setStorage("file_list_type",
                      listType == ListType.list ? "list" : "icon");
                },
                child: Image.asset(
                  listType == ListType.list
                      ? "assets/icons/list_list.png"
                      : "assets/icons/list_icon.png",
                  width: 20,
                  height: 20,
                ),
              ),
            ),
            if (multiSelect)
              Padding(
                padding: EdgeInsets.only(right: 10, top: 8, bottom: 8),
                child: NeuButton(
                  decoration: NeumorphicDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: EdgeInsets.all(10),
                  bevel: 5,
                  onPressed: () {
                    if (selectedFiles.length == files.length) {
                      selectedFiles = [];
                    } else {
                      selectedFiles = [];
                      files.forEach((file) {
                        selectedFiles.add(file);
                      });
                    }

                    setState(() {});
                  },
                  child: Image.asset(
                    "assets/icons/select_all.png",
                    width: 20,
                    height: 20,
                  ),
                ),
              )
            else if (paths.length > 1)
              Padding(
                padding: EdgeInsets.only(right: 10, top: 8, bottom: 8),
                child: NeuButton(
                  decoration: NeumorphicDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: EdgeInsets.all(10),
                  bevel: 5,
                  onPressed: () {
                    showCupertinoModalPopup(
                      context: context,
                      builder: (context) {
                        return StatefulBuilder(
                          builder: _buildSortMenu,
                        );
                      },
                    ).then((value) {
                      refresh();
                    });
                  },
                  child: Image.asset(
                    "assets/icons/sort.png",
                    width: 20,
                    height: 20,
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.only(right: 10, top: 8, bottom: 8),
              child: NeuButton(
                decoration: NeumorphicDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: EdgeInsets.all(10),
                bevel: 5,
                onPressed: () {
                  showCupertinoModalPopup(
                    context: context,
                    builder: (context) {
                      return Material(
                        color: Colors.transparent,
                        child: NeuCard(
                          width: double.infinity,
                          bevel: 20,
                          curveType: CurveType.emboss,
                          decoration: NeumorphicDecoration(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(22))),
                          child: SafeArea(
                            top: false,
                            child: Padding(
                              padding: EdgeInsets.all(20),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Text(
                                    "选择操作",
                                    style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w500),
                                  ),
                                  SizedBox(
                                    height: 12,
                                  ),
                                  Container(
                                    width: double.infinity,
                                    child: Wrap(
                                      runSpacing: 20,
                                      spacing: 20,
                                      children: [
                                        if (paths.length == 0) ...[
                                          Container(
                                            constraints:
                                                BoxConstraints(maxWidth: 112),
                                            width: (MediaQuery.of(context)
                                                        .size
                                                        .width -
                                                    100) /
                                                4,
                                            child: NeuButton(
                                              onPressed: () async {
                                                Navigator.of(context).pop();
                                                List volumes =
                                                    await getVolumes();
                                                if (volumes != null &&
                                                    volumes.length > 0) {
                                                  Navigator.of(context)
                                                      .push(CupertinoPageRoute(
                                                          builder: (context) {
                                                            return AddSharedFolders(
                                                                volumes);
                                                          },
                                                          settings: RouteSettings(
                                                              name:
                                                                  "add_shared_folders")))
                                                      .then((res) {
                                                    if (res != null && res) {
                                                      refresh();
                                                    }
                                                  });
                                                } else {
                                                  Util.toast("未获取到存储空间");
                                                }
                                              },
                                              decoration: NeumorphicDecoration(
                                                color: Theme.of(context)
                                                    .scaffoldBackgroundColor,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              bevel: 20,
                                              padding: EdgeInsets.symmetric(
                                                  vertical: 10),
                                              child: Column(
                                                children: [
                                                  Image.asset(
                                                    "assets/icons/new_folder.png",
                                                    width: 30,
                                                  ),
                                                  Text(
                                                    "共享文件夹",
                                                    style:
                                                        TextStyle(fontSize: 12),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                        if (paths.length > 0) ...[
                                          Container(
                                            constraints:
                                                BoxConstraints(maxWidth: 112),
                                            width: (MediaQuery.of(context)
                                                        .size
                                                        .width -
                                                    100) /
                                                4,
                                            child: NeuButton(
                                              onPressed: () async {
                                                Navigator.of(context).pop();
                                                String name = "";
                                                showCupertinoDialog(
                                                    context: context,
                                                    builder: (context) {
                                                      return Material(
                                                        color:
                                                            Colors.transparent,
                                                        child: Column(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .center,
                                                          children: [
                                                            NeuCard(
                                                              width: double
                                                                  .infinity,
                                                              margin: EdgeInsets
                                                                  .symmetric(
                                                                      horizontal:
                                                                          50),
                                                              curveType:
                                                                  CurveType
                                                                      .emboss,
                                                              bevel: 5,
                                                              decoration:
                                                                  NeumorphicDecoration(
                                                                color: Theme.of(
                                                                        context)
                                                                    .scaffoldBackgroundColor,
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            25),
                                                              ),
                                                              child: Padding(
                                                                padding:
                                                                    EdgeInsets
                                                                        .all(
                                                                            20),
                                                                child: Column(
                                                                  children: [
                                                                    Text(
                                                                      "新建文件夹",
                                                                      style: TextStyle(
                                                                          fontSize:
                                                                              20,
                                                                          fontWeight:
                                                                              FontWeight.w500),
                                                                    ),
                                                                    SizedBox(
                                                                      height:
                                                                          16,
                                                                    ),
                                                                    NeuCard(
                                                                      decoration:
                                                                          NeumorphicDecoration(
                                                                        color: Theme.of(context)
                                                                            .scaffoldBackgroundColor,
                                                                        borderRadius:
                                                                            BorderRadius.circular(20),
                                                                      ),
                                                                      bevel: 20,
                                                                      curveType:
                                                                          CurveType
                                                                              .flat,
                                                                      padding: EdgeInsets.symmetric(
                                                                          horizontal:
                                                                              20,
                                                                          vertical:
                                                                              5),
                                                                      child:
                                                                          TextField(
                                                                        onChanged:
                                                                            (v) =>
                                                                                name = v,
                                                                        decoration:
                                                                            InputDecoration(
                                                                          border:
                                                                              InputBorder.none,
                                                                          hintText:
                                                                              "请输入文件夹名",
                                                                          labelText:
                                                                              "文件夹名",
                                                                        ),
                                                                      ),
                                                                    ),
                                                                    SizedBox(
                                                                      height:
                                                                          20,
                                                                    ),
                                                                    Row(
                                                                      children: [
                                                                        Expanded(
                                                                          child:
                                                                              NeuButton(
                                                                            onPressed:
                                                                                () async {
                                                                              if (name.trim() == "") {
                                                                                Util.toast("请输入文件夹名");
                                                                                return;
                                                                              }
                                                                              Navigator.of(context).pop();
                                                                              String path = "/" + paths.join("/");
                                                                              var res = await Api.createFolder(path, name);
                                                                              if (res['success']) {
                                                                                Util.toast("文件夹创建成功");
                                                                                refresh();
                                                                              } else {
                                                                                if (res['error']['errors'] != null && res['error']['errors'].length > 0 && res['error']['errors'][0]['code'] == 414) {
                                                                                  Util.toast("文件夹创建失败：指定的名称已存在");
                                                                                } else {
                                                                                  Util.toast("文件夹创建失败");
                                                                                }
                                                                              }
                                                                            },
                                                                            decoration:
                                                                                NeumorphicDecoration(
                                                                              color: Theme.of(context).scaffoldBackgroundColor,
                                                                              borderRadius: BorderRadius.circular(25),
                                                                            ),
                                                                            bevel:
                                                                                20,
                                                                            padding:
                                                                                EdgeInsets.symmetric(vertical: 10),
                                                                            child:
                                                                                Text(
                                                                              "确定",
                                                                              style: TextStyle(fontSize: 18),
                                                                            ),
                                                                          ),
                                                                        ),
                                                                        SizedBox(
                                                                          width:
                                                                              16,
                                                                        ),
                                                                        Expanded(
                                                                          child:
                                                                              NeuButton(
                                                                            onPressed:
                                                                                () async {
                                                                              Navigator.of(context).pop();
                                                                            },
                                                                            decoration:
                                                                                NeumorphicDecoration(
                                                                              color: Theme.of(context).scaffoldBackgroundColor,
                                                                              borderRadius: BorderRadius.circular(25),
                                                                            ),
                                                                            bevel:
                                                                                20,
                                                                            padding:
                                                                                EdgeInsets.symmetric(vertical: 10),
                                                                            child:
                                                                                Text(
                                                                              "取消",
                                                                              style: TextStyle(fontSize: 18),
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      ],
                                                                    )
                                                                  ],
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    });
                                              },
                                              decoration: NeumorphicDecoration(
                                                color: Theme.of(context)
                                                    .scaffoldBackgroundColor,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              bevel: 20,
                                              padding: EdgeInsets.symmetric(
                                                  vertical: 10),
                                              child: Column(
                                                children: [
                                                  Image.asset(
                                                    "assets/icons/new_folder.png",
                                                    width: 30,
                                                  ),
                                                  Text(
                                                    "新建文件夹",
                                                    style:
                                                        TextStyle(fontSize: 12),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          SizedBox(
                                            width: (MediaQuery.of(context)
                                                        .size
                                                        .width -
                                                    100) /
                                                4,
                                            child: NeuButton(
                                              onPressed: () async {
                                                Navigator.of(context).pop();
                                                Navigator.of(context).push(
                                                    CupertinoPageRoute(
                                                        builder: (context) {
                                                          return Share(
                                                            paths: [
                                                              "/" +
                                                                  paths
                                                                      .join("/")
                                                            ],
                                                            fileRequest: true,
                                                          );
                                                        },
                                                        settings: RouteSettings(
                                                            name: "share")));
                                              },
                                              decoration: NeumorphicDecoration(
                                                color: Theme.of(context)
                                                    .scaffoldBackgroundColor,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              bevel: 20,
                                              padding: EdgeInsets.symmetric(
                                                  vertical: 10),
                                              child: Column(
                                                children: [
                                                  Image.asset(
                                                    "assets/icons/upload.png",
                                                    width: 30,
                                                  ),
                                                  Text(
                                                    "创建文件请求",
                                                    style:
                                                        TextStyle(fontSize: 12),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                        Container(
                                          constraints:
                                              BoxConstraints(maxWidth: 112),
                                          width: (MediaQuery.of(context)
                                                      .size
                                                      .width -
                                                  100) /
                                              4,
                                          child: NeuButton(
                                            onPressed: () async {
                                              Navigator.of(context).pop();
                                              Navigator.of(context).push(
                                                  CupertinoPageRoute(
                                                      builder: (content) {
                                                        return ShareManager();
                                                      },
                                                      settings: RouteSettings(
                                                          name:
                                                              "share_manager")));
                                            },
                                            decoration: NeumorphicDecoration(
                                              color: Theme.of(context)
                                                  .scaffoldBackgroundColor,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            bevel: 20,
                                            padding: EdgeInsets.symmetric(
                                                vertical: 10),
                                            child: Column(
                                              children: [
                                                Image.asset(
                                                  "assets/icons/link.png",
                                                  width: 30,
                                                ),
                                                Text(
                                                  "共享链接管理",
                                                  style:
                                                      TextStyle(fontSize: 12),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        Container(
                                          constraints:
                                              BoxConstraints(maxWidth: 112),
                                          width: (MediaQuery.of(context)
                                                      .size
                                                      .width -
                                                  100) /
                                              4,
                                          child: NeuButton(
                                            onPressed: () async {
                                              Navigator.of(context).pop();
                                              Navigator.of(context)
                                                  .push(CupertinoPageRoute(
                                                      builder: (content) {
                                                        return RemoteFolder();
                                                      },
                                                      settings: RouteSettings(
                                                          name:
                                                              "remote_folder")))
                                                  .then((res) {
                                                refresh();
                                                getSmbFolder();
                                              });
                                            },
                                            decoration: NeumorphicDecoration(
                                              color: Theme.of(context)
                                                  .scaffoldBackgroundColor,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            bevel: 20,
                                            padding: EdgeInsets.symmetric(
                                                vertical: 10),
                                            child: Column(
                                              children: [
                                                Image.asset(
                                                  "assets/icons/remote.png",
                                                  width: 30,
                                                ),
                                                Text(
                                                  "装载远程",
                                                  style:
                                                      TextStyle(fontSize: 12),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        // if (paths.length > 0)
                                        //   Container(
                                        //     constraints: BoxConstraints(maxWidth: 112),
                                        //     width: (MediaQuery.of(context).size.width - 100) / 4,
                                        //     child: NeuButton(
                                        //       onPressed: () async {
                                        //         Navigator.of(context).pop();
                                        //         Navigator.of(context)
                                        //             .push(CupertinoPageRoute(
                                        //                 builder: (content) {
                                        //                   return Search("/" + paths.join("/"));
                                        //                 },
                                        //                 settings: RouteSettings(name: "search")))
                                        //             .then((res) {
                                        //           if (res != null) {
                                        //             search(res['folders'], res['pattern'], res['search_content']);
                                        //           }
                                        //         });
                                        //       },
                                        //       decoration: NeumorphicDecoration(
                                        //         color: Theme.of(context).scaffoldBackgroundColor,
                                        //         borderRadius: BorderRadius.circular(10),
                                        //       ),
                                        //       bevel: 20,
                                        //       padding: EdgeInsets.symmetric(vertical: 10),
                                        //       child: Column(
                                        //         children: [
                                        //           Image.asset(
                                        //             "assets/icons/search.png",
                                        //             width: 30,
                                        //           ),
                                        //           Text(
                                        //             "搜索",
                                        //             style: TextStyle(fontSize: 12),
                                        //           ),
                                        //         ],
                                        //       ),
                                        //     ),
                                        //   ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(
                                    height: 20,
                                  ),
                                  NeuButton(
                                    onPressed: () async {
                                      Navigator.of(context).pop();
                                    },
                                    decoration: NeumorphicDecoration(
                                      color: Theme.of(context)
                                          .scaffoldBackgroundColor,
                                      borderRadius: BorderRadius.circular(25),
                                    ),
                                    bevel: 20,
                                    padding: EdgeInsets.symmetric(vertical: 10),
                                    child: Text(
                                      "取消",
                                      style: TextStyle(fontSize: 18),
                                    ),
                                  ),
                                  SizedBox(
                                    height: 8,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
                child: Image.asset(
                  "assets/icons/actions.png",
                  width: 20,
                  height: 20,
                ),
              ),
            )
          ],
        ),
      ),
      body: Column(
        children: [
          if (searchResult)
            Container(
              height: 45,
              color: Theme.of(context).scaffoldBackgroundColor,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Container(
                    margin: EdgeInsets.only(left: 20),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: NeuCard(
                      decoration: NeumorphicDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      bevel: 5,
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      child: Text(
                        "搜索结果",
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  Spacer(),
                  GestureDetector(
                    onTap: () {
                      searchTimer?.cancel();
                      setState(() {
                        searching = false;
                        searchResult = false;
                        refresh();
                      });
                    },
                    child: Container(
                      margin: EdgeInsets.only(right: 20),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: NeuCard(
                        decoration: NeumorphicDecoration(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        bevel: 5,
                        curveType: CurveType.flat,
                        padding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        child: searching
                            ? Row(
                                children: [
                                  Text(
                                    "搜索中",
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  SizedBox(
                                    width: 5,
                                  ),
                                  CupertinoActivityIndicator(
                                    radius: 6,
                                  ),
                                ],
                              )
                            : Text(
                                "退出搜索",
                                style: TextStyle(fontSize: 12),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              height: 45,
              color: Theme.of(context).scaffoldBackgroundColor,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.only(left: 20, top: 10, bottom: 10),
                    child: NeuButton(
                      onPressed: () {
                        goPath("");
                      },
                      decoration: NeumorphicDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      bevel: 5,
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      child: Icon(
                        CupertinoIcons.home,
                        size: 16,
                      ),
                    ),
                  ),
                  if (paths.length > 0)
                    Container(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Icon(
                        CupertinoIcons.right_chevron,
                        size: 14,
                      ),
                    ),
                  Expanded(
                    child: ListView.separated(
                      controller: _pathScrollController,
                      itemBuilder: _buildPathItem,
                      itemCount: paths.length,
                      scrollDirection: Axis.horizontal,
                      separatorBuilder: (context, i) {
                        return Container(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Icon(
                            CupertinoIcons.right_chevron,
                            size: 14,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          if (backgroundProcess.isNotEmpty && showProcessList)
            _buildProcessList(),
          Expanded(
            child: success
                ? Stack(
                    children: [
                      listType == ListType.list
                          ? DraggableScrollbar.semicircle(
                              backgroundColor:
                                  Theme.of(context).scaffoldBackgroundColor,
                              scrollbarTimeToFade: Duration(seconds: 1),
                              controller: _fileScrollController,
                              child: ListView.builder(
                                controller: _fileScrollController,
                                padding: EdgeInsets.only(
                                    left: 20,
                                    right: 20,
                                    top: 20,
                                    bottom:
                                        selectedFiles.length > 0 ? 140 : 20),
                                itemBuilder: (context, i) {
                                  return _buildFileItem(files[i]);
                                },
                                itemCount: files.length,
                              ),
                            )
                          : Container(
                              width: double.infinity,
                              child: DraggableScrollbar.semicircle(
                                backgroundColor:
                                    Theme.of(context).scaffoldBackgroundColor,
                                scrollbarTimeToFade: Duration(seconds: 1),
                                controller: _fileScrollController,
                                child: ListView(
                                  controller: _fileScrollController,
                                  padding: EdgeInsets.all(20),
                                  children: [
                                    Wrap(
                                      runSpacing: 20,
                                      spacing: 20,
                                      children:
                                          files.map(_buildFileItem).toList(),
                                    )
                                  ],
                                ),
                              ),
                            ),
                      // if (selectedFiles.length > 0)
                      AnimatedPositioned(
                        bottom: selectedFiles.length > 0 ? 0 : -100,
                        duration: Duration(milliseconds: 200),
                        child: NeuCard(
                          width: MediaQuery.of(context).size.width - 40,
                          margin: EdgeInsets.all(20),
                          padding: EdgeInsets.all(10),
                          height: 62,
                          bevel: 20,
                          curveType: CurveType.flat,
                          decoration: NeumorphicDecoration(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  showCupertinoModalPopup(
                                    context: context,
                                    builder: (context) {
                                      return SelectFolder(
                                        multi: false,
                                      );
                                    },
                                  ).then((folder) async {
                                    if (folder != null && folder.length == 1) {
                                      List<String> files = selectedFiles
                                          .map((e) => e['path'] as String)
                                          .toList();
                                      var res = await Api.copyMoveTask(
                                          files, folder[0], true);
                                      if (res['success']) {
                                        setState(() {
                                          selectedFiles = [];
                                          multiSelect = false;
                                          backgroundProcess[res['data']
                                              ['taskid']] = {
                                            "timer": null,
                                            "data": {
                                              "dest_folder_path": folder[0],
                                              "progress": 0,
                                            },
                                            "type": 'move',
                                            "path": files,
                                          };
                                        });
                                        //获取移动进度
                                        getProcessingTaskResult(
                                            res['data']['taskid']);
                                      }
                                    }
                                  });
                                },
                                child: Column(
                                  children: [
                                    Image.asset(
                                      "assets/icons/move.png",
                                      width: 25,
                                    ),
                                    Text(
                                      "移动到",
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  showCupertinoModalPopup(
                                    context: context,
                                    builder: (context) {
                                      return SelectFolder(
                                        multi: false,
                                      );
                                    },
                                  ).then((folder) async {
                                    if (folder != null && folder.length == 1) {
                                      List<String> files = selectedFiles
                                          .map((e) => e['path'] as String)
                                          .toList();
                                      var res = await Api.copyMoveTask(
                                          files, folder[0], false);
                                      if (res['success']) {
                                        setState(() {
                                          selectedFiles = [];
                                          multiSelect = false;
                                          backgroundProcess[res['data']
                                              ['taskid']] = {
                                            "timer": null,
                                            "data": {
                                              "dest_folder_path": folder[0],
                                              "progress": 0,
                                            },
                                            "type": "copy",
                                            "path": files,
                                          };
                                        });
                                        getProcessingTaskResult(
                                            res['data']['taskid']);
                                      }
                                    }
                                  });
                                },
                                child: Column(
                                  children: [
                                    Image.asset(
                                      "assets/icons/copy.png",
                                      width: 25,
                                    ),
                                    Text(
                                      "复制到",
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  compressFile(selectedFiles
                                      .map((e) => e['path'] as String)
                                      .toList());
                                },
                                child: Column(
                                  children: [
                                    Image.asset(
                                      "assets/icons/archive.png",
                                      width: 25,
                                    ),
                                    Text(
                                      "压缩",
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  downloadFiles(selectedFiles);
                                },
                                child: Column(
                                  children: [
                                    Image.asset(
                                      "assets/icons/download.png",
                                      width: 25,
                                    ),
                                    Text(
                                      "下载",
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  deleteFile(selectedFiles
                                      .map((e) => e['path'] as String)
                                      .toList());
                                },
                                child: Column(
                                  children: [
                                    Image.asset(
                                      "assets/icons/delete.png",
                                      width: 25,
                                    ),
                                    Text(
                                      "删除",
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (loading)
                        Container(
                          width: MediaQuery.of(context).size.width,
                          height: MediaQuery.of(context).size.height,
                          color: Theme.of(context)
                              .scaffoldBackgroundColor
                              .withOpacity(0.7),
                          child: Center(
                            child: NeuCard(
                              padding: EdgeInsets.all(50),
                              curveType: CurveType.flat,
                              decoration: NeumorphicDecoration(
                                color:
                                    Theme.of(context).scaffoldBackgroundColor,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              bevel: 20,
                              child: CupertinoActivityIndicator(
                                radius: 14,
                              ),
                            ),
                          ),
                        ),
                    ],
                  )
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "$msg",
                          style: TextStyle(
                              color: AppTheme.of(context).placeholderColor),
                        ),
                        SizedBox(
                          height: 20,
                        ),
                        SizedBox(
                          width: 200,
                          child: NeuButton(
                            padding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 10),
                            decoration: NeumorphicDecoration(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            bevel: 5,
                            onPressed: () {
                              refresh();
                            },
                            child: Text(
                              ' 刷新 ',
                              style: TextStyle(fontSize: 18),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      drawer: Favorite(goPath),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      // floatingActionButton: FloatingActionButton(
      //   child: Icon(Icons.refresh),
      //   onPressed: getBackgroundTask,
      // ),
    );
  }
}
