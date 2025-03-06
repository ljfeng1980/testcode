import 'dart:io';
import 'dart:typed_data';
import 'package:get/get.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

//class FileController extends GetxController {
Future<String> gifToBin(String gifPath) async {
  String name = "output";
  String binFilePath =
      gifPath.replaceAll('.gif', '').replaceAll('pic/', 'output/') + ".bin";
  final (frameCount, averageDuration, width, height, folderPath) =
      await _convertGifToImages(name, gifPath);

  //String folderPath = '$name/$newName';
  await _packImagesToBin(
      folderPath, binFilePath, frameCount, averageDuration, width, height);

  final binFile = File(binFilePath);
  if (await binFile.exists()) {
    print(">>>>> 动画打包成功，输出文件: $binFilePath <<<<<");
    return binFilePath;
  } else {
    throw Exception("打包失败，文件未生成: $binFilePath");
  }
}

Future<(int, int, int, int, String)> _convertGifToImages(
    String name, String gifPath) async {
  // 获取临时目录作为基础路径
  final tempBaseDir = await getTemporaryDirectory();
  final outputPath = p.join(tempBaseDir.path, name);
  print("准备创建目录: $outputPath");
  final gifFile = File(gifPath);
  if (!gifFile.existsSync()) {
    throw Exception("GIF 文件不存在: $gifPath");
  }

  // 解码 GIF
  final gifBytes = gifFile.readAsBytesSync();
  print("开始解码GIF: ${DateTime.now()}");
  final gif = img.decodeGif(gifBytes);
  print("解码完成: ${DateTime.now()}");
  if (gif == null) {
    throw Exception("无法解码 GIF 文件: $gifPath");
  }

  // 清理目录
  final dir = Directory(outputPath);
  if (dir.existsSync()) {
    dir.listSync().forEach((entity) {
      if (entity is Directory) {
        entity.deleteSync(recursive: true);
      }
    });
  } else {
    dir.createSync(recursive: true);
    print("创建目录: $name");
  }

  // 创建 temp 目录
  final tempPath = p.join(outputPath, "temp"); // 修改为基于 outputPath
  final tempDir = Directory(tempPath);
  if (tempDir.existsSync()) {
    print('$tempPath exists');
  } else {
    tempDir.createSync();
  }

  // 解析 GIF 帧持续时间
  final frameDurations = _parseGifFrameDurations(gifBytes, gif.frames.length);

  // 处理 GIF 帧
  int frameCount = 0;
  for (int i = 0; i < gif.frames.length; i++) {
    final frame = gif.frames[i];
    frameCount++;

    // 使用解析出的持续时间
    int duration = frameDurations[i];
    if (duration == 0) duration = 100; // 默认 100ms

    // JPG 格式，调整尺寸为 16 的倍数
    int width = frame.width;
    int height = frame.height;
    if (width % 16 != 0) width = ((width / 16).ceil()) * 16;
    if (height % 16 != 0) height = ((height / 16).ceil()) * 16;

    // 创建白色背景图像
    final jpgImage = img.Image(width: width, height: height, numChannels: 3);
    img.fill(jpgImage, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(jpgImage, frame, dstX: 0, dstY: 0);

    // 保存为 JPG
    final jpgBytes = img.encodeJpg(jpgImage);
    File('$tempPath/frame_${frameCount.toString().padLeft(5, '0')}.jpg')
        .writeAsBytesSync(jpgBytes);
  }

  // 计算平均帧间隔
  int averageDuration = frameDurations.isEmpty
      ? 100
      : (frameDurations.reduce((a, b) => a + b) ~/ frameDurations.length);
  if (averageDuration == 0) averageDuration = 100;

  // 重命名 temp 目录
  String newName = "${averageDuration}ms";
  final newPath = p.join(outputPath, newName);
  tempDir.renameSync(newPath);

  return (
    frameCount,
    averageDuration,
    gif.width,
    gif.height,
    newPath,
  );
}

// 手动解析 GIF 帧持续时间
List<int> _parseGifFrameDurations(Uint8List gifBytes, int frameCount) {
  final durations = <int>[];
  int pos = 0;

  // 跳过 GIF 头（6 字节）
  if (gifBytes.length < 6 ||
      String.fromCharCodes(gifBytes.sublist(0, 3)) != "GIF") {
    throw Exception("无效的 GIF 文件");
  }
  pos += 6;

  // 跳过 Logical Screen Descriptor（7 字节）
  pos += 7;

  // 处理全局颜色表（如果有）
  int packedField = gifBytes[pos - 1];
  if ((packedField & 0x80) != 0) {
    int colorTableSize = 3 * (1 << ((packedField & 0x07) + 1));
    pos += colorTableSize;
  }

  int frameIndex = 0;
  while (pos < gifBytes.length && frameIndex < frameCount) {
    if (gifBytes[pos] == 0x21) {
      // Extension Introducer
      pos++;
      if (gifBytes[pos] == 0xF9) {
        // Graphic Control Extension
        pos++;
        int blockSize = gifBytes[pos];
        if (blockSize != 4) throw Exception("无效的 Graphic Control Extension");
        pos++;

        // 跳过 packed field (1 字节)
        pos++;

        // 读取延时时间 (2 字节，单位 1/100 秒)
        int delayTime = ByteData.sublistView(gifBytes, pos, pos + 2)
            .getUint16(0, Endian.little);
        durations.add(delayTime * 10); // 转换为毫秒
        pos += 2;

        // 跳过 Transparent Color Index 和 Block Terminator
        pos += 2;
        frameIndex++;
      } else {
        // 跳过其他扩展块
        pos++;
        int blockSize = gifBytes[pos];
        pos += blockSize + 1;
      }
    } else if (gifBytes[pos] == 0x2C) {
      // Image Descriptor
      // 跳过 Image Descriptor (9 字节)
      pos += 9;

      // 处理局部颜色表（如果有）
      int packedField = gifBytes[pos - 1];
      if ((packedField & 0x80) != 0) {
        int colorTableSize = 3 * (1 << ((packedField & 0x07) + 1));
        pos += colorTableSize;
      }

      // 跳过图像数据
      pos++; // LZW Minimum Code Size
      while (gifBytes[pos] != 0) {
        int blockSize = gifBytes[pos];
        pos += blockSize + 1;
      }
      pos++; // Block Terminator
    } else if (gifBytes[pos] == 0x3B) {
      // Trailer
      break;
    } else {
      pos++;
    }
  }

  // 如果帧数不匹配，使用默认值填充
  while (durations.length < frameCount) {
    durations.add(100); // 默认 100ms
  }

  return durations;
}

Future<void> _packImagesToBin(
  String folderPath,
  String binFilePath,
  int frameCount,
  int imageInterval,
  int width,
  int height,
) async {
  print("开始打包: $folderPath -> $binFilePath");

  final folder = Directory(folderPath);
  final imageFiles = folder
      .listSync()
      .whereType<File>()
      .map((f) => f.path.split('/').last)
      .toList();
  print("找到 ${imageFiles.length} 个图像文件: $imageFiles");

  const int checksum = 0x12345678;
  int headerSize = 24 + imageFiles.length * 16;

  int totalSize = headerSize;
  for (var imageFile in imageFiles) {
    int fileSize = File('$folderPath/$imageFile').lengthSync();
    totalSize += fileSize + 32 + 4; // 增加4字节用于链接地址
    print("文件 $imageFile 大小: $fileSize, 累计总大小: $totalSize");
  }
  print("计算总大小: $totalSize 字节 (头部: $headerSize)");

  final byteData = ByteData(totalSize);
  int offset = 0;

  byteData.setUint32(offset, checksum, Endian.little);
  offset += 4;
  byteData.setUint32(offset, headerSize, Endian.little);
  offset += 4;
  byteData.setUint32(offset, frameCount, Endian.little);
  offset += 4;
  byteData.setUint32(offset, imageInterval, Endian.little);
  offset += 4;
  final folderPathBytes =
      folderPath.padRight(12, '\0').substring(0, 12).codeUnits;
  for (var byte in folderPathBytes) {
    byteData.setUint8(offset, byte);
    offset++;
  }
  byteData.setUint32(offset, 0, Endian.little);
  offset += 4;
  print("头部写入完成，偏移量: $offset");

  final addressTableStart = offset;
  offset += imageFiles.length * 16;
  print("地址表开始位置: $addressTableStart, 当前偏移量: $offset");

  int firstPicAddr = 0;
  for (int i = 0; i < imageFiles.length; i++) {
    final imageFile = imageFiles[i];
    final imagePath = '$folderPath/$imageFile';
    final imageBytes = File(imagePath).readAsBytesSync();
    int sour = offset;

    if (i == 0) firstPicAddr = sour;

    int tableOffset = addressTableStart + i * 16;
    final imageNameBytes =
        imageFile.padRight(12, '\0').substring(0, 12).codeUnits;
    for (int j = 0; j < 12; j++) {
      byteData.setUint8(tableOffset + j, imageNameBytes[j]);
    }
    byteData.setUint32(tableOffset + 12, sour, Endian.little);
    print("帧 $i: 地址表写入 - 名称: $imageFile, 偏移: $sour");

    byteData.setUint32(offset, sour, Endian.little);
    offset += 4;
    byteData.setUint32(offset, imageBytes.length + 32, Endian.little);
    offset += 4;

    int format = imageFile.endsWith('.jpg') ? 11 : 0;
    byteData.setUint8(offset, format);
    offset += 1;
    byteData.setUint8(offset, 0);
    offset += 1;
    byteData.setUint16(offset, 0, Endian.little);
    offset += 2;
    byteData.setUint16(offset, width, Endian.little);
    offset += 2;
    byteData.setUint16(offset, height, Endian.little);
    offset += 2;
    byteData.setUint32(offset, sour + 32, Endian.little);
    offset += 4;
    byteData.setUint32(offset, imageBytes.length, Endian.little);
    offset += 4;
    byteData.setUint32(offset, 0, Endian.little);
    offset += 4;
    byteData.setUint32(offset, 0, Endian.little);
    offset += 4;

    print(
        "帧 $i: 开始写入图像数据，当前偏移: $offset, 剩余空间: ${totalSize - offset}, 数据大小: ${imageBytes.length}");
    for (var byte in imageBytes) {
      if (offset >= totalSize) {
        throw Exception("偏移量 $offset 超出缓冲区大小 $totalSize");
      }
      byteData.setUint8(offset, byte);
      offset++;
    }

    int sour2 = offset;
    byteData.setUint32(sour + 4,
        i + 1 == imageFiles.length ? firstPicAddr : sour2, Endian.little);
    print("帧 $i: 数据写入完成 - 大小: ${imageBytes.length}, 下一帧偏移: $sour2");
  }

  byteData.setUint32(28, offset - 1, Endian.little);
  print("结束地址更新: ${offset - 1}");

  File(binFilePath).writeAsBytesSync(byteData.buffer.asUint8List());
  print("打包完成！文件写入: $binFilePath");
}

/*Future<void> _packImagesToBin(
  String folderPath,
  String binFilePath,
  int frameCount,
  int imageInterval,
  int width,
  int height,
) async {
  print("开始打包: $folderPath -> $binFilePath");

  final folder = Directory(folderPath);
  final imageFiles = folder
      .listSync()
      .whereType<File>()
      .map((f) => f.path.split('/').last)
      .toList();
  print("找到 ${imageFiles.length} 个图像文件: $imageFiles");

  const int checksum = 0x12345678;
  int headerSize = 24 + imageFiles.length * 16;

  int totalSize = headerSize;
  for (var imageFile in imageFiles) {
    int fileSize = File('$folderPath/$imageFile').lengthSync();
    totalSize += fileSize + 32;
    print("文件 $imageFile 大小: $fileSize, 累计总大小: $totalSize");
  }
  print("计算总大小: $totalSize 字节 (头部: $headerSize)");

  final byteData = ByteData(totalSize);
  int offset = 0;

  byteData.setUint32(offset, checksum, Endian.little);
  offset += 4;
  byteData.setUint32(offset, headerSize, Endian.little);
  offset += 4;
  byteData.setUint32(offset, frameCount, Endian.little);
  offset += 4;
  byteData.setUint32(offset, imageInterval, Endian.little);
  offset += 4;
  final folderPathBytes =
      folderPath.padRight(12, '\0').substring(0, 12).codeUnits;
  for (var byte in folderPathBytes) {
    byteData.setUint8(offset, byte);
    offset++;
  }
  byteData.setUint32(offset, 0, Endian.little);
  offset += 4;
  print("头部写入完成，偏移量: $offset");

  final addressTableStart = offset;
  offset += imageFiles.length * 16;
  print("地址表开始位置: $addressTableStart, 当前偏移量: $offset");

  int firstPicAddr = 0;
  for (int i = 0; i < imageFiles.length; i++) {
    final imageFile = imageFiles[i];
    final imagePath = '$folderPath/$imageFile';
    final imageBytes = File(imagePath).readAsBytesSync();
    int sour = offset;

    if (i == 0) firstPicAddr = sour;

    int tableOffset = addressTableStart + i * 16;
    final imageNameBytes =
        imageFile.padRight(12, '\0').substring(0, 12).codeUnits;
    for (int j = 0; j < 12; j++) {
      byteData.setUint8(tableOffset + j, imageNameBytes[j]);
    }
    byteData.setUint32(tableOffset + 12, sour, Endian.little);
    print("帧 $i: 地址表写入 - 名称: $imageFile, 偏移: $sour");

    byteData.setUint32(offset, sour, Endian.little);
    offset += 4;
    byteData.setUint32(offset, imageBytes.length + 32, Endian.little);
    offset += 4;

    int format = imageFile.endsWith('.jpg') ? 11 : 0;
    byteData.setUint8(offset, format);
    offset += 1;
    byteData.setUint8(offset, 0);
    offset += 1;
    byteData.setUint16(offset, 0, Endian.little);
    offset += 2;
    byteData.setUint16(offset, width, Endian.little);
    offset += 2;
    byteData.setUint16(offset, height, Endian.little);
    offset += 2;
    byteData.setUint32(offset, sour + 32, Endian.little);
    offset += 4;
    byteData.setUint32(offset, imageBytes.length, Endian.little);
    offset += 4;
    byteData.setUint32(offset, 0, Endian.little);
    offset += 4;
    byteData.setUint32(offset, 0, Endian.little);
    offset += 4;

    print(
        "帧 $i: 开始写入图像数据，当前偏移: $offset, 剩余空间: ${totalSize - offset}, 数据大小: ${imageBytes.length}");
    for (var byte in imageBytes) {
      if (offset >= totalSize) {
        throw Exception("偏移量 $offset 超出缓冲区大小 $totalSize");
      }
      byteData.setUint8(offset, byte);
      offset++;
    }

    int sour2 = offset;
    byteData.setUint32(sour + 4,
        i + 1 == imageFiles.length ? firstPicAddr : sour2, Endian.little);
    print("帧 $i: 数据写入完成 - 大小: ${imageBytes.length}, 下一帧偏移: $sour2");
  }

  byteData.setUint32(28, offset - 1, Endian.little);
  print("结束地址更新: ${offset - 1}");

  File(binFilePath).writeAsBytesSync(byteData.buffer.asUint8List());
  print("打包完成！文件写入: $binFilePath");
}*/
//}
