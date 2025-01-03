import 'package:dsm_helper/providers/shortcut.dart';
import 'package:dsm_helper/providers/wallpaper.dart';
import 'package:dsm_helper/util/function.dart';
import 'package:dsm_helper/widgets/neu_back_button.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:neumorphic/neumorphic.dart';
import 'package:provider/provider.dart';

class WidgetSetting extends StatefulWidget {
  final List widgets;
  final Map restoreSizePos;
  WidgetSetting(this.widgets, this.restoreSizePos);
  @override
  _WidgetSettingState createState() => _WidgetSettingState();
}

class _WidgetSettingState extends State<WidgetSetting> {
  bool showShortcut = true;
  bool showWallpaper = true;
  List<String> allWidgets = [
    // "SYNO.SDS.SystemInfoApp.FileChangeLogWidget",
    "SYNO.SDS.SystemInfoApp.SystemHealthWidget",
    "SYNO.SDS.ResourceMonitor.Widget",
    "SYNO.SDS.SystemInfoApp.StorageUsageWidget",
    "SYNO.SDS.SystemInfoApp.ConnectionLogWidget",
    "SYNO.SDS.TaskScheduler.TaskSchedulerWidget",
    "SYNO.SDS.SystemInfoApp.FileChangeLogWidget",
    "SYNO.SDS.SystemInfoApp.RecentLogWidget",
  ];
  Map name = {
    "SYNO.SDS.SystemInfoApp.FileChangeLogWidget": "文件更改日志",
    "SYNO.SDS.SystemInfoApp.RecentLogWidget": "最新日志",
    "SYNO.SDS.TaskScheduler.TaskSchedulerWidget": "计划任务",
    "SYNO.SDS.SystemInfoApp.SystemHealthWidget": "系统状况",
    "SYNO.SDS.SystemInfoApp.ConnectionLogWidget": "目前连接用户",
    "SYNO.SDS.SystemInfoApp.StorageUsageWidget": "存储",
    "SYNO.SDS.ResourceMonitor.Widget": "资源监控",
  };
  List showWidgets = [];
  List selectedWidgets = [];
  @override
  void initState() {
    Util.getStorage("show_shortcut").then((showShortcutStr) {
      setState(() {
        if (showShortcutStr != null) {
          showShortcut = showShortcutStr == "1";
        } else {
          showShortcut = true;
        }
      });
    });
    Util.getStorage("show_wallpaper").then((showWallpaperStr) {
      setState(() {
        if (showWallpaperStr != null) {
          showWallpaper = showWallpaperStr == "1";
        } else {
          showWallpaper = true;
        }
      });
    });
    setState(() {
      selectedWidgets.addAll(widget.widgets);
      showWidgets.addAll(widget.widgets);
    });
    allWidgets.forEach((widget) {
      if (!showWidgets.contains(widget)) {
        setState(() {
          showWidgets.add(widget);
        });
      }
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: AppBackButton(context),
        title: Text("小组件设置"),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: 10, top: 8, bottom: 8),
            child: NeuButton(
              decoration: NeumorphicDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(10),
              ),
              padding: EdgeInsets.all(10),
              bevel: 5,
              onPressed: () async {
                List saveWidgets = [];
                showWidgets.forEach((widget) {
                  if (selectedWidgets.contains(widget)) {
                    saveWidgets.add(widget);
                  }
                });
                Map data = {
                  "SYNO.SDS._Widget.Instance": {"modulelist": saveWidgets},
                  // "restoreSizePos": widget.restoreSizePos
                };
                var res = await Api.userSetting(data);
                if (res['success']) {
                  Util.toast("保存小组件成功");
                  Navigator.of(context).pop(saveWidgets);
                } else {
                  Util.toast("保存小组件失败，代码${res['error']['code']}");
                }
              },
              child: Image.asset(
                "assets/icons/save.png",
                width: 20,
                height: 20,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  setState(() {
                    showShortcut = !showShortcut;
                    Provider.of<ShortcutProvider>(context, listen: false)
                        .changeMode(showShortcut);
                  });
                });
              },
              child: NeuCard(
                decoration: NeumorphicDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                curveType: showShortcut ? CurveType.emboss : CurveType.flat,
                bevel: 20,
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Image.asset(
                            "assets/icons/shortcut.png",
                            width: 30,
                          ),
                          SizedBox(
                            width: 8,
                          ),
                          Text(
                            "控制台快捷方式",
                            style: TextStyle(fontSize: 16),
                          ),
                          Spacer(),
                          if (showShortcut)
                            Icon(
                              CupertinoIcons.checkmark_alt,
                              color: Color(0xffff9813),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  setState(() {
                    showWallpaper = !showWallpaper;
                    Provider.of<WallpaperProvider>(context, listen: false)
                        .changeMode(showWallpaper);
                  });
                });
              },
              child: NeuCard(
                decoration: NeumorphicDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                curveType: showWallpaper ? CurveType.emboss : CurveType.flat,
                bevel: 20,
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Image.asset(
                            "assets/icons/wallpaper.png",
                            width: 30,
                          ),
                          SizedBox(
                            width: 8,
                          ),
                          Text(
                            "系统状态显示壁纸",
                            style: TextStyle(fontSize: 16),
                          ),
                          Spacer(),
                          if (showWallpaper)
                            Icon(
                              CupertinoIcons.checkmark_alt,
                              color: Color(0xffff9813),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 20,
          ),
          Expanded(
            child: ReorderableListView(
              children: showWidgets.map((widget) {
                return GestureDetector(
                  key: ValueKey(widget),
                  onTap: () {
                    setState(() {
                      if (selectedWidgets.contains(widget)) {
                        selectedWidgets.remove(widget);
                      } else {
                        selectedWidgets.add(widget);
                      }
                      print(showWidgets);
                    });
                  },
                  child: NeuCard(
                    margin: EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                    curveType: CurveType.flat,
                    decoration: NeumorphicDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    bevel: 20,
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              name[widget],
                              style: TextStyle(fontSize: 16),
                            ),
                          ),
                          NeuCard(
                            decoration: NeumorphicDecoration(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            curveType: selectedWidgets.contains(widget)
                                ? CurveType.emboss
                                : CurveType.flat,
                            padding: EdgeInsets.all(5),
                            bevel: 5,
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: selectedWidgets.contains(widget)
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
                  ),
                );
              }).toList(),
              onReorder: (int oldIndex, int newIndex) {
                if (oldIndex < newIndex) {
                  newIndex -= 1;
                }
                var child = showWidgets.removeAt(oldIndex);
                showWidgets.insert(newIndex, child);

                setState(() {});
              },
            ),
          ),
        ],
      ),
    );
  }
}
