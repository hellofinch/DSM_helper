import 'dart:io';

import 'package:dsm_helper/util/function.dart';
import 'package:dsm_helper/widgets/cupertino_image.dart';
import 'package:flutter/material.dart';

class FileIcon extends StatelessWidget {
  final FileType fileType;
  final String thumb;
  final bool network;
  FileIcon(this.fileType, {this.thumb, this.network = true});
  @override
  Widget build(BuildContext context) {
    if (fileType == FileType.folder) {
      return Image.asset(
        "assets/icons/folder.png",
        width: 40,
        height: 40,
      );
    } else if (fileType == FileType.music) {
      return Icon(Icons.music_note_rounded);
    } else if (fileType == FileType.movie) {
      return Image.asset(
        "assets/icons/movie.png",
        width: 40,
        height: 40,
      );
    } else if (fileType == FileType.image) {
      return thumb == null
          ? Image.asset(
              "assets/icons/image.png",
              width: 40,
              height: 40,
            )
          : network
              ? CupertinoExtendedImage(
                  Util.baseUrl + "/webapi/entry.cgi?path=${Uri.encodeComponent(thumb)}&size=small&api=SYNO.FileStation.Thumb&method=get&version=2&_sid=${Util.sid}&animate=true",
                  width: 40,
                  height: 40,
                  fit: BoxFit.contain,
                )
              : Image.file(
                  File(thumb),
                  fit: BoxFit.contain,
                  width: 40,
                  height: 40,
                );
    } else if (fileType == FileType.word) {
      return Image.asset(
        "assets/icons/word.png",
        width: 40,
        height: 40,
      );
    } else if (fileType == FileType.ppt) {
      return Image.asset(
        "assets/icons/ppt.png",
        width: 40,
        height: 40,
      );
    } else if (fileType == FileType.excel) {
      return Image.asset(
        "assets/icons/excel.png",
        width: 40,
        height: 40,
      );
    } else if (fileType == FileType.pdf) {
      return Image.asset(
        "assets/icons/pdf.png",
        width: 40,
        height: 40,
      );
    } else if (fileType == FileType.zip) {
      return Image.asset(
        "assets/icons/zip.png",
        width: 40,
        height: 40,
      );
    } else if (fileType == FileType.ps) {
      return Image.asset(
        "assets/icons/psd.png",
        width: 40,
        height: 40,
      );
    } else if (fileType == FileType.text) {
      return Image.asset(
        "assets/icons/txt.png",
        width: 40,
        height: 40,
      );
    } else if (fileType == FileType.code) {
      return Image.asset(
        "assets/icons/code.png",
        width: 40,
        height: 40,
      );
    } else if (fileType == FileType.apk) {
      return Image.asset(
        "assets/icons/apk.png",
        width: 40,
        height: 40,
      );
    } else if (fileType == FileType.iso) {
      return Image.asset(
        "assets/icons/iso.png",
        width: 40,
        height: 40,
      );
    } else {
      return Image.asset(
        "assets/icons/other.png",
        width: 40,
        height: 40,
      );
    }
  }
}
