import 'package:dsm_helper/util/function.dart';
import 'package:dsm_helper/widgets/bubble_tab_indicator.dart';
import 'package:dsm_helper/widgets/cupertino_image.dart';
import 'package:flutter/material.dart';
import 'package:neumorphic/neumorphic.dart';

class Packages extends StatefulWidget {
  @override
  _PackagesState createState() => _PackagesState();
}

class _PackagesState extends State<Packages> with SingleTickerProviderStateMixin {
  TabController _tabController;
  List banners = [];
  List others = [];
  List packages = [];
  List categories = [];
  List installedPackages = [];
  List canUpdatePackages = [];
  List launchedPackages = [];
  @override
  void initState() {
    _tabController = TabController(initialIndex: 1, length: 3, vsync: this);
    getData();
    super.initState();
  }

  getData() async {
    var res = await Api.packages();
    if (res['success']) {
      setState(() {
        banners = res['data']['banners'];
        packages = res['data']['packages'];
        categories = res['data']['categories'];
      });
    } else {}
    await getOthers();
    await getLaunchedPackages();
    await getInstalledPackages();
  }

  getOthers() async {
    var res = await Api.packages(others: true);
    if (res['success']) {
      setState(() {
        others = res['data']['packages'];
      });
    }
  }

  getLaunchedPackages() async {
    var res = await Api.launchedPackages();
    if (res['success']) {
      Map packages = res['data']['packages'];
      packages.forEach((key, value) {
        launchedPackages.add(key);
        setState(() {});
      });
    }
  }

  getInstalledPackages() async {
    var res = await Api.installedPackages();
    if (res['success']) {
      List installedPackagesInfo = res['data']['packages'];

      installedPackagesInfo.forEach((installedPackageInfo) {
        packages.forEach((package) {
          package['installed'] = package['installed'] ?? false;
          package['installed_version'] = package['installed_version'] ?? "";
          package['can_update'] = package['can_update'] ?? false;
          package['launched'] = package['launched'] ?? false;
          if (installedPackageInfo['id'] == package['id']) {
            package['installed'] = true;
            package['installed_version'] = installedPackageInfo['version'];
            package['can_update'] = Util.versionCompare(package['installed_version'], package['version']) > 0;
            package['additional'] = installedPackageInfo['additional'];
            if (package['installed']) {
              installedPackages.add(package);
            }
            if (package['can_update']) {
              canUpdatePackages.add(package);
            }
            if (launchedPackages.contains(package['id'])) {
              package['launched'] = true;
            }
          }
          setState(() {});
        });
        others.forEach((package) {
          package['installed'] = package['installed'] ?? false;
          package['installed_version'] = package['installed_version'] ?? "";
          package['can_update'] = package['can_update'] ?? false;
          package['launched'] = package['launched'] ?? false;
          if (installedPackageInfo['id'] == package['id']) {
            package['installed'] = true;
            package['installed_version'] = installedPackageInfo['version'];
            package['can_update'] = Util.versionCompare(package['version'], package['installed_version']) > 0;
            package['additional'] = installedPackageInfo['additional'];
            if (package['installed']) {
              installedPackages.add(package);
            }
            if (package['can_update']) {
              canUpdatePackages.add(package);
            }
            if (launchedPackages.contains(package['id'])) {
              package['launched'] = true;
            }
          }

          setState(() {});
        });
      });
    } else {}
  }

  List<String> getCategoryName(List categoryIds) {
    List<String> name = [];
    if (categoryIds == null) {
      return [];
    }
    for (int i = 0; i < categoryIds.length; i++) {
      categories.forEach((category) {
        if (category['id'] == categoryIds[i]) {
          name.add(category['dname']);
        }
      });
    }
    return name;
  }

