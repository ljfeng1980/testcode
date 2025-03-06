
from PIL import Image, ImageSequence
import os
import shutil

def match_value(name):
    with open('cfg.txt', 'r') as file:
        for line in file:
            if name in line:
                if 'bmp' in line:
                    return 1
                elif 'jpg' in line:
                    return 2
                elif 'png' in line:
                    return 0
    return 0

def convert_gif_to_images(name , gif_path, type):
    # 指定目录路径
    dir_path = name # "/path/to/directory"
    
    # 删除目录下所有文件夹
    for folder_name in os.listdir(dir_path):
        folder_path = os.path.join(dir_path, folder_name)
        if os.path.isdir(folder_path):
            shutil.rmtree(folder_path)
    
    # 创建temp目录
    temp_path = os.path.join(dir_path, "temp")
    
    # 使用os.makedirs()函数创建文件夹 
    if os.path.exists(temp_path):
        print(temp_path,'exists')
    else:
        os.makedirs(temp_path)

    with Image.open(gif_path) as img:
        frame_durations = []  # 存储每帧间隔
        frame_count = 0  # 总帧数
        
        for frame in ImageSequence.Iterator(img):
            frame_count += 1
            frame_durations.append(frame.info['duration'])  # 获取当前帧的持续时间

            if type == 0:
                frame.save(temp_path+'/' +  f'frame_{frame_count}.png', 'PNG')  # 保存为PNG
            elif type == 1:
                # 创建一个新的BMP图像，使用白色作为背景色
                bmp_image = Image.new("RGB", frame.size, (255, 255, 255))
                bmp_image.paste(frame, (0, 0), mask=frame.convert("RGBA"))
                bmp_image.save(temp_path+'/' + f'frame_{frame_count}.bmp', 'BMP')  # 保存为BMP
                #bmp_image.save(temp_path+'/' +  f'frame_{frame_count}.jpg')  # 保存为PNG
            elif type == 2:
                
                width, height = frame.size
                if width % 16 != 0:
                    width = (width // 16 + 1) * 16
                if height % 16 != 0:
                    height = (height // 16 + 1) * 16

                # 创建一个新的BMP图像，使用白色作为背景色
                bmp_image = Image.new("RGB", (width, height), (255, 255, 255))
                bmp_image.paste(frame, (0, 0), mask=frame.convert("RGBA"))
                bmp_image.save(temp_path + '/' + f'frame_{frame_count:05d}.jpg')  # 保存为jpg

        print(frame_durations)
        # 自定义修改temp目录名字        
        average_duration = sum(frame_durations) / len(frame_durations)
        print("平均值:", average_duration)
        if average_duration == 0:
            average_duration = 100
            
        new_name = "{}ms".format(int(average_duration))
        new_path = os.path.join(dir_path, new_name)
        print(temp_path, new_path)
        os.rename(temp_path, new_path)
                
        average_duration=int(average_duration)
                
        return frame_count, average_duration, img.size, new_name


import os
import struct

from PIL import Image

def get_image_size(image_path):
    try:
        with Image.open(image_path) as img:
            width, height = img.size
            return width, height
    except IOError:
        print("无法打开图片文件:", image_path)
        return None

def is_jpg(file_path):
    try:
        with Image.open(file_path) as img:
            return img.format == 'JPEG'
    except IOError:
        print("无法打开文件:", file_path)
        return False


def pack_images_to_bin(folder_path, bin_file_path, checksum, address_list_length, image_interval, gif_image_path):
    # 获取文件夹中的所有图片文件
    image_files = [f for f in os.listdir(folder_path) if os.path.isfile(os.path.join(folder_path, f))]

    # 计算需要的字节数
    header_size = 24 + len(image_files) * 16
    total_size = header_size + sum(os.path.getsize(os.path.join(folder_path, f)) for f in image_files)

    image_files_num = len(image_files)
    print("文件列表大小：", image_files_num)
    
    # 打开二进制文件
    with open(bin_file_path, 'wb') as bin_file:
        # 写入头信息
        bin_file.write(struct.pack('I', checksum))
        bin_file.write(struct.pack('I', image_files_num*16 + 24))
        
        bin_file.write(struct.pack('II12sI', image_files_num, image_interval, folder_path.encode('utf-8'), 0))

        # 写入每个图片的地址和名字
        for image_file in image_files:
            image_path = os.path.join(folder_path, image_file)
            bin_file.write(struct.pack('12s4s', b'', b''))

        count = 0
        first_pic_addr = 0
        all_pic = len(image_files)
        # 写入每张图片的数据
        for image_file in image_files:
        
            image_path = os.path.join(folder_path, image_file)
            image_size = os.path.getsize(image_path)
            width, height = get_image_size(gif_image_path)
            with open(image_path, 'rb') as image:
                print(image_path)
                sour = bin_file.tell()
                if count == 0:
                    first_pic_addr = sour
                    
                #print(sour)
                bin_file.seek(32 + count*16,0)
                count = count+1
                bin_file.write(struct.pack('12sI', image_file.encode('utf-8'), sour))                
                bin_file.seek(sour,0)
                
                bin_file.write(struct.pack('I', sour))
                bin_file.write(struct.pack('I', image_size + 32))
                
                # enum {
                    # PIXEL_FMT_ARGB8888,0
                    # PIXEL_FMT_RGB888,1
                    # PIXEL_FMT_RGB565,2
                    # PIXEL_FMT_L8,3
                    # PIXEL_FMT_AL88,4
                    # PIXEL_FMT_AL44,5
                    # PIXEL_FMT_A8,6
                    # PIXEL_FMT_L1,7
                    # PIXEL_FMT_ARGB8565,8
                    # PIXEL_FMT_OSD16,9
                    # PIXEL_FMT_SOLID,10
                    # PIXEL_FMT_JPEG,11
                    # PIXEL_FMT_UNKNOW,12
                # };
                # struct image_file {
                    # u8 format;
                    # u8 compress;
                    # u16 data_crc;
                    # u16 width;
                    # u16 height;
                    # u32 offset;
                    # u32 len;
                    # u32 unzipOffset;
                    # u32 unzipLen;
                # };
                format = 0
                if is_jpg(image_path):
                    #print("是JPG图片")
                    format = 11
                compress = 0
                data_crc = 0
                width = width
                height = height
                offset = sour+32
                image_size = image_size
                unzipOffset = 0
                unzipLen = 0
                bin_file.write(struct.pack('BBHHHIIII', format, compress, data_crc, width, height, offset, image_size, unzipOffset, unzipLen))
                bin_file.write(image.read())
                # 补充对齐字节
                # padding_bytes = (4 - (bin_file.tell() % 4)) % 4
                # data = b'xxxxxx'
                # bin_file.write(data[:padding_bytes])
        
                sour2 = bin_file.tell()
                bin_file.seek(sour+4,0)
                if all_pic <= count:
                    print("返回第一张图")
                    bin_file.write(struct.pack('I', first_pic_addr))
                else:
                    bin_file.write(struct.pack('I', sour2))
                bin_file.seek(sour2,0)
        
        with open(image_path, 'rb') as image:
            imgs_end_addr = bin_file.tell()
            bin_file.seek(28, 0)
            bin_file.write(struct.pack('I', imgs_end_addr-1))
        
    print("打包完成！")

    
def gif_to_bin(gif_path):
    # 用户输入参数
    name = "output"
    #gif_path = input("请输入GIF文件路径：")


    frame_count, average_duration, size, new_name = convert_gif_to_images(name , gif_path, 2)
        

    # 使用示例
    folder_path = name + '/' + new_name

    print(gif_path)


    bin_file_path = gif_path.replace('.gif','').replace('pic/', 'output/').replace('pic\\', 'output\\') +".bin"
    checksum = 0x12345678
    address_list_length = 0
    image_interval = average_duration

    pack_images_to_bin(folder_path, bin_file_path, checksum, address_list_length, image_interval, gif_path)


    # 加入暂停
    print(">>>>> 动画打包成功，按回车键结束... <<<<<")

def jpg_to_bin(jpg_path):
    bin_file_path = jpg_path.replace('.jpg','').replace('pic/', 'output/').replace('pic\\', 'output\\') +".bin"
    image_size = os.path.getsize(jpg_path)
    width, height = get_image_size(jpg_path)
    with open(jpg_path, 'rb') as image:
        with open(bin_file_path, 'wb') as bin_file:
            print(jpg_path)
            bin_file.write("IMB\0".encode())
            sour = bin_file.tell()
                
                          
            bin_file.seek(sour,0)
            
            bin_file.write(struct.pack('I', sour))
            bin_file.write(struct.pack('I', image_size + 32))
            
            # enum {
                # PIXEL_FMT_ARGB8888,0
                # PIXEL_FMT_RGB888,1
                # PIXEL_FMT_RGB565,2
                # PIXEL_FMT_L8,3
                # PIXEL_FMT_AL88,4
                # PIXEL_FMT_AL44,5
                # PIXEL_FMT_A8,6
                # PIXEL_FMT_L1,7
                # PIXEL_FMT_ARGB8565,8
                # PIXEL_FMT_OSD16,9
                # PIXEL_FMT_SOLID,10
                # PIXEL_FMT_JPEG,11
                # PIXEL_FMT_UNKNOW,12
            # };
            # struct image_file {
                # u8 format;
                # u8 compress;
                # u16 data_crc;
                # u16 width;
                # u16 height;
                # u32 offset;
                # u32 len;
                # u32 unzipOffset;
                # u32 unzipLen;
            # };
            format = 0
            if is_jpg(jpg_path):
                #print("是JPG图片")
                format = 11
            compress = 0
            data_crc = 0
            width = width
            height = height
            offset = sour+32
            image_size = image_size
            unzipOffset = 0
            unzipLen = 0
            bin_file.write(struct.pack('BBHHHIIII', format, compress, data_crc, width, height, offset, image_size, unzipOffset, unzipLen))
            bin_file.write(image.read())
            # 补充对齐字节
            # padding_bytes = (4 - (bin_file.tell() % 4)) % 4
            # data = b'xxxxxx'
            # bin_file.write(data[:padding_bytes])






