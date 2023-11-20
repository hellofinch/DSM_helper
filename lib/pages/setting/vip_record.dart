import 'package:cool_ui/cool_ui.dart';
import 'package:dsm_helper/models/setting/vip_record_model.dart';
import 'package:dsm_helper/themes/app_theme.dart';
import 'package:dsm_helper/util/function.dart';
import 'package:dsm_helper/widgets/neu_back_button.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:neumorphic/neumorphic.dart';

class VipRecord extends StatefulWidget {
  const VipRecord({Key key}) : super(key: key);

  @override
  State<VipRecord> createState() => _VipRecordState();
}

class _VipRecordState extends State<VipRecord> {
  List<VipRecordModel> records = [];
  bool loading = true;
  @override
  void initState() {
    getData();
    super.initState();
  }

  getData() async {
    try {
      records = await VipRecordModel.fetch();
      setState(() {
        loading = false;
      });
    } catch (e) {
      Util.toast(e.message);
      Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: AppBackButton(context),
        title: Text("开通记录"),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text("注意：仅包含积分兑换与在线支付方式的开通记录"),
          ),
          Expanded(
            child: loading
                ? Center(
                    child: CupertinoActivityIndicator(),
                  )
                : records.length > 0
                    ? ListView.builder(
                        itemBuilder: (context, i) {
                          return _buildRecordItem(records[i]);
                        },
                        itemCount: records.length,
                      )
                    : Center(
                        child: Text(
                          "暂无开通记录",
                          style: TextStyle(color: AppTheme.of(context).placeholderColor),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordItem(VipRecordModel record) {
    return NeuCard(
      margin: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      bevel: 20,
      curveType: CurveType.flat,
      decoration: NeumorphicDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("开通方式：${record.type == 1 ? '积分兑换' : '在线支付'} - ${record.cost}"),
                Text("开通时间：${record.createTime}"),
                Text("生效时间：${record.startTime}"),
                Text("过期时间：${record.isForever == 0 ? record.endTime : '永不过期'}"),
              ],
            ),
          ),
          if (record.activityId != null && record.activityId > 0)
            NeuButton(
              onPressed: () async {
                var hide = showWeuiLoadingToast(context: context);
                String userToken = await Util.getStorage("user_token");
                var res = await Util.post("${Util.appUrl}/vip/redemption", data: {"token": userToken, "id": record.id});
                print(res);
                hide();
                if (res['code'] == 0) {
                  Util.toast(res['msg']);
                } else {
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
                                      "兑换码",
                                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                                    ),
                                    SizedBox(
                                      height: 16,
                                    ),
                                    NeuCard(
                                      decoration: NeumorphicDecoration(
                                        color: Theme.of(context).scaffoldBackgroundColor,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      bevel: 20,
                                      curveType: CurveType.flat,
                                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                      child: Text("${res['data']['code']}"),
                                    ),
                                    SizedBox(
                                      height: 20,
                                    ),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: NeuButton(
                                            onPressed: () {
                                              Navigator.of(context).pop();
                                            },
                                            decoration: NeumorphicDecoration(
                                              color: Theme.of(context).scaffoldBackgroundColor,
                                              borderRadius: BorderRadius.circular(25),
                                            ),
                                            bevel: 20,
                                            padding: EdgeInsets.symmetric(vertical: 10),
                                            child: Text(
                                              "关闭",
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
                                              Clipboard.setData(ClipboardData(text: res['data']['code']));
                                              Util.toast("兑换码已复制到剪贴板");
                                            },
                                            decoration: NeumorphicDecoration(
                                              color: Theme.of(context).scaffoldBackgroundColor,
                                              borderRadius: BorderRadius.circular(25),
                                            ),
                                            bevel: 20,
                                            padding: EdgeInsets.symmetric(vertical: 10),
                                            child: Text(
                                              "复制",
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
                    },
                  );
                }
              },
              decoration: NeumorphicDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(20),
              ),
              bevel: 5,
              padding: EdgeInsets.symmetric(horizontal: 15, vertical: 7),
              child: Text(
                "领取兑换码",
                style: TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}