  Widget _buildButton(package) {
    Widget button;
    if (package['can_update'] == null || package['installed'] == null) {
      button = NeuCard(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: NeumorphicDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(20),
        ),
        curveType: CurveType.convex,
        child: Text("获取中"),
      );
    } else if (package['can_update']) {
      button = NeuButton(
        onPressed: () {
          Util.toast("暂不支持更新套件，敬请期待");
        },
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: NeumorphicDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text("更新"),
      );
    } else if (package['installed']) {
      String text = "";
      if (package['launched']) {
        text = "已启动";
      } else if (package['additional'] != null && package['additional']['startable']) {
        text = "启动";
      } else {
        text = "已安装";
      }
      button = NeuButton(
        onPressed: () {
          if (text == "启动") {
            Util.toast("暂不支持启动套件，敬请期待");
          }
        },
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: NeumorphicDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          "$text",
          style: text == "启动" ? null : TextStyle(color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      );
    } else {
      button = NeuButton(
        onPressed: () {
          Util.toast("暂不支持安装套件，敬请期待");
        },
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: NeumorphicDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text("立即安装"),
      );
    }
    return button;
  }

  Widget _buildUpdateItem(update) {
    return NeuCard(
      width: (MediaQuery.of(context).size.width - 60) / 2,
      curveType: CurveType.flat,
      decoration: NeumorphicDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      bevel: 20,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            CupertinoExtendedImage(
              update['thumbnail'].last,
              width: 80,
            ),
            SizedBox(
              width: 10,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    update['dname'],
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16),
                  ),
                  SizedBox(
                    height: 5,
                  ),
                  Text(
                    update['version'],
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
            _buildButton(update),
          ],
        ),
      ),
    );
  }

  Widget _buildPackageItem(package, bool installed) {
    return NeuCard(
      width: (MediaQuery.of(context).size.width - 60) / 2,
      curveType: CurveType.flat,
      decoration: NeumorphicDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      bevel: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                SizedBox(
                  height: 20,
                ),
                CupertinoExtendedImage(
                  package['thumbnail'].last,
                  width: 80,
                ),
                SizedBox(
                  height: 10,
                ),
                SizedBox(
                  height: 40,
                  child: Text(
                    "${package['dname']}",
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                Text(
                  "${installed ? package['additional']['updated_at'] : getCategoryName(package['category']).length > 0 ? getCategoryName(package['category']).join(",") : package['maintainer']}",
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
          Padding(padding: EdgeInsets.all(20), child: _buildButton(package)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "套件中心",
          style: Theme.of(context).textTheme.headline6,
        ),
        brightness: Brightness.light,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
        children: [
          NeuCard(
            width: double.infinity,
            decoration: NeumorphicDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(20),
            ),
            margin: EdgeInsets.symmetric(vertical: 10, horizontal: 20),
            curveType: CurveType.flat,
            bevel: 10,
            child: TabBar(
              isScrollable: false,
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.label,
              labelColor: Colors.black,
              unselectedLabelColor: Colors.grey,
              indicator: BubbleTabIndicator(
                indicatorColor: Theme.of(context).scaffoldBackgroundColor,
                shadowColor: Util.getAdjustColor(Theme.of(context).scaffoldBackgroundColor, -20),
              ),
              tabs: [
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 10, horizontal: 5),
                  child: Text("已安装"),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 10, horizontal: 5),
                  child: Text("全部套件"),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 10, horizontal: 5),
                  child: Text("社群"),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                Container(
                  child: ListView(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                    children: [
                      if (canUpdatePackages.length > 0)
                        ListView.builder(
                          padding: EdgeInsets.only(bottom: 20),
                          itemBuilder: (content, i) {
                            return _buildUpdateItem(canUpdatePackages[i]);
                          },
                          itemCount: canUpdatePackages.length,
                          shrinkWrap: true,
                        ),
                      Wrap(
                        runSpacing: 20,
                        spacing: 20,
                        children: installedPackages.map((package) {
                          return _buildPackageItem(package, true);
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                Container(
                  child: ListView(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                    children: [
                      Wrap(
                        runSpacing: 20,
                        spacing: 20,
                        children: packages.map((package) {
                          return _buildPackageItem(package, false);
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                Container(
                  child: ListView(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                    children: [
                      Wrap(
                        runSpacing: 20,
                        spacing: 20,
                        children: others.map((package) {
                          return _buildPackageItem(package, false);
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}