# Remoto

用 iPhone 控制 Sony BRAVIA 电视的原生 App。

局域网直连，不依赖 Home Assistant，不依赖云端，无账号。

---

## 与 TVRemoteKit 的关系

本仓库是 **App**，协议实现在 **SDK** 里，两者分开维护：

| 仓库 | 职责 |
|---|---|
| [TVRemoteKit](../TVRemoteKit) | Swift SDK —— 设备发现、协议、认证、按键。跨平台，无 UI |
| **Remoto**（本仓库） | iOS App —— UI、交互、设备管理、用户设置 |

依赖方向是单向的：`Remoto → TVRemoteKit`。

任何协议层的问题都应该在 TVRemoteKit 修，而不是在 App 里打补丁。这是刻意的约束 —— SDK 是真正要长期维护的东西，App 是它的第一个使用者，同时充当 SDK 的 API 设计验证器：**如果某个功能在 App 里写起来别扭，说明 SDK 的 API 设计有问题。**

## 状态

🚧 早期开发中。SDK 尚在 Day 1 阶段，本仓库暂时只有骨架。

## 目标设备

首个验证设备：Sony KD-65X8500F（2018 款 Android TV，接口版本 5.4.0）。

其他 BRAVIA 机型的兼容性依赖 TVRemoteKit 的能力探测（`getSupportedApiInfo` / `getRemoteControllerInfo`），不做型号硬编码。

## 电视端前置设置

```
设置 → 网络和互联网 → 家庭网络设置 → IP 控制
    → 验证方式 →「普通和预共享密钥」
    → 设置预共享密钥
设置 → 网络和互联网 → 远程设备设置 → 远程控制 → 开启
```

## 开发约束

- **无付费 Apple Developer 账号** —— 免费签名，真机证书 7 天过期需重新安装
- **不能使用需特批授权的能力** —— SSDP 组播、Wake-on-LAN 广播均不可用
- 设备发现走 Bonjour + 子网单播扫描（均无需 entitlement）

详见 TVRemoteKit `docs/plan.md` 第六章。

## 隐私

- 预共享密钥存 Keychain，不写入代码、不写入仓库、不上传任何服务器
- App 不含任何网络请求，除了直接发往用户自己电视的局域网请求

## License

MIT
