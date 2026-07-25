# 华阳签 — 安装说明

显示名：**华阳签** · Bundle ID：`com.huayang.sign`

## 卡点

当前电脑是 **Windows**，没有 Xcode，**无法在本机生成 IPA**，因此我现在没法「直接」装到手机。

## 你给我 IPA 之后（或 Mac 编好后）

把 `HuaYangSign.ipa` 放到本机任意路径，告诉我，我会立刻：

1. 上传到 `http://192.168.2.175:8090/upload_file`
2. `install_app` 装进手机（TrollStore/越狱通道）

Mac 一键打包：

```bash
cd LCSignClone && ./scripts/build-ipa.sh
```
